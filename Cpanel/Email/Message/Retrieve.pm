package Cpanel::Email::Message::Retrieve;

# cpanel - Cpanel/Email/Message/Retrieve.pm        Copyright 2022 cPanel, L.L.C.
#                                                           All rights reserved.
# copyright@cpanel.net                                         http://cpanel.net
# This code is subject to the cPanel license. Unauthorized copying is prohibited

use strict;

use Cpanel::FastSpawn::InOut             ();
use Cpanel::Locale                       ();
use Cpanel::PwCache                      ();
use Cpanel::Email::Archive               ();
use Cpanel::Exim::Utils                  ();
use Cpanel::Sys::Hostname                ();
use Cpanel::AccessIds::ReducedPrivileges ();
use Cpanel::Validate::Username           ();
use Cpanel::AcctUtils::DomainOwner::Tiny ();
use Cpanel::AcctUtils::Domain            ();
use Cpanel::Dovecot::Utils               ();

my $locale;
my $hostname;

# If the value in %MESSAGE_LOCATIONS contains an arrayref, retrieve_message_filehandle
# will also examine the locations referenced in value of the each item in the arrayref
#
# For example
#
# 'all_dovecot' => [ ['dovecot_delivery','dovecot_virtual_delivery'], "%homedir%/mail/new/%time%." ],
#
# Would attempt to retrieve the message from all the locations
# that the dovecot_delivery and dovecot_virtual_delivery keys referenced
# as well as the non-arrayref key '%homedir%/mail/new/%time%.'
#
my %MESSAGE_LOCATIONS = (
    'local_delivery'                      => [ '%homedir%/mail/cur/%time%.',       '%homedir%/mail/new/%time%.', ],                                                  #tested on sin
    'local_delivery_spam'                 => [ '%homedir%/mail/.spam/cur/%time%.', '%homedir%/mail/.spam/new/%time%.' ],
    'dovecot_delivery_spam'               => ["dovecot:%localpart%:INBOX.spam"],                                                                                     #tested on sin
    'address_directory'                   => [ '%path%/cur/%time%.', '%path%/new/%time%.', "dovecot:%localpart%@%domain%:%mail_from_path%" ],                        #tested on mx1
    'address_file'                        => ['%path%/inbox'],
    'virtual_userdelivery_spam'           => [ '%homedir%/mail/%domain%/%localpart%/.spam/cur/%time%.', '%homedir%/mail/%domain%/%localpart%/.spam/new/%time%.' ],
    'dovecot_virtual_delivery_spam'       => ['dovecot:%localpart%@%domain%:INBOX.spam'],
    'local_boxtrapper_delivery'           => [ '%homedir%/etc/boxtrapper/queue/[^-]+-%time%.msg',      [ 'local_delivery', 'dovecot_delivery' ] ],
    'virtual_boxtrapper_userdelivery'     => [ [ 'virtual_userdelivery', 'dovecot_virtual_delivery' ], '%homedir%/etc/%domain%/%localpart%/boxtrapper/queue/[^-]+-%time%.msg' ],
    'virtual_userdelivery'                => [ '%homedir%/mail/%domain%/%localpart%/cur/%time%.',      '%homedir%/mail/%domain%/%localpart%/new/%time%.' ],
    'dovecot_delivery'                    => ['dovecot:%localpart%:%mailbox%'],
    'dovecot_delivery_no_batch'           => ['dovecot:%localpart%:%mailbox%'],
    'dovecot_virtual_delivery'            => ['dovecot:%localpart%@%domain%:%mailbox%'],
    'dovecot_virtual_delivery_no_batch'   => ['dovecot:%localpart%@%domain%:%mailbox%'],
    'archiver_incoming_local_user_method' => [
        '%homedir%/mail/archive/%domain%/.%direction%.%YYYYMMDDGMT%/new/%time%.',
        '%homedir%/mail/archive/%domain%/.%direction%.%YYYYMMDDGMT%/cur/%time%.',
        '%homedir%/mail/archive/%domain%/.%direction%.%YYYYMMDDGMT_plusone%/new/%time%.',
        '%homedir%/mail/archive/%domain%/.%direction%.%YYYYMMDDGMT_plusone%/cur/%time%.',
        '%homedir%/mail/archive/%domain%/.%direction%.%YYYYMMDDGMT_minusone%/new/%time%.',
        '%homedir%/mail/archive/%domain%/.%direction%.%YYYYMMDDGMT_minusone%/cur/%time%.',
    ],
    'archiver_incoming_domain_method' => [ ['archiver_incoming_local_user_method'] ],
    'archiver_outgoing'               => [ ['archiver_incoming_local_user_method'] ],
);

sub retrieve_message_filehandle {    ## no critic qw(Subroutines::ProhibitExcessComplexity)
    my %OPTS = @_;

    $locale   ||= Cpanel::Locale->get_handle();
    $hostname ||= Cpanel::Sys::Hostname::gethostname();

    my $address   = $OPTS{'address'};
    my $transport = $OPTS{'transport'};
    my $msgid     = $OPTS{'msgid'};
    my $path      = $OPTS{'path'};
    my $direction = $OPTS{'direction'};
    my $archive   = $OPTS{'archive'} ? 1 : 0;

    foreach my $var ( keys %OPTS ) {
        if ( $var ne 'path' && $OPTS{$var} =~ m{/} ) {
            return { 'status' => 0, 'statusmsg' => $locale->maketext( "The parameter “[_1]” may not contain slashes.", $var ) };
        }
        if ( $OPTS{$var} =~ m/\0/ ) {
            return { 'status' => 0, 'statusmsg' => $locale->maketext( "The parameter “[_1]” may not contain null bytes.", $var ) };
        }

    }

    if ( length $address && length $path ) {
        if ( lc $path eq lc $address ) {
            $address = $path;    # We want the caseful name of the address if possible
        }
        elsif ( index( $path, '@' ) > -1 || Cpanel::Validate::Username::is_valid($path) ) {

            # In this case the email was forwarded to another address
            # because path is the deliveredto address
            #
            # See emailstats_search.js
            # "path": encodeURIComponent(rowData["deliveredto"])
            #
            $address = $path;
        }

        # so we can find the right subaddress folder
    }

    $path = '' if !$path || $path !~ m{^/};    # handle exim wierdness

    if ( !length $msgid ) {
        return { 'status' => 0, 'statusmsg' => $locale->maketext( "“[_1]” is a required parameter.", 'msgid' ) };
    }
    my $delivery_time = Cpanel::Exim::Utils::get_time_from_msg_id( $OPTS{'msgid'} );
    if ( !$delivery_time ) {
        return { 'status' => 0, 'statusmsg' => $locale->maketext( "“[_1]” must be a valid Message-ID.", 'msgid' ) };
    }
    elsif ( !length $address ) {
        return { 'status' => 0, 'statusmsg' => $locale->maketext( "“[_1]” is a required parameter.", 'address' ) };
    }
    my ( $localpart, $domain ) = split( m{@}, $address );

    my $subaddress;
    $localpart =~ s{^"}{};
    $localpart =~ s{"$}{};
    ( $localpart, $subaddress ) = split( m{\+}, $localpart, 2 );

    if ( $transport =~ m/^(?:dovecot|local)/ ) {
        $domain ||= $hostname;
    }

    if ( !length $domain ) {
        return { 'status' => 0, 'statusmsg' => $locale->maketext( "“[_1]” must be a complete email address for non-local deliveries.", 'address' ) };
    }
    elsif ( !length $direction && !length $transport ) {
        return { 'status' => 0, 'statusmsg' => $locale->maketext( "Either “[_1]” or “[_2]” is required.", 'transport', 'direction' ) };
    }
    if ( length $direction && $direction !~ m/^(?:incoming|outgoing)$/ ) {
        return { 'status' => 0, 'statusmsg' => $locale->maketext( "“[_1]” must be either “[_2]” or “[_3]”.", 'direction', 'incoming', 'outgoing' ) };
    }
    if ( length $transport ) {
        if ( $transport eq 'address_directory' && !length $OPTS{'path'} ) {
            return { 'status' => 0, 'statusmsg' => $locale->maketext( "The “[_1]” transport requires the “[_2]” parameter.", 'transport', 'path' ) };
        }
    }
    else {
        if ( $archive && $direction eq 'outgoing' ) {
            $transport = 'archiver_outgoing';
        }
        if ( $domain eq $hostname ) {
            if ( $archive && $direction eq 'incoming' ) {
                $transport = 'archiver_incoming_local_user_method';
            }
            elsif ( $transport !~ m{^dovecot} ) {
                $transport = 'local_delivery';
            }
        }
        else {
            if ( $archive && $direction eq 'incoming' ) {
                $transport = 'archiver_incoming_domain_method';
            }
            elsif ( $transport !~ m{^dovecot} ) {
                $transport = 'virtual_userdelivery';
            }
        }
    }
    if ( !length $direction && $transport =~ m/^archiver_([^_]+)/ ) {
        $direction = $1;
    }

    my $user;
    if ( $domain eq $hostname ) {
        $user = $localpart;
        if ( $transport !~ m{^dovecot} ) {
            $domain = Cpanel::AcctUtils::Domain::getdomain($user);
        }
    }
    else {
        $user = Cpanel::AcctUtils::DomainOwner::Tiny::getdomainowner( $domain, { 'default' => '' } );
    }

    if ( !length $user ) {
        return { 'status' => 0, 'statusmsg' => $locale->maketext( "The address “[_1]” is not local to this server.", $address ) };
    }

    $direction ||= 'incoming';    # Mail that is leaving the server is not ever
                                  # saved on the server unless they have outgoing
                                  # archiving enabled.  If you fail to provide this
                                  # function a direction, we will assume it is incoming
                                  # since that is the most likely what you wanted

    my $potential_locations = $MESSAGE_LOCATIONS{$transport};

    if ( !$potential_locations ) {
        return { 'status' => 0, 'statusmsg', $locale->maketext( "This system does not know how to track messages with the transport “[_1]”.", $transport ) };
    }

    my @search_path;
    foreach my $location ( @{$potential_locations} ) {
        if ( ref $location ) {
            push @search_path, map { @{ $MESSAGE_LOCATIONS{$_} } } @{$location};
        }
        else {
            push @search_path, $location;
        }
    }

    my $homedir = Cpanel::PwCache::gethomedir($user);

    if ( !length $homedir ) {
        return { 'status' => 0, 'statusmsg' => $locale->maketext( "The address “[_1]” is not local to this server.", $address ) };
    }
    if ( length $path ) {
        $path =~ s/\/+/\//g;
        if ( $path !~ /^\Q$homedir\E\/(?:etc|mail)\// ) {
            return { 'status' => 0, 'statusmsg' => $locale->maketext( "The path “[_1]” is not inside the user’s home directory ([_2]).", $path, $homedir ) };
        }
    }

    my ($mailbox) = ( $path || '' ) =~ m{/\.([^\/]+)};
    if ($subaddress) {
        $mailbox = $subaddress;
    }
    my %template_vars = (
        'user'                 => $user,
        'homedir'              => $homedir,
        'time'                 => $delivery_time,
        'YYYYMMDDGMT'          => Cpanel::Email::Archive::YYYYMMDDGMT($delivery_time),
        'YYYYMMDDGMT_plusone'  => Cpanel::Email::Archive::YYYYMMDDGMT( $delivery_time + 86400 ),
        'YYYYMMDDGMT_minusone' => Cpanel::Email::Archive::YYYYMMDDGMT( $delivery_time - 86400 ),
        'localpart'            => $localpart,
        'domain'               => $domain,
        'path'                 => ( $path || '' ),
        'direction'            => $direction,
        'mailbox'              => $mailbox ? "INBOX.$mailbox" : 'INBOX',
    );
    $template_vars{'time'} = substr( $template_vars{'time'}, 0, -3 ) . '[0-9]{3}';

    # Kmail seems to have a date appended to the message-id
    #   id 1SsGDL-002XD2-AQ; Fri, 20 Jul 2012 11:38:03 -0500
    my $msgid_match_regex = qr/^\s*id\s*\Q$msgid\E[;\s\n\r]/m;

    #
    # allow up to 999 +/- seconds for delivery
    my $searcher = sub {
        foreach my $spath (@search_path) {
            next if $spath =~ m{^dovecot:};
            $spath =~ s/%([^%]+)%/if (!$template_vars{$1}) { next; } { $template_vars{$1} }/eg;

            my @split_path   = split( /\/+/, $spath );
            my $search_regex = pop(@split_path);
            my $search_path  = join( '/', @split_path );
            $search_regex =~ s/\./\\\./g;    #escape dots only.  We allow regexes here since the data
                                             #is trusted as this module provides it, however a trailing dot is special
            my $compiled_search_regex;
            eval { $compiled_search_regex = qr/^$search_regex/ };

            if ($@) {
                warn "Failed to compile regex: $search_regex\n";
                next;
            }

            if ( opendir( my $dir_fh, $search_path ) ) {
                foreach my $file ( grep ( m/$compiled_search_regex/, readdir($dir_fh) ) ) {
                    my $fh;
                    if ( open( $fh, '<', "$search_path/$file" ) ) {
                        my $buffer;
                        read( $fh, $buffer, 32768 );
                        if ( $buffer =~ $msgid_match_regex ) {
                            closedir($dir_fh);
                            seek( $fh, 0, 0 );
                            return { 'status' => 1, 'statusmsg' => $locale->maketext("Found Message"), 'path' => "$search_path/$file", 'user' => $user, 'fh' => $fh };
                        }
                        close($fh);
                    }

                }
                closedir($dir_fh);
            }
        }
    };

    my $result;
    if ( $> == 0 ) {
        $result = Cpanel::AccessIds::ReducedPrivileges::call_as_user(
            $searcher,
            $user,
            $user
        );
    }
    else {
        $result = $searcher->();
    }

    return $result if $result;

    my $start_date = substr( $delivery_time, 0, -4 ) . '0000';
    my $end_date   = substr( $delivery_time, 0, -4 ) . '9999';

    foreach my $spath (@search_path) {
        next if $spath !~ m{^dovecot:};
        my ( $dovecot, $email, $mailbox ) = split( m{:}, $spath, 3 );
        $email   =~ s/%([^%]+)%/if (!$template_vars{$1}) { next; } { $template_vars{$1} }/eg;
        $mailbox =~ s/%([^%]+)%/if (!$template_vars{$1}) { next; } { $template_vars{$1} }/eg;
        $email   =~ s{\@\Q$hostname\E$}{};
        my @cmd = (
            Cpanel::Dovecot::Utils::doveadm_bin(), 'fetch',
            '-u',          $email, 'text',
            'mailbox',     $mailbox,
            'SAVEDSINCE',  $start_date,
            'SAVEDBEFORE', $end_date,
            'HEADER',      'Received', 'id ' . $msgid
        );

        my ( $write, $fh );
        my $pid;
        if ( $pid = Cpanel::FastSpawn::InOut::inout( $write, $fh, @cmd ) ) {
            close($write);
            my $buffer = '';
            read( $fh, $buffer, 6 );
            if ( $buffer =~ m{^text:} ) {
                return { 'status' => 1, 'statusmsg' => $locale->maketext("Found Message"), 'path' => $spath, 'user' => $user, 'fh' => $fh };
            }
        }
        elsif ( defined $pid ) {
            exec(@cmd) or die "Failed to execute: @cmd: $!";
        }
        else {
            return { 'status' => 0, 'statusmsg' => $locale->maketext( "The system failed to create a child process because of the following error: [_1]", $! ) };
        }
    }

    return { 'status' => 0, 'statusmsg' => $locale->maketext("Could not locate message.") };
}

1;
