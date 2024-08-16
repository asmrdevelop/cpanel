package Cpanel::TailWatch::Eximstats;

# cpanel - Cpanel/TailWatch/Eximstats.pm           Copyright 2022 cPanel, L.L.C.
#                                                           All rights reserved.
# copyright@cpanel.net                                         http://cpanel.net
# This code is subject to the cPanel license. Unauthorized copying is prohibited

##############################################################
## no other use()s, require() only *and* only then in init() #
##############################################################

use base 'Cpanel::TailWatch::Base';

# /usr/local/cpanel already in @INC
# should work with these on but disabled in production for slight memory gain
use strict;
use warnings;

use Cpanel::SQLite::Compat ();
use Cpanel::ServerTasks    ();

our $DEBUG                          = 0;
our $VERSION                        = 3.0;
our $LOG_DUPLICATES                 = 1;
our $CACHE_PURGE_TIME               = 720;
our $READ_BUFFER_SIZE               = 65535;
our $KEEP_RECENT_RECIPIENT_IPS_TIME = ( 86400 * 3 );    # 72 hours

our $RECENT_RECIPIENT_MAIL_SERVER_IPS_FILE_PERMS = 0640;

our $_UPGRADE_IN_PROGRESS_FILE = '/usr/local/cpanel/upgrade_in_progress.txt';

our $MAX_LOCKED_DB_RETRIES = 10;

#CONSTANTS
our ( $MAX_EMAIL_PER_HOUR, $MAX_DEFER_FAIL_PERCENTAGE, $MIN_DEFER_FAIL_TO_TRIGGER_PROTECTION, $CURRENT_EMAILS_PER_HOUR, $CURRENT_DEFER_FAIL, $REACHED_MAX_EMAIL_PER_HOUR, $REACHED_MAX_DEFER_FAIL_PER_HOUR ) = ( 0, 1, 2, 3, 4, 5, 6 );

##############################################################
## no other use()s, require() only *and* only then in init() #
##############################################################

sub init {

    # this is where modules should be require()'d
    # this method gets called if PKG->is_enabled()

    require Time::Local;
    require File::Copy;
    require Cpanel::IO;                         # Needed for read_bytes_to_end_of_line
    require Cpanel::Exception;
    require Cpanel::EximStats::Retention;
    require Cpanel::Email::DeferThreshold;      # needed for defer_threshold
    require Cpanel::EmailTracker::Purge;
    require Cpanel::Exim::Utils::Generate;
    require Cpanel::ConfigFiles;
    require Cpanel::DeliveryReporter::Basic;    # PPI USE OK -- add function to Cpanel::DeliveryReporter namespace
    require Cpanel::LoadModule;
    require Cpanel::TailWatch;

    return;
}

sub internal_name { return 'eximstats' }

sub disable {

    # The order of arguments is different than others in this module, see Cpanel::TailWatch::Base::disable
    my ( $tailwatch_obj, $my_ns ) = @_;

    # Limits must be reset when Eximstats is disabled or limited domains will be blocked indefinitely.
    $tailwatch_obj->log('Email limits reset by Eximstats disable') if $my_ns->_force_email_limits_hourly_reset();

    goto &Cpanel::TailWatch::Base::disable;    # PPI NO PARSE -- already loaded by 'use base'
}

sub new {
    my ( $my_ns, $tailwatch_obj, %OPTS ) = @_;
    my $self = bless { 'tailwatch_obj' => $tailwatch_obj, '_cached_get_epoch_from_iso8601_or_now' => [ 0, 0 ], 'internal_store' => { 'last_check_time' => 0, 'check_interval' => 300 } }, $my_ns;

    # was in init as "$my_ns->{'_mailgid'}", but didn't make sense there since $my_ns is just a string looking for a ref to be blessed as;
    $self->{'_mailgid'} = ( getgrnam('mail') )[2];

    if ( keys %OPTS ) {
        if ( $OPTS{'buffered_sql'} ) {
            $self->{'buffered_sql'} = 1;
            $self->{'sql_buffer'}   = [];
        }
        if ( $OPTS{'import'} ) {
            $self->{'import'} = 1;
        }
    }

    $tailwatch_obj->register_module( $self, __PACKAGE__, &Cpanel::TailWatch::PREVPNT, [ '/var/log/exim/mainlog', '/var/log/exim_mainlog' ] );    ## no critic (ProhibitAmpersandSigils)

    $self->{'process_line_regex'}->{'/var/log/exim/mainlog'} = $self->{'process_line_regex'}->{'/var/log/exim_mainlog'} =                                                                                 #
      qr/(?: Completed$|cancelled|SpamAssassin as | rejected RCPT | Sender identification| SMTP connection|\S+ (?:=>|\->|\*\*|==|<=|error|check_mail_permissions|exceeded the max emails per hour) )/;    #

    local $@;
    eval {
        $self->_trim_recent_recipient_mail_server_ips_and_open_for_append();

        $tailwatch_obj->register_reload_module( $self, __PACKAGE__ );

        $tailwatch_obj->register_action_module( $self, __PACKAGE__ );

        mkdir '/var/cpanel/email_send_limits', 0751 if !-e '/var/cpanel/email_send_limits';

        $self->_validate_email_limits_data();
    };
    my $err = $@;

    # Make sure to not reuse a SQLite DBH after a fork()
    $self->reset_dbh();

    if ($err) {
        local $@ = $err;
        die;
    }

    return $self;
}

# SQLite will potentially corrupt databases if you use a DBH created before a fork.
# see: https://sqlite.org/faq.html#q6
sub reset_dbh {
    my ($self) = @_;

    $self->{'dbh'}     = undef;
    $self->{'dbh_pid'} = undef;

    return;
}

sub run {
    my ( $my_ns, $tailwatch_obj, $time ) = @_;

    # Status of true means we are inside a service check but we have passed control back to the main tailwatch
    # process so other drivers can be handled.  If we are here then we need to continue service checks.
    $my_ns->_check_for_time_to_trim_recipient_mail_server_ips($time);
    $my_ns->_check_email_limits_for_hourly_reset($time);

    return;
}

sub get_exim_retention_seconds {
    my ($my_ns) = @_;

    my $exim_retention_days = Cpanel::EximStats::Retention::get_valid_exim_retention_days( undef, $my_ns->{'tailwatch_obj'}{'global_share'}{'data_cache'}{'cpconf'} );

    if ($exim_retention_days) {
        my $day_seconds = 24 * 60 * 60;
        return int( $day_seconds * $exim_retention_days );
    }
    return 0;
}

sub reload {
    my ( $my_ns, $tailwatch_obj, $time ) = @_;

    $my_ns->{'retention_seconds'} = $my_ns->get_exim_retention_seconds();

    # Status of true means we are inside a service check but we have passed control back to the main tailwatch
    # process so other drivers can be handled.  If we are here then we need to continue service checks.
    $my_ns->_validate_email_limits_data($time);

    return;
}

sub process_line {    ## no critic (ProhibitExcessComplexity)
    my ( $self, $line, $tailwatch_obj, $logfile, $now ) = @_;

    $now ||= time();

    $tailwatch_obj->debug("process_line: $line") if $tailwatch_obj->{'debug'};

    my ( $date, $time, @ARGS ) = split( m/ /, $line );

    return if !@ARGS;

    chomp $ARGS[-1];
    my $unixtime = $self->_get_epoch_from_iso8601_or_now("$date $time");

    unless ( $self->{'parse_only'} || $self->{'sql_only'} ) {
        $self->{'retention_seconds'} = $self->get_exim_retention_seconds() if !defined $self->{'retention_seconds'};
        if ( $self->{'retention_seconds'} && $unixtime + $self->{'retention_seconds'} < $now ) {
            $tailwatch_obj->debug("$line is older than retention_seconds ($self->{'retention_seconds'})") if $tailwatch_obj->{'debug'};
            return;
        }
    }

    if ( index( $line, 'check_mail_permissions Hit daily email notify limit' ) > -1 ) {
        if ( join( ' ', @ARGS ) =~ m/\A[\w]{6}-[\w]{6}-[\w]{2} check_mail_permissions Hit daily email notify limit for domain ([a-zA-Z0-9\-\.]+)\Z/ ) {
            my $this_domain = $1;
            if ( not -e '/var/cpanel/email_send_limits/daily_notify/' . $this_domain . '_send' ) {
                if ( open( my $send_fh, '>', '/var/cpanel/email_send_limits/daily_notify/' . $this_domain . '_send' ) ) {
                    close $send_fh;
                }
                $self->_send_limit_exceeded_notification( $this_domain, 'daily' );
            }
        }
    }
    elsif ( index( $line, 'exceeded the max emails per hour' ) > -1 ) {
        my ($this_domain) = ( $line =~ m/Domain (\S*) / );
        $self->_send_limit_exceeded_notification( $this_domain, 'hourly' );
    }

    shift @ARGS if index( $ARGS[0], '-' ) == 0 || index( $ARGS[0], '+' ) == 0;    #case 54301: skip timezone m/^[+-][0-9]{4}$/
    shift @ARGS if $ARGS[0] =~ tr/]//;                                            #skip pid

    # Exim uses the following regex for finding message ids
    #      regex_must_compile(US"^(?:[^\\W_]{6}-){2}[^\\W_]{2}$", FALSE, TRUE);
    # Only shift out the msgid if it is a msgid
    my ( $deliveredto, $address, $msgid );

    if (   length $ARGS[0] == 23
        && substr( $ARGS[0], 6,  1 ) eq '-'
        && substr( $ARGS[0], 18, 1 ) eq '-'
        && ( substr( $ARGS[0], 0,  6 )  =~ tr{a-zA-Z0-9_}{} ) == 6
        && ( substr( $ARGS[0], 7,  11 ) =~ tr{a-zA-Z0-9_}{} ) == 11
        && ( substr( $ARGS[0], 14, 4 )  =~ tr{a-zA-Z0-9_}{} ) == 4 ) {
        $msgid = shift @ARGS;
    }

    #  $msgid = shift @ARGS if ( ( $ARGS[0] =~ tr/-// ) == 2 && $ARGS[0] =~ m/^(?:[^\W_]{6}-){2}[^\W_]{2}$/ );
    if ( $ARGS[0] eq 'Sender' && $ARGS[1] eq 'identification' ) {

        # Will log as 2017-05-26 13:42:22 1dEKBq-0007HB-6R Sender identification S=nick
        splice( @ARGS, 0, 2 );
        my %SENDER_OPTS     = map { ( split( m/=/, $_, 2 ) )[ 0, 1 ] } @ARGS;
        my $update_response = $self->_process_eximstats_update(
            'sends',
            q{UPDATE sends SET user=?,domain=?,sender=? where msgid=?;},
            [ $SENDER_OPTS{'U'}, $SENDER_OPTS{'D'}, $SENDER_OPTS{'S'}, $msgid ]
        );
        if ( $self->{'parse_only'} ) {
            return {
                'action'      => 'sender_identification',
                'sender_opts' => \%SENDER_OPTS,
            };
        }
        if ( $self->{'sql_only'} ) { return $update_response; }
    }
    elsif ( $ARGS[0] eq 'SMTP' && $ARGS[1] eq 'connection' ) {
        if ( $ARGS[2] eq 'identification' ) {
            splice( @ARGS, 0, 3 );
            my %CONNECTION_OPTS = map { ( split( m/=/, $_, 2 ) )[ 0, 1 ] } @ARGS;

            if ( $CONNECTION_OPTS{'M'} ) {
                my $msgid = $CONNECTION_OPTS{'M'};
                my $user  = $CONNECTION_OPTS{'U'};
                if ( $CONNECTION_OPTS{'B'} eq 'redirect_resolver' ) {
                    my $domain      = $CONNECTION_OPTS{'D'};
                    my $alias_entry = $CONNECTION_OPTS{'O'};

                    my $update_response = $self->_process_eximstats_update(
                        'sends',
                        q{UPDATE sends SET user=?,domain=?,auth=?,sender=? where msgid=?;},
                        [ $user, $domain, 'forwarder', $user, $msgid ]
                    );

                    if ( $self->{'parse_only'} ) {
                        return {
                            'action'          => 'redirect_resolver',
                            'connection_opts' => \%CONNECTION_OPTS,
                        };
                    }
                    if ( $self->{'sql_only'} ) { return $update_response; }
                }
                else {
                    $self->{'internal_store'}{'SENDER_MSGID_USER_MAP'}->{$msgid} = [ $user, $CONNECTION_OPTS{'B'}, $now ];
                    $tailwatch_obj->debug("Set msgid $msgid in SENDER_MSGID_USER_MAP to $user") if $tailwatch_obj->{'debug'};
                }
            }
            elsif ( $CONNECTION_OPTS{'B'} eq 'identify_local_connection' ) {
                my $port = $CONNECTION_OPTS{'P'};
                my $user = $CONNECTION_OPTS{'U'};
                $self->{'internal_store'}{'SENDER_ADDRESS_PORT_USER_MAP'}->{ 'localhost_' . $port } = [ $user, $CONNECTION_OPTS{'B'}, $now ];
                $tailwatch_obj->debug("Set address:port localhost_$port in SENDER_ADDRESS_PORT_USER_MAP to $user") if $tailwatch_obj->{'debug'};
            }
            else {
                my $port    = $CONNECTION_OPTS{'P'};
                my $address = $CONNECTION_OPTS{'A'};
                my $user    = $CONNECTION_OPTS{'U'};
                $self->{'internal_store'}{'SENDER_ADDRESS_PORT_USER_MAP'}->{ $address . '_' . $port } = [ $user, $CONNECTION_OPTS{'B'}, $now ];
                $tailwatch_obj->debug("Set address:port ${address}_$port in SENDER_ADDRESS_PORT_USER_MAP to $user") if $tailwatch_obj->{'debug'};
            }

            if ( $self->{'parse_only'} ) {
                return {
                    'action'          => 'identify',
                    'connection_opts' => \%CONNECTION_OPTS,
                };
            }
        }
        elsif ( $ARGS[2] eq 'outbound' ) {
            my ( $countedtime, $countedmsgid, $counteddomain, $countedemail ) = splice( @ARGS, 3, 4 );
            my $countedhour = ( $countedtime - ( $countedtime % 3600 ) );
            if ( $self->{'parse_only'} ) {
                return {
                    'action'        => 'outbound',
                    'countedtime'   => $countedtime,
                    'countedhour'   => $countedhour,
                    'counteddomain' => $counteddomain,
                    'countedemail'  => $countedemail,
                    'countedmsgid'  => $countedmsgid,
                };
            }

            # Now, Domain, Time, Hour, Email
            $self->{'internal_store'}{'counted_domain_cache'}{$countedmsgid} = [ $now, $counteddomain, $countedtime, $countedhour, $countedemail ];
        }
        elsif ( $ARGS[2] eq 'from' && grep { $_ eq 'closed' || $_ eq 'lost' } @ARGS ) {
            my ( $ip, $port ) = $self->parse_ipdata_from_args( \@ARGS );
            my $key = ( $tailwatch_obj->_is_loopback($ip) ? 'localhost' : $ip ) . '_' . $port;
            delete $self->{'internal_store'}{'SENDER_ADDRESS_PORT_USER_MAP'}->{$key};
            if ( $self->{'parse_only'} ) {
                return {
                    'action' => 'close',
                    'ip'     => $ip,
                    'port'   => $port,
                    'key'    => $key
                };
            }
        }
        elsif ( $ARGS[2] eq 'lost' && $ARGS[3] eq 'after' && $ARGS[4] eq 'final' && $ARGS[5] eq 'dot' ) {
            my ( $ip, $port ) = $self->parse_ipdata_from_args( \@ARGS );
            my $key = ( $tailwatch_obj->_is_loopback($ip) ? 'localhost' : $ip ) . '_' . $port;
            delete $self->{'internal_store'}{'SENDER_ADDRESS_PORT_USER_MAP'}->{$key};
            if ($msgid) {
                foreach my $key ( 'SENDER_MSGID_USER_MAP', 'SPAMSCORE_MSGID_MAP', 'sender_address_cache', 'sender_domain_cache', 'counted_domain_cache' ) {
                    delete $self->{'internal_store'}{$key}->{$msgid};
                }
            }

            if ( $self->{'parse_only'} ) {
                return {
                    'action' => 'lost',
                    'ip'     => $ip,
                    'port'   => $port,
                    'msgid'  => $msgid,
                    'key'    => $key
                };
            }

        }
        return;
    }

    # LENGTH ' Completed' == 10, LENGTH '\n' == 1, 11
    elsif ( $msgid && rindex( $line, ' Completed' ) == ( length($line) - 11 ) ) {
        foreach my $key ( 'SENDER_MSGID_USER_MAP', 'SPAMSCORE_MSGID_MAP', 'sender_address_cache', 'sender_domain_cache', 'counted_domain_cache' ) {
            delete $self->{'internal_store'}{$key}->{$msgid};
        }
        if ( $self->{'parse_only'} ) {
            return {
                'action' => 'completed',
                'msgid'  => $msgid,
            };
        }

        return;
    }
    elsif ($ARGS[0] ne '=>'
        && $ARGS[0] ne '->'
        && $ARGS[0] ne '**'
        && $ARGS[0] ne '=='
        && $ARGS[0] ne '<='
        && $ARGS[0] ne 'error'
        && $ARGS[0] ne 'cancelled' ) {
        if ( index( $line, ' rejected RCPT ' ) > -1 ) {
            my $sender_domain = '';
            my $user          = '-remote-';
            my $size          = 0;
            my $auth          = 'unauthorized';
            my $localsender   = 0;
            my $processed     = 0;
            my $router        = 'reject';
            my $transport     = '**rejected**';
            my $deliveryuser  = '';

            my %CFG = map { ( split( m/=/, $_, 2 ) )[ 0, 1 ] } @ARGS;
            my ( $recipient, $msg ) = ( $line =~ m/ rejected RCPT ([^:]+):\s*(.*)/ );
            if ( length $msg && $msg =~ tr{"}{} ) {
                substr( $msg, 0, 1, '' ) if substr( $msg, 0, 1 ) eq '"';
                chop($msg) if substr( $msg, -1 ) eq '"';
            }
            my $address = $CFG{'F'};
            if ( $address =~ tr{<>}{} ) {
                substr( $address, 0, 1, '' ) if substr( $address, 0, 1 ) eq '<';
                chop($address) if substr( $address, -1 ) eq '>';
            }
            $address ||= '';
            if ( length $recipient && $recipient =~ tr{<>}{} ) {
                substr( $recipient, 0, 1, '' ) if substr( $recipient, 0, 1 ) eq '<';
                chop($recipient) if substr( $recipient, -1 ) eq '>';
            }
            $recipient ||= '';
            my $deliverydomain = ( split( /\@/, $recipient ) )[1];
            $deliverydomain ||= '';

            if (   $deliverydomain
                && exists $tailwatch_obj->{'global_share'}{'data_cache'}{'domain_user_map'}{$deliverydomain}
                && $tailwatch_obj->{'global_share'}{'data_cache'}{'domain_user_map'}{$deliverydomain} ) {
                $deliveryuser = $tailwatch_obj->{'global_share'}{'data_cache'}{'domain_user_map'}{$deliverydomain};
            }
            $deliveryuser ||= '';
            my $host = $CFG{'H'};
            if ( $host && $host =~ tr/\[// ) {
                ($host) = $self->parse_bracketed_host($host);
            }
            my ( $ip, $port ) = $self->parse_ipdata_from_args( \@ARGS );

            if ( !$msgid ) {
                my $ipdec;
                if ( $ip =~ tr/:// ) {

                    # use just the end of ipv6 address, good enough to get a unique key thats the same every time
                    $ipdec = $ip;
                    $ipdec =~ tr/://d;
                    ($ipdec) = $ipdec =~ /([a-f0-9]{0,6}$)/;
                    $ipdec = hex $ipdec;
                }
                else {
                    $ipdec = unpack( 'N', pack( 'C4C4C4C4', split( /\./, $ip ) ) );
                }
                $msgid = Cpanel::Exim::Utils::Generate::get_msg_id( $unixtime, ( $ipdec || 0 ), ( $port || $$ ) );
            }
            $host = '' unless defined $host;
            if ( $host =~ tr{()}{} ) {
                substr( $host, 0, 1, '' ) if substr( $host, 0, 1 ) eq '(';
                chop($host) if substr( $host, -1 ) eq ')';
            }

            $host        ||= $ip;         #case 54426: always set the host var as its what we display
            $host        ||= 'unknown';
            $ip          ||= 'unknown';
            $deliveredto ||= $address;

            if ( $self->{'parse_only'} ) {
                return {
                    'address'        => $address,
                    'deliveredto'    => $deliveredto,
                    'date'           => $date,
                    'time'           => $time,
                    'cfg'            => \%CFG,
                    'host'           => $host,
                    'ip'             => $ip,
                    'deliverydomain' => $deliverydomain,
                    'deliveryuser'   => $deliveryuser,
                    'recipient'      => $recipient,
                    'msg'            => $msg,
                    'msgid'          => $msgid,
                };
            }

            # case FB-88897: dupes are expected here and we just want to ignore them
            local $LOG_DUPLICATES = 0;
            my $first_insert_response = $self->_process_eximstats_insert(
                'sends',
                qq{INSERT INTO sends},
                [qw(sendunixtime msgid processed domain email user size host ip auth localsender)],
                [ $unixtime, $msgid, $processed, $sender_domain, $address, $user, $size, $host, $ip, $auth, $localsender ]
            );
            my $second_insert_response = $self->_process_eximstats_insert(
                'failures',
                qq{INSERT INTO failures},
                [qw(sendunixtime msgid email deliveredto transport_method message host ip router deliveryuser deliverydomain)],
                [ $unixtime, $msgid, $recipient, $deliveredto, $transport, $msg, $host, $ip, $router, $deliveryuser, $deliverydomain ]
            );
            if ( $self->{'sql_only'} ) { return [ $first_insert_response, $second_insert_response ]; }
            return $first_insert_response && $second_insert_response;
        }
        elsif ( $msgid && $line =~ m/Warning:\s+"SpamAssassin\s+as\s+/ ) {
            $self->{'internal_store'}{'SPAMSCORE_MSGID_MAP'}->{$msgid}->[2] = $now;
            ( $self->{'internal_store'}{'SPAMSCORE_MSGID_MAP'}->{$msgid}->[0] ) = $line =~ m/spam\s+\(([\-0-9\.]+)\)"/;
            if ( $self->{'parse_only'} ) {
                return $self->{'internal_store'}{'SPAMSCORE_MSGID_MAP'}->{$msgid}->[0];
            }
            return;
        }
    }
    my $direction = shift @ARGS;
    my %CFG;

    if ( $direction eq 'failed' || $direction eq 'cancelled' ) {
        $address     = '';
        $deliveredto = '';
    }
    else {

        # This magic handles delivery points quotes and spaces in them
        #2011-10-11 20:35:43 1RDnjR-0005ho-Uu <= "tuition portal <teo.jsm"@gmail.com H=(mercury150.networknoc.com) [114.129.45.58] P=esmtps X=TLSv1:AES256-SHA:256 S=7617
        #2011-10-11 14:11:46 1RDhjt-0004ss-8n <= "admin <ng.wmsps"@gmail.com H=(mercury150.networknoc.com) [114.129.45.58] P=esmtps X=TLSv1:AES256-SHA:256 S=6806
        my @DELIVERY_POINT = shift @ARGS || '';

        if ( @ARGS && ( $DELIVERY_POINT[0] =~ tr/"// ) == 1 ) {
            while ( @ARGS && $ARGS[0] !~ tr/"// ) {
                push @DELIVERY_POINT, shift @ARGS;    # insided quotes
            }
            push @DELIVERY_POINT, shift @ARGS;        # end quoted item
        }

# This magic handles delivery points with spaces in them
#2011-09-30 21:07:22 1R9oz3-0005fH-O5 => /home/cplove/mail/c.net/sam/.Server Status/ <mydlcpanel.net> R=virtual_user_filter T=address_directory
#2017-01-24 16:14:03 1cW9Lm-0004Tz-TD => philip.stark+01 - test vm notifications ("philip.stark+01 - Test VM Notifications"@cpanel.net, "philip.stark+01 - Test VM Notifications"@cpanel.net, philip.stark@cpanel.net, philip.stark@cpanel.net) <philip.stark@cpanel.net> SRS=<SRS0=zTt2S=ZG=63.pota.to=cpanel@cpanel.net> R=virtual_user T=dovecot_virtual_delivery C="250 2.0.0 <philip.stark+01 - Test VM Notifications@cpanel.net> 4T9TCqvRh1h3OAAA6kPjFA Saved"
        while (
            @ARGS
            && index( $ARGS[0], '(' ) != 0    # not the start of an expansion
            && $ARGS[0] !~ tr/=<//            # does not have a < or = in it
            && ( -1 != index( $ARGS[0], '/' ) || !grep { -1 != index( $_, '@' ) } @DELIVERY_POINT )
        ) {
            push @DELIVERY_POINT, shift @ARGS;
        }

        # Handle logging of expansions
        # 2011-10-26 08:20:54 [4478] 1RJ3Pa-0001AA-HC => nick (nick@cpanel.net, nick@pigdog.org, nick@pigdog.org) <nick@pigdog.org> F=<mycow@pigdog.org> P=<mycow@pigdog.org> R=boxtrapper_autowhitelist T=boxtrapper_autowhitelist S=860 QT=0s DT=0s
        if ( @ARGS && index( $ARGS[0], '(' ) == 0 ) {
            my @address_expansions = shift @ARGS;

            # If the address has spaces we need to consume the rest of it
            #ex "philip.stark+01 - Test VM Notifications"@cpanel.net,
            while ( @ARGS && $address_expansions[-1] !~ tr{),}{} ) {
                $address_expansions[-1] .= ' ' . shift @ARGS;
            }

            # remove leading (
            substr( $address_expansions[-1], 0, 1, '' );

            # Not a single expansion like (nick@cpanel.net)
            if ( substr( $address_expansions[-1], -1 ) ne ')' ) {

                # remove trailing ,
                chop( $address_expansions[-1] );

                while ( @ARGS && substr( $ARGS[0], -1 ) ne ')' ) {

                    # keep going until we get a ) ie removes nick@pigdog.org,
                    push @address_expansions, shift @ARGS;

                    # If the address has spaces we need to consume the rest of it
                    #ex "philip.stark+01 - Test VM Notifications"@cpanel.net,
                    while ( @ARGS && $address_expansions[-1] !~ tr{),}{} ) {
                        $address_expansions[-1] .= ' ' . shift @ARGS;
                    }

                    chop( $address_expansions[-1] );    # remove trailing , or )
                }
                if (@ARGS) {

                    # removes nick@pigdog.org)
                    push @address_expansions, shift @ARGS;

                    # If the address has spaces we need to consume the rest of it
                    #ex "philip.stark+01 - Test VM Notifications"@cpanel.net)
                    while ( @ARGS && $address_expansions[-1] !~ tr{),}{} ) {
                        $address_expansions[-1] .= ' ' . shift @ARGS;
                    }

                    # remove trailing , or )
                    chop( $address_expansions[-1] );
                }
            }
            else {

                # remove trailing )
                chop( $address_expansions[-1] );
            }

            # Handle forwarder expansion when not going to /dev/null
            # IE This still goes to /dev/null
            # 2011-11-06 14:59:17 1RN9oB-0001v4-K1 => /dev/null (erice@cpanel.net) <techmgr@cpanel.net> R=virtual_user_filter T=**bypassed**
            if ( $DELIVERY_POINT[0] !~ tr{/@}{} ) {
                my $lowercase_delivery_point = $DELIVERY_POINT[0];
                $lowercase_delivery_point =~ tr/A-Z/a-z/;
                foreach my $possible_address (@address_expansions) {
                    my ( $lowercase_possible_local_part, $lowercase_possible_domain ) = split( m{@}, $possible_address );

                    $lowercase_possible_local_part =~ tr/A-Z/a-z/;
                    $lowercase_possible_domain     =~ tr/A-Z/a-z/ if length $lowercase_possible_domain;

                    if ( $lowercase_possible_local_part =~ tr{"}{} ) {
                        substr( $lowercase_possible_local_part, 0, 1, '' );
                        chop($lowercase_possible_local_part);
                    }
                    if ( $DELIVERY_POINT[0] =~ tr{@}{} ) {
                        if ( length $lowercase_possible_domain && $lowercase_possible_local_part . '@' . $lowercase_possible_domain eq $lowercase_delivery_point ) {
                            @DELIVERY_POINT = ($possible_address);
                            last;
                        }
                    }
                    elsif ( $lowercase_possible_local_part eq $lowercase_delivery_point ) {
                        @DELIVERY_POINT = ($possible_address);
                        last;
                    }
                }
            }
        }

        $deliveredto = scalar @DELIVERY_POINT == 1 ? $DELIVERY_POINT[0] : join( ' ', @DELIVERY_POINT );

        chop($deliveredto) if defined $deliveredto && substr( $deliveredto, -1 ) eq ':' && substr( $deliveredto, 0, 1 ) ne ':';

        if ( @ARGS && index( $ARGS[0], '<' ) == 0 ) {
            my @address_parts;
            while (@ARGS) {
                push @address_parts, shift @ARGS;
                last if index( $address_parts[-1], '>' ) > -1;
            }
            $address = join( ' ', @address_parts );
            substr( $address, 0, 1, '' ) if substr( $address, 0, 1 ) eq '<';
            chop($address) if substr( $address, -1 ) eq '>';
        }

        $address ||= $deliveredto;
        $address = lc $address;

        if ( $deliveredto !~ tr/\/ // && $deliveredto !~ tr/\@// && $address =~ tr/\@// && $deliveredto !~ /^\s*:/ ) {
            $deliveredto .= '@' . ( split( m/\@/, $address ) )[1];    #ie make nick nick@cpanel.net
        }

        # To debug parser :  (not included as a debug because of the volume)
        #$tailwatch_obj->log("$msgid = [deliveredto]=$deliveredto address=[$address] ARGS=[@ARGS]");
        %CFG = map { ( split( m/=/, $_, 2 ) )[ 0, 1 ] } @ARGS;
    }

    if ( $self->{'parse_only'} && $direction ne '=>' && $direction ne '<=' ) {
        return {
            'address'     => $address,
            'deliveredto' => $deliveredto,
            'msgid'       => $msgid,
            'date'        => $date,
            'time'        => $time,
            'direction'   => $direction,
            'cfg'         => \%CFG,
        };
    }

    if ( $direction eq '**' || $direction eq '==' || $direction eq 'failed' || $direction eq 'cancelled' ) {
        delete $self->{'internal_store'}{'SENDER_MSGID_USER_MAP'}->{$msgid} if exists $self->{'internal_store'}{'SENDER_MSGID_USER_MAP'}->{$msgid};    # will already be used
        my $table     = ( ( $direction eq '**' || $direction eq 'failed' || $direction eq 'cancelled' ) ? 'failures' : 'defers' );
        my $transport = $CFG{'T'} || 'fail';
        my ( $port, $ip );
        my $msg;
        chop($transport) if defined $transport && substr( $transport, -1 ) eq ':';

        my $isremote = ( defined $transport && index( $transport, 'remote' ) > -1 ? 1 : 0 );
        my $host     = $CFG{'H'};
        my $router   = $CFG{'R'} || '';
        chop($router) if defined $router && substr( $router, -1 ) eq ':';
        if ( $host && $host =~ tr/\[// ) {
            ( $host, $port ) = $self->parse_bracketed_host($host);
        }
        if ( !$host ) {
            my $line = join( " ", @ARGS );
            ($host) = $line =~ /: host\s+(\S+)/;
        }
        $host = '' unless defined $host;
        if ( $host =~ tr{()}{} ) {
            $host =~ s/^\(//;
            $host =~ s/\)$//;
        }

        if ( !$ip && $line =~ tr{[}{} ) {
            ( $ip, $port ) = $self->parse_ipdata_from_args( \@ARGS );
        }

        $ip   ||= '';
        $host ||= $ip;    #case 54426: always set the host var as its what we display

        if ( !$msgid ) {
            $tailwatch_obj->error("Unable to parse [$line] for $table");
            return;
        }

        if ( $direction eq 'failed' || $direction eq 'cancelled' ) {

            # 2018-04-16 18:29:01 1f8DYT-0004dY-50 cancelled by system filter: local deliveries only
            $msg = join( ' ', $direction, @ARGS );
        }
        else {
            if ( !$address ) {
                $tailwatch_obj->error("Unable to parse [$line] for $table");
                return;
            }
            $msg = ( split( m/:\s*/, join( ' ', @ARGS ), 2 ) )[-1];
        }

        if ( $msg =~ tr{"}{} ) {
            substr( $msg, 0, 1, '' ) if substr( $msg, 0, 1 ) eq '"';
            chop($msg) if substr( $msg, -1 ) eq '"';

        }
        if ( !$self->_validate_email_limits_data($now) ) {
            $self->_check_email_limits_for_hourly_reset($now);
        }

        if ( my $sender_domain = $self->_get_sender_domain($msgid) ) {
            $self->{'internal_store'}{'email_limits'}{$sender_domain}->[$CURRENT_DEFER_FAIL]++;
            $self->_sync_limit_to_fs($sender_domain);
        }

        my ( $deliverydomain, $deliveryuser ) = $self->_get_domain_and_user_from_address_and_deliveredto( $tailwatch_obj, $address, $deliveredto );

        if ( $table eq 'defers' ) {
            return $self->_process_eximstats_insert(
                $table,
                qq{INSERT INTO $table},
                [qw(sendunixtime msgid email transport_method message host ip router deliveryuser deliverydomain)],
                [ $unixtime, $msgid, $address, $transport, $msg, $host, $ip, $router, $deliveryuser, $deliverydomain ]
            );
        }
        else {
            return $self->_process_eximstats_insert(
                $table,
                qq{INSERT INTO $table},
                [qw(sendunixtime msgid email deliveredto transport_method message host ip router deliveryuser deliverydomain)],
                [ $unixtime, $msgid, $address, $deliveredto, $transport, $msg, $host, $ip, $router, $deliveryuser, $deliverydomain ]
            );

        }
    }
    elsif ( $direction eq '<=' ) {
        if ( ++$self->{'internal_store'}{'lines_processed'} >= 512 ) {
            $self->{'internal_store'}{'lines_processed'} = 0;
            $self->_purge_info_cache();
        }
        my $spamscore = exists $self->{'internal_store'}{'SPAMSCORE_MSGID_MAP'}->{$msgid} ? $self->{'internal_store'}{'SPAMSCORE_MSGID_MAP'}->{$msgid}->[0] : undef;
        delete $self->{'internal_store'}{'SPAMSCORE_MSGID_MAP'}->{$msgid};
        my $user      = '';
        my $sender    = '';
        my $auth      = '';
        my $ip        = '';
        my $port      = '';
        my $processed = 0;           #always tracked
        my $proto     = $CFG{'P'};
        my $size      = $CFG{'S'};

        if ( defined $CFG{'A'} ) {
            if ( $CFG{'A'} =~ tr{:}{} ) {
                ( $auth, $user ) = split( m/:/, $CFG{'A'} );
                $sender = $user;
            }
            else {
                $auth = $CFG{'A'};
            }
        }
        if ( defined $proto && length($proto) >= 5 && substr( $proto, 0, 5 ) eq 'local' ) {
            $user   = $CFG{'U'};
            $sender = $user;
            $auth   = 'localuser';
            $ip     = '127.0.0.1';
        }
        my $host = $CFG{'H'};
        if ( $host && $host =~ tr/\[// ) {
            ( $host, $port ) = $self->parse_bracketed_host($host);
        }
        $host = '' unless defined $host;
        if ( $host =~ tr{()}{} ) {
            substr( $host, 0, 1, '' ) if substr( $host, 0, 1 ) eq '(';
            chop($host) if substr( $host, -1 ) eq ')';
        }
        if ( !$host && length $proto && $proto eq 'local' ) {
            $host = 'localhost';
        }

        if ( !$ip && $line =~ tr{[}{} ) {
            ( $ip, $port ) = $self->parse_ipdata_from_args( \@ARGS );
        }

        $host ||= $ip;    #case 54426: always set the host var as its what we display
        $port ||= '';

        # case 56622: Authentication should always overwrite local connection
        if ( !$auth || !$user ) {
            if ( exists $self->{'internal_store'}{'SENDER_MSGID_USER_MAP'}->{$msgid} ) {
                ( $user, $auth ) = @{ $self->{'internal_store'}{'SENDER_MSGID_USER_MAP'}->{$msgid} }[ 0, 1 ];
                delete $self->{'internal_store'}{'SENDER_MSGID_USER_MAP'}->{$msgid};    #per message so we can remove
            }
            elsif ( exists $self->{'internal_store'}{'SENDER_ADDRESS_PORT_USER_MAP'}->{ 'localhost_' . $port } && $tailwatch_obj->_is_loopback($ip) ) {
                ( $user, $auth ) = @{ $self->{'internal_store'}{'SENDER_ADDRESS_PORT_USER_MAP'}->{ 'localhost_' . $port } }[ 0, 1 ];
            }
            elsif ( exists $self->{'internal_store'}{'SENDER_ADDRESS_PORT_USER_MAP'}->{ $ip . '_' . $port } ) {
                ( $user, $auth ) = @{ $self->{'internal_store'}{'SENDER_ADDRESS_PORT_USER_MAP'}->{ $ip . '_' . $port } }[ 0, 1 ];
            }
        }
        elsif ( exists $self->{'internal_store'}{'SENDER_MSGID_USER_MAP'}->{$msgid} ) {
            delete $self->{'internal_store'}{'SENDER_MSGID_USER_MAP'}->{$msgid};    #per message so we can remove
        }

        $tailwatch_obj->debug("We have a send unixtime=($unixtime) auth=($auth) user=($user) address=($address) ip=($ip) port=($port)") if $tailwatch_obj->{'debug'};

        if ( !$user ) {
            $self->_check_relayips();
            if ( exists $self->{'internal_store'}{'relayips'}{$ip} ) {
                my @possible_users = @{ $self->{'internal_store'}{'relayips'}{$ip} };
                if ( grep { $address eq $_ } @possible_users ) {
                    $user = $address;
                }
                else {
                    my $address_domain   = ( split( m/[\%\@\+]+/, $address ) )[-1];
                    my @matching_domains = grep( /\@\Q$address_domain\E$/, @possible_users );
                    $user = $matching_domains[0] if @matching_domains;
                }
                $user ||= $possible_users[0];
                $auth = 'recent_authed_mail_ips';
                $tailwatch_obj->debug("Found user $user in /etc/recent_authed_mail_ips_users") if $tailwatch_obj->{'debug'};
            }
            else {
                $user = '-remote-';
                $auth = 'localdelivery';
            }
        }

        if ( !$user || $user eq 'mail' || $user eq 'mailnull' ) {
            $tailwatch_obj->debug("Unable to determine user: $line") if $tailwatch_obj->{'debug'};
            return;
        }

        my $localsender = 1;
        my $sender_domain;

        if ( $user eq 'mailman' ) {    #special case for mailman
            $auth = 'mailman';

            my $domain = ( split( m/[\%\@\+]+/, $address ) )[-1];
            if (   $domain
                && exists $tailwatch_obj->{'global_share'}{'data_cache'}{'domain_user_map'}{$domain}
                && $tailwatch_obj->{'global_share'}{'data_cache'}{'domain_user_map'}{$domain} ) {
                $sender_domain = $domain;
                $user          = $tailwatch_obj->{'global_share'}{'data_cache'}{'domain_user_map'}{$domain};
            }
        }
        elsif ( $user =~ tr/\@\%\+// ) {
            $tailwatch_obj->debug("User has a @/%/+ in it -- $user") if $tailwatch_obj->{'debug'};

            my $domain = ( split( m/[\%\@\+]+/, $user ) )[-1];

            $tailwatch_obj->debug("Found user domain to be $domain") if $tailwatch_obj->{'debug'};

            # If the cache is out of date, we force it up to date
            if ( $domain && !$self->{'import'} && !exists $tailwatch_obj->{'global_share'}{'data_cache'}{'domain_user_map'}{$domain} && $tailwatch_obj->{'global_share'}{'data_cache'}->{'cache_time'} <= ( stat('/etc/userdomains') )[9] ) {
                $tailwatch_obj->ensure_global_share(1);    #force recache
            }

            if (   $domain
                && exists $tailwatch_obj->{'global_share'}{'data_cache'}{'domain_user_map'}{$domain}
                && $tailwatch_obj->{'global_share'}{'data_cache'}{'domain_user_map'}{$domain} ) {
                $sender_domain = $domain;
                $user          = $tailwatch_obj->{'global_share'}{'data_cache'}{'domain_user_map'}{$domain};
            }
            else {
                $localsender = 0;
                $user        = '-remote-';                 # Indicates corrupt /etc/userdomains
                $tailwatch_obj->debug("Unable to locate user $user, using 'cpanel'") if $tailwatch_obj->{'debug'};
            }
        }

        $sender_domain = $tailwatch_obj->{'global_share'}{'data_cache'}{'user_domain_map'}{$user} if ( !$sender_domain );

        $self->{'internal_store'}{'sender_domain_cache'}{$msgid}  = [ time(), $sender_domain ];
        $self->{'internal_store'}{'sender_address_cache'}{$msgid} = [ time(), $address ];

        if ( $self->{'parse_only'} ) {
            return {
                'address'     => $address,
                'deliveredto' => $deliveredto,
                'msgid'       => $msgid,
                'date'        => $date,
                'time'        => $time,
                'direction'   => $direction,
                'cfg'         => \%CFG,
            };
        }
        $user          ||= '';    #cannot be null
        $sender_domain ||= '';    #cannot be null
        $spamscore     ||= '';    # cannot be null

        return $self->_process_eximstats_insert(
            'sends',
            q{INSERT INTO sends},
            [qw(sendunixtime msgid processed domain email user size host ip auth localsender spamscore sender)],
            [ $unixtime, $msgid, $processed, $sender_domain, $address, $user, $size, $host, $ip, $auth, $localsender, $spamscore, $sender ]
        );

    }
    elsif ( $direction eq '=>' || $direction eq '->' ) {
        if ( ++$self->{'internal_store'}{'lines_processed'} >= 512 ) {
            $self->{'internal_store'}{'lines_processed'} = 0;
            $self->_purge_info_cache();
        }

        delete $self->{'internal_store'}{'SENDER_MSGID_USER_MAP'}->{$msgid} if exists $self->{'internal_store'}{'SENDER_MSGID_USER_MAP'}->{$msgid};    # will already be used
        my $transport = $CFG{'T'} || '';
        $transport =~ s/:$// if $transport =~ tr{:}{};
        my $isremote  = index( $transport, 'remote' ) > -1 ? 1 : 0;
        my $processed = ( $isremote && $direction eq '=>' ? 0 : 2 );                                                                                   #we only process remote for back compat -- we still need to store it for searching and delivery reports though
        my ( $ip, $port );
        my $host   = $CFG{'H'};
        my $router = $CFG{'R'} || '';
        $router =~ s/:$// if defined $router && $router =~ tr{:}{};

        if ( $host && $host =~ tr/\[// ) {
            ( $host, $port ) = $self->parse_bracketed_host($host);
        }
        if ( !$ip && $line =~ tr/\[// ) {
            ( $ip, $port ) = $self->parse_ipdata_from_args( \@ARGS );
        }
        $host = '' unless defined $host;
        if ( $host =~ tr{()}{} ) {
            substr( $host, 0, 1, '' ) if substr( $host, 0, 1 ) eq '(';
            chop($host) if substr( $host, -1 ) eq ')';
        }

        $host ||= $ip;           #case 54426: always set the host var as its what we display
        $ip   ||= '127.0.0.1';
        $host ||= 'localhost';

        if ( $ip =~ tr{*}{} ) {
            $ip =~ s{\*}{};    # see http://www.exim.org/exim-html-3.30/doc/html/spec_48.html
                               # "The second and subsequent messages delivered down an existing connection are identified in the main log by the addition of an asterisk after the closing square bracket of the IP address
        }

        if ( !$address || !$msgid ) {
            $tailwatch_obj->error("Unable to parse [$line] for smtp");
            return;
        }

        if ( !$self->_validate_email_limits_data($now) ) {
            $self->_check_email_limits_for_hourly_reset($now);
        }

        my ( $recipient_user, $recipient_domain );

        if ( $router && index( $router, 'autowhitelist' ) > -1 ) {    #special case
            my $domain = $self->_get_sender_domain($msgid);

            # If the cache is out of date, we force it up to date
            if ( $domain && !$self->{'import'} && !exists $tailwatch_obj->{'global_share'}{'data_cache'}{'domain_user_map'}{$domain} && $tailwatch_obj->{'global_share'}{'data_cache'}->{'cache_time'} <= ( stat('/etc/userdomains') )[9] ) {
                $tailwatch_obj->ensure_global_share(1);    #force recache
            }
            if (   $domain
                && exists $tailwatch_obj->{'global_share'}{'data_cache'}{'domain_user_map'}{$domain}
                && $tailwatch_obj->{'global_share'}{'data_cache'}{'domain_user_map'}{$domain} ) {
                $recipient_user   = $tailwatch_obj->{'global_share'}{'data_cache'}{'domain_user_map'}{$domain};
                $recipient_domain = $domain;
            }
            else {
                $recipient_user = '-system-';
            }
        }
        else {
            if ( my $sender_domain = $self->_get_sender_domain($msgid) ) {
                $tailwatch_obj->debug("Got sender domain for $msgid ($sender_domain)") if $tailwatch_obj->{'debug'};
                $self->{'internal_store'}{'email_limits'}{$sender_domain}->[$CURRENT_EMAILS_PER_HOUR]++;

                $self->_sync_limit_to_fs($sender_domain);
            }
            else {
                $tailwatch_obj->debug("Could not get sender domain for $msgid") if $tailwatch_obj->{'debug'};
            }

            if ($isremote) {
                $recipient_user = '-remote-';
            }
            else {
                ( $recipient_domain, $recipient_user ) = $self->_get_domain_and_user_from_address_and_deliveredto( $tailwatch_obj, $address, $deliveredto );
            }
        }

        $recipient_domain ||= '';    #cannot be NULL
        $recipient_user   ||= '';    #cannot be NULL

        my ( $counted_domain, $counted_time, $counted_hour );

        if ( $isremote && exists $self->{'internal_store'}{'counted_domain_cache'}{$msgid} && $self->{'internal_store'}{'counted_domain_cache'}{$msgid}->[4] eq $address ) {
            ( $counted_domain, $counted_time, $counted_hour ) = @{ $self->{'internal_store'}{'counted_domain_cache'}{$msgid} }[ 1, 2, 3 ];
        }

        if ( $isremote && $ip && $router !~ m{autoreply} && $self->{'recent_recipient_mail_server_ips_fh'} ) {

            # We do not add unknown senders or auto replys to the recent
            # recipients list as they are likely not send by humans
            my $sender_localpart = $self->_get_sender_localpart($msgid);
            if ( $sender_localpart && $sender_localpart !~ m{^(?:dropbox|(?:do)?[-_]?not?[-_]?reply)} ) {
                my $range = $ip;
                if ( $unixtime > ( $now - $KEEP_RECENT_RECIPIENT_IPS_TIME ) ) {
                    if ( $range =~ m{:} ) {    #ipv6 must be quoted
                        syswrite( $self->{'recent_recipient_mail_server_ips_fh'}, qq{"$range" # $unixtime\n} );
                    }
                    else {
                        $range =~ s{\.[0-9]+$}{.0};
                        $range .= '/24';
                        syswrite( $self->{'recent_recipient_mail_server_ips_fh'}, qq{$range # $unixtime\n} );
                    }
                }
            }
        }

        if ( $self->{'parse_only'} ) {
            return {
                'address'     => $address,
                'deliveredto' => $deliveredto,
                'msgid'       => $msgid,
                'date'        => $date,
                'time'        => $time,
                'direction'   => $direction,
                'cfg'         => \%CFG,
                'ip'          => $ip,
            };
        }

        $counted_domain ||= '';    # cannot be null
        $counted_time   ||= 0;
        $counted_hour   ||= 0;

        local $LOG_DUPLICATES = 0 if $transport eq '**bypassed**';    # We can always bypass multiple times

        return $self->_process_eximstats_insert(
            'smtp',
            qq{INSERT INTO smtp},
            [qw(sendunixtime msgid email processed transport_method transport_is_remote host ip deliveredto router deliveryuser deliverydomain counteddomain countedtime countedhour)],
            [ $unixtime, $msgid, $address, $processed, $transport, $isremote, $host, $ip, $deliveredto, $router, $recipient_user, $recipient_domain, $counted_domain, $counted_time, $counted_hour ]
        );

    }
}

## Driver specific helpers ##

sub _ensure_sth {
    my ( $self, $sql ) = @_;

    $self->_ensure_dbh() or return;

    return $self->{'dbh'}->prepare_cached($sql);
}

sub _ensure_dbh {
    my ($self) = @_;

    # if we've failed to connect once, do modulus loop to keep from trying to connect every time (queries will then be logged)
    # when we restart, can't connect to sqlite, and have a lot of lines to process this will save a lot of overhead

    eval { require Cpanel::EximStats::DB::Sqlite; };

    if ($@) {
        $self->{'dbh_connect_failed'}++;
        $self->{'tailwatch_obj'}->log("[SQLERR] Could not create DBI object: $@");
        return;
    }

    if ( $self->{'dbh_connect_failed'} || !$self->{'dbh'} ) {
        if ( eval { $self->{'dbh'} = Cpanel::EximStats::DB::Sqlite->dbconnect() } ) {
            $self->{'dbh_pid'} = $$;
            $self->{'tailwatch_obj'}->debug('Using new DBI connection') if $self->{'tailwatch_obj'}->{'debug'};
            $self->{'dbh_connect_failed'} = 0;

            #At one point we were writing these DBs in non-WAL.
            #This conversion will auto-upgrade those.
            Cpanel::SQLite::Compat::upgrade_to_wal_journal_mode_if_needed( $self->{'dbh'} );

            return $self->{'dbh'};
        }
        else {
            $self->{'dbh'}     = undef;
            $self->{'dbh_pid'} = undef;
            $self->{'dbh_connect_failed'}++;
            $self->{'tailwatch_obj'}->log( "[SQLERR] Could not connect to Database: " . $@ || DBI->errstr() );
            return;
        }
    }
    else {
        if ( $self->{'dbh_pid'} != $$ ) {
            $self->{'tailwatch_obj'}->error('Attempted to use a database handle that was created before a fork(). This should NOT happen!');
            Cpanel::LoadModule::load_perl_module("Cpanel::Logger");
            my $logger = Cpanel::Logger->new();
            $logger->panic('Attempted to use an Eximstats database handle that was created before a fork(). This should NOT happen!');
        }
        $self->{'tailwatch_obj'}->debug('Reusing DBI connection') if $self->{'tailwatch_obj'}->{'debug'};
        return $self->{'dbh'};
    }
}

sub _get_sender_localpart {
    my ( $self, $msgid ) = @_;

    if ( exists $self->{'internal_store'}{'sender_address_cache'}{$msgid} ) {
        my $email = $self->{'internal_store'}{'sender_address_cache'}{$msgid}->[1];
        return ( split( m{\@}, $email ) )[0];
    }

    $self->_ensure_dbh() or return;

    my $quoted_msgid = $msgid =~ m/^(?:[^\W_]{6}-){2}[^\W_]{2}$/ ? qq{'$msgid'} : $self->quote($msgid);

    my $email = $self->{'dbh'}->selectrow_array( "select email from sends where msgid=" . $quoted_msgid );
    return length $email ? ( split( m{\@}, $email ) )[0] : undef;
}

sub _get_sender_domain {
    my ( $self, $msgid ) = @_;

    return $self->{'internal_store'}{'sender_domain_cache'}{$msgid}->[1]  if exists $self->{'internal_store'}{'sender_domain_cache'}{$msgid};
    return $self->{'internal_store'}{'counted_domain_cache'}{$msgid}->[1] if exists $self->{'internal_store'}{'counted_domain_cache'}{$msgid};

    $self->_ensure_dbh() or return;

    my $quoted_msgid = $msgid =~ m/^(?:[^\W_]{6}-){2}[^\W_]{2}$/ ? qq{'$msgid'} : $self->quote($msgid);

    return $self->{'dbh'}->selectrow_array( "select domain from sends where msgid=" . $quoted_msgid );
}

sub _purge_info_cache {
    my $self = shift;
    my $time = time();
    return if ( ( $self->{'last_info_cache_purge_time'} || 0 ) + $CACHE_PURGE_TIME > $time );

    $self->{'last_info_cache_purge_time'} = $time;

    foreach my $list_ref (
        [ 'SENDER_ADDRESS_PORT_USER_MAP', 2 ],
        [ 'SENDER_MSGID_USER_MAP',        2 ],
        [ 'SPAMSCORE_MSGID_MAP',          2 ],
        [ 'sender_domain_cache',          0 ],
        [ 'counted_domain_cache',         0 ],
        [ 'sender_address_cache',         0 ],

    ) {
        my ( $list, $time_position ) = @{$list_ref};
        my $cache_ref = $self->{'internal_store'}->{$list};

        delete @{$cache_ref}{
            grep {

                $cache_ref->{$_}->[$time_position] + $CACHE_PURGE_TIME < $time
              }
              keys %{$cache_ref}
        };

    }
    return;
}

sub quote {
    return $_[0]->{'dbh'}->quote( $_[1] );
}

sub _ansi_quote {
    my $string = $_[1];
    $string =~ s/'/''/g;
    return "'$string'";
}

sub _get_sth_or_string_as_sql_string_with_values {
    my ( $self, $sth, $values_ar ) = @_;

    # modified (different unpack, no more X than Y handling, no other methods used)
    # from DBIx::Std's $sth->get_display_only_plain_text_sql_from_values(\@values);
    my $position_of_next_qmark;
    my $sql       = ref $sth ? $sth->{'Statement'} : $sth;
    my $final_sql = '';

    for my $piece ( @{$values_ar} ) {
        last if ( ( $position_of_next_qmark = index( $sql, '?' ) ) == -1 );

        # does not do fancy placeholders, only '?'
        # binary data also may not be not handled: (IE driver handles ? in execute(), not via quote())
        # !! display purposes only not packaged for execution !!
        $final_sql .= substr( $sql, 0, $position_of_next_qmark, '' ) . ( ref $self->{'dbh'} ? $self->quote($piece) : $self->_ansi_quote($piece) );

        substr( $sql, 0, 1, '' );    # dump the qmark
    }

    return $final_sql . $sql;
}

sub _sql_execute {
    my ( $self, $tailwatch_obj, $table, $sth, $values_ref ) = @_;

    if ( !$sth ) {
        $tailwatch_obj->error("Statement handle not set");
        return;
    }

    $tailwatch_obj->debug( 'SQL: ' . $self->_get_sth_or_string_as_sql_string_with_values( $sth, $values_ref ) ) if $tailwatch_obj->{'debug'};

    my ( $log_failed_sql, $tries, $is_locked ) = ( 0, 0, 0 );
    while ( $tries++ < $MAX_LOCKED_DB_RETRIES ) {
        local $@;
        my $err;
        my $rc = eval { $sth->execute( @{$values_ref} ); };
        if ($@) {
            $err = $@;
        }

        if ( !$rc || $err || $DBI::errstr ) {

            # Tries already incremented
            if ( $MAX_LOCKED_DB_RETRIES > $tries && $self->_error_is_locked( $err, $DBI::errstr ) ) {
                _sleep(1);
                next;
            }

            my $is_dupe = $self->_error_is_dupe( $err, $DBI::errstr );
            $log_failed_sql = ( !$is_dupe || $LOG_DUPLICATES ) ? 1 : 0;

            if ($log_failed_sql) {
                my $err_message = $err ? Cpanel::Exception::get_string($err) : $DBI::errstr || '';
                $tailwatch_obj->error( "SQL Failed with error ($err_message): " . $self->_get_sth_or_string_as_sql_string_with_values( $sth, $values_ref ) );
            }
        }

        last if !$err || $err && !$is_locked;
    }

    return if $log_failed_sql;
    return 1;
}

sub _get_epoch_from_iso8601_or_now {

    if ( $_[0]->{'_cached_get_epoch_from_iso8601_or_now'}->[0] eq $_[1] ) {
        return $_[0]->{'_cached_get_epoch_from_iso8601_or_now'}->[1];
    }

    return time() if length( $_[1] ) < length('1970-01-01 00:00:00');

    return (
        $_[0]->{'_cached_get_epoch_from_iso8601_or_now'} =    #
          [                                                   #
            $_[1],                                            #
            (
                int(
                    Time::Local::timelocal_nocheck(

                        #2016-12-25 05:03:0

                        substr( $_[1], 17, 2 ),           # sec
                        substr( $_[1], 14, 2 ),           # min
                        substr( $_[1], 11, 2 ),           # hour
                        substr( $_[1], 8,  2 ),           # mday
                        ( substr( $_[1], 5, 2 ) - 1 ),    # mon
                        substr( $_[1], 0, 4 )             # year
                    )
                  )
                  || time()
            )    #
          ]    #
    )->[1];    #
}

sub _check_relayips {
    my ( $self, $tailwatch_obj ) = @_;
    if ( !exists $self->{'internal_store'}{'relayips_cache_time'} ) {
        $self->{'internal_store'}{'relayips_cache_time'} = 0;
    }
    else {
        return if $self->{'import'};
    }
    my $mtime = int( ( stat('/etc/demousers') )[9] );
    if ( ( $self->{'internal_store'}{'relayips_cache_time'} + 1800 ) < $mtime ) {
        $self->_load_relayips($tailwatch_obj);
    }
}

sub _load_relayips {
    my ($self) = @_;
    $self->{'internal_store'}{'relayips_cache_time'} = time;
    $self->{'internal_store'}{'relayips'}            = {};

    # FIXME: If the recentauthedmailiptracker module is loaded we can just pull the data from there (if its not this file isn't being updated anyways... however that doesn't acocunt for always relay)
    if ( -e '/etc/recent_authed_mail_ips' && -e '/etc/recent_authed_mail_ips_users' ) {

        # case 43151, case 43150
        my $recent_authed_mail_ips_users_is_up_to_date = ( stat(_) )[9] + 7200 > time() ? 1 : 0;
        if ( $recent_authed_mail_ips_users_is_up_to_date && open my $fh, '<', '/etc/recent_authed_mail_ips_users' ) {
            while ( my $line = readline($fh) ) {
                chomp $line;
                my ( $ip, $users ) = split( m/:\s*/, $line );
                next if $self->{'tailwatch_obj'}->_is_loopback($ip);
                my $internal_store_relayips_ip_ref = $self->{'internal_store'}{'relayips'}{$ip};
                foreach my $user ( split( /\s*\,\s*/, $users ) ) {
                    $user =~ s/\/.*$//g if $user =~ tr/\///;
                    $user =~ tr/+%:/@/;
                    push @{$internal_store_relayips_ip_ref}, $user;
                }
            }
            close $fh;
        }
        $self->{'tailwatch_obj'}->debug("/etc/recent_authed_mail_ips_users is more than two hours old, not using for user calculation") if !$recent_authed_mail_ips_users_is_up_to_date && $self->{'tailwatch_obj'}->{'debug'};
    }
}

sub _validate_email_limits_data {
    my $self = shift;
    my $now  = shift || time();

    return 1 if $now == ( $self->{'internal_store'}{'last_validate_email_limits_data'} || 0 );
    $self->{'internal_store'}{'last_validate_email_limits_data'} = $now;

    my $mtime = int( ( stat('/etc/email_send_limits') )[9] );
    if ( !exists $self->{'internal_store'}{'email_limits_mtime'} || $mtime != $self->{'internal_store'}{'email_limits_mtime'} ) {
        $self->_setup_email_limits_data();
        $self->_sync_all_limits_to_fs();
        return 1;
    }
    return 0;
}

sub _check_email_limits_for_hourly_reset {
    my $self  = shift;
    my $now   = shift || time();
    my $force = shift;

    $self->_purge_info_cache();

    my $starttime = $now - ( $now % 3600 );
    if ( $force || $self->{'internal_store'}{'email_limits_starttime'} != $starttime ) {
        alarm(0);    #cancel any alarms

        $self->_reset_email_limits_data($starttime);
        Cpanel::EmailTracker::Purge::purge_old_tracker_files();
        return 1;
    }
    return 0;
}

sub _force_email_limits_hourly_reset {
    my $self = shift;
    return $self->_check_email_limits_for_hourly_reset( undef, 1 );
}

sub _check_for_time_to_trim_recipient_mail_server_ips {
    my $self = shift;
    my $now  = shift || time();

    my $trimtime = $now - ( $now % 600 );    # Trim every 10 minutes
    if ( !$self->{'internal_store'}{'last_trim_recent_recipient_mail_server_ips_time'} || $self->{'internal_store'}{'last_trim_recent_recipient_mail_server_ips_time'} != $trimtime ) {
        $self->_trim_recent_recipient_mail_server_ips_and_open_for_append();
        $self->{'internal_store'}{'last_trim_recent_recipient_mail_server_ips_time'} = $trimtime;
        return 1;
    }

    return 0;
}

sub _trim_recent_recipient_mail_server_ips_and_open_for_append {
    my ($self) = @_;

    my $tailwatch_obj = $self->{'tailwatch_obj'};

    my $temp_file = $Cpanel::ConfigFiles::RECENT_RECIPIENT_MAIL_SERVER_IPS_FILE . '.trim';
    open( my $read_fh, '<', $Cpanel::ConfigFiles::RECENT_RECIPIENT_MAIL_SERVER_IPS_FILE ) || do {
        $tailwatch_obj->error("Failed to open “$Cpanel::ConfigFiles::RECENT_RECIPIENT_MAIL_SERVER_IPS_FILE” for read because of an error: $!");
        return;
    };
    open( my $write_fh, '>', $temp_file ) || do {
        $tailwatch_obj->error("Failed to open “$temp_file” for write because of an error: $!");
        return;
    };

    # CPANEL-1973: Ensures permissions are set on the RECENT_RECIPIENT_MAIL_SERVER_IPS_FILE file
    $self->{'_mailgid'} ||= ( getgrnam('mail') )[2];
    chown( 0, $self->{'_mailgid'}, $write_fh );
    chmod( $RECENT_RECIPIENT_MAIL_SERVER_IPS_FILE_PERMS, $write_fh );

    my $expire_time = ( time() - $KEEP_RECENT_RECIPIENT_IPS_TIME );

    # Copy all the unexpired entries to a new file
    my %seen;
    while ( my $lines = Cpanel::IO::read_bytes_to_end_of_line( $read_fh, $READ_BUFFER_SIZE ) ) {

        # read_bytes_to_end_of_line allows us to avoid
        # multiple readline calls and process a block of
        # lines in a single more focused loop to gain speed
        $lines =~ s{[\n]$}{};    # Avoid the need to chomp() every loop
        foreach ( split( m{[\n]}, $lines ) ) {
            my ( $ip, $timestamp ) = split( m{[ #]+}, $_ );
            if ( $ip && $timestamp > $expire_time && ( !$seen{$ip} || $seen{$ip} < $timestamp ) ) {
                $seen{$ip} = $timestamp;
            }
        }
    }
    close($read_fh);

    if ( keys %seen ) {
        print {$write_fh} join( "\n", map { "$_ # $seen{$_}" } keys %seen ) . "\n";
    }
    close($write_fh);

    rename( $temp_file, $Cpanel::ConfigFiles::RECENT_RECIPIENT_MAIL_SERVER_IPS_FILE ) || do {
        $tailwatch_obj->error("Failed to rename “$temp_file” to “$Cpanel::ConfigFiles::RECENT_RECIPIENT_MAIL_SERVER_IPS_FILE” because of an error: $!");
        return;
    };

    open( $self->{'recent_recipient_mail_server_ips_fh'}, '>>', $Cpanel::ConfigFiles::RECENT_RECIPIENT_MAIL_SERVER_IPS_FILE ) or do {
        $tailwatch_obj->error("Failed to open “$Cpanel::ConfigFiles::RECENT_RECIPIENT_MAIL_SERVER_IPS_FILE” for append because of an error: $!");
    };

    return 1;
}

sub _reset_email_limits_data {
    my $self      = shift;
    my $starttime = shift;

    return if $self->{'import'};

    if ($DEBUG) {
        $self->_ensure_dbh(-100) or return;    #-100 is forced

        foreach my $domain ( keys %{ $self->{'internal_store'}{'email_limits'} } ) {
            my $file     = "/var/cpanel/email_send_limits/track/$domain/" . join( '.', ( gmtime( $self->{'internal_store'}{'email_limits_starttime'} ) )[ 2, 3, 4, 5 ] );
            my $fs_count = ( ( stat($file) )[7] || 0 );

            $self->{'tailwatch_obj'}->log("FS Count for $domain ($file): $fs_count");
        }

        # $self->{'tailwatch_obj'}->log( "Emails: " . Data::Dumper::Dumper( $self->{'internal_store'}{'emails'} ) );
        delete $self->{'internal_store'}{'emails'};
    }

    $self->{'internal_store'}{'email_limits_starttime'} = $starttime;
    $self->{'tailwatch_obj'}->log("Resetting email limits to new starttime of $starttime");
    foreach my $domain ( grep { $_ ne '*' } keys %{ $self->{'internal_store'}{'email_limits'} } ) {
        unlink( '/var/cpanel/email_send_limits/max_emails_' . $domain )    if ( $self->{'internal_store'}{'email_limits'}{$domain}->[$REACHED_MAX_EMAIL_PER_HOUR] );
        unlink( '/var/cpanel/email_send_limits/max_deferfail_' . $domain ) if ( $self->{'internal_store'}{'email_limits'}{$domain}->[$REACHED_MAX_DEFER_FAIL_PER_HOUR] );
        @{ $self->{'internal_store'}{'email_limits'}{$domain} }[ $CURRENT_EMAILS_PER_HOUR, $CURRENT_DEFER_FAIL, $REACHED_MAX_EMAIL_PER_HOUR, $REACHED_MAX_DEFER_FAIL_PER_HOUR ] = ( 0, 0, 0, 0 );
    }
}

sub _setup_email_limits_data {
    my $self = shift;

    $self->_ensure_dbh() or return;

    #..{'internal_store} = {
    #   'email_limits_starttime' => XXX % 3600
    #   'email_limits' => [
    #        'MAX_EMAIL_PER_HOUR',  <= whole number
    #        'MAX_DEFER_FAIL_PERCENTAGE',  <= percent
    #        'MIN_DEFER_FAIL_TO_TRIGGER_PROTECTION',  <= whole number (Replaced with constant number)
    #        'CURRENT_EMAILS_PER_HOUR',
    #        'CURRENT_DEFER_FAIL',
    #        'REACHED_MAX_EMAIL_PER_HOUR',
    #        'REACHED_MAX_DEFER_FAIL_PER_HOUR',
    #    ];
    #}
    my $now       = time();
    my $starttime = $now - ( $now % 3600 );
    my $endtime   = $starttime + 3600;

    $self->{'internal_store'}{'email_limits_starttime'} = $starttime;

    return if $self->{'import'};

    $self->{'tailwatch_obj'}->log("Loading email sending limits from $starttime - $endtime");

    if ( open( my $email_limits_fh, '<', '/etc/email_send_limits' ) ) {
        $self->{'internal_store'}{'email_limits_mtime'} = ( stat($email_limits_fh) )[9];
        readline($email_limits_fh);    #version info
        readline($email_limits_fh);    #format info

        $self->{'internal_store'}{'email_limits'} = {
            map { ( ( $_->[0] && $_->[1] ) ? ( $_->[0] => [ split ',', $_->[1], -1 ] ) : () ) }
            map { [ split( m/(?:\: |\n)/, $_, 3 ) ] } (<$email_limits_fh>)
        };

        # $data =         {
        #            'SUCCESSCOUNT' => '239',
        #            'SENDCOUNT' => '239',
        #            'DEFERCOUNT' => '0',
        #            'FAILCOUNT' => '0',
        #            'DOMAIN' => 'pi.nt'
        #          }
        close($email_limits_fh);

        my $domain_group_stats = Cpanel::DeliveryReporter::group_stats(    # PPI NO PARSE - We only need Cpanel::DeliveryReport::Basic which provides group_stats (this module has odd namespace)
            ( bless { 'dbh' => $self->{'dbh'} }, 'Cpanel::DeliveryReporter' ),    # we fake an object to avoid loading the entire DeliveryReporter namespace (10MiB),
            'starttime'    => $starttime,                                         #
            'endtime'      => $endtime,                                           #
            'group'        => 'domain',                                           #
            'sort'         => 'none',                                             #
            'nosize'       => 1,                                                  #
            'nouser'       => 1,                                                  #
            'deliverytype' => 'remote_or_faildefer'                               #
        );

        if ( ref $domain_group_stats eq 'ARRAY' ) {

            foreach my $data ( @{$domain_group_stats} ) {

                next if ( !$data->{'DOMAIN'} );
                @{ $self->{'internal_store'}{'email_limits'}{ $data->{'DOMAIN'} } }[ $CURRENT_EMAILS_PER_HOUR, $CURRENT_DEFER_FAIL ] = ( $data->{'SUCCESSCOUNT'}, $data->{'FAILCOUNT'} + $data->{'DEFERCOUNT'} );
            }

        }
        else {
            $self->{'tailwatch_obj'}->log( "[SQLERR] Fetching group_stats for domains failed.  Do you need to run /usr/local/cpanel/bin/updateeximstats?  The exact error was: " . DBI->errstr() );
        }
    }

    return 1;
}

sub _sync_all_limits_to_fs {
    my $self = shift;

    return if $self->{'import'};

    my $fs_limits             = $self->_fetch_fs_limits_list();
    my $EMAIL_DEFER_THRESHOLD = Cpanel::Email::DeferThreshold::defer_threshold();

    foreach my $domain ( sort grep { $_ ne '*' } keys %{ $self->{'internal_store'}{'email_limits'} } ) {
        my ( $max_emails, $max_deferfail ) = $self->_check_email_limits($domain);
        if ($max_emails) {
            if ( !exists $fs_limits->{ 'max_emails_' . $domain } ) {
                open( my $email_send_limits_fh, '>', '/var/cpanel/email_send_limits/max_emails_' . $domain );
                print {$email_send_limits_fh} $self->{'internal_store'}{'email_limits'}{$domain}->[$CURRENT_EMAILS_PER_HOUR] . '/' . $self->{'internal_store'}{'email_limits'}{$domain}->[$MAX_EMAIL_PER_HOUR];
            }
            $self->{'internal_store'}{'email_limits'}{$domain}->[$REACHED_MAX_EMAIL_PER_HOUR] = 1;
        }
        else {
            unlink( '/var/cpanel/email_send_limits/max_emails_' . $domain ) if exists $fs_limits->{ 'max_emails_' . $domain };
        }
        if ($max_deferfail) {
            if ( !exists $fs_limits->{ 'max_deferfail_' . $domain } ) {
                open( my $email_send_limits_fh, '>', '/var/cpanel/email_send_limits/max_deferfail_' . $domain );
                print {$email_send_limits_fh} $self->{'internal_store'}{'email_limits'}{$domain}->[$CURRENT_DEFER_FAIL] . '/'
                  . $EMAIL_DEFER_THRESHOLD . ' ('
                  . int( ( $self->{'internal_store'}{'email_limits'}{$domain}->[$CURRENT_DEFER_FAIL] / ( $self->{'internal_store'}{'email_limits'}{$domain}->[$CURRENT_EMAILS_PER_HOUR] + $self->{'internal_store'}{'email_limits'}{$domain}->[$CURRENT_DEFER_FAIL] ) ) * 100 ) . '%)';
            }
            $self->{'internal_store'}{'email_limits'}{$domain}->[$REACHED_MAX_DEFER_FAIL_PER_HOUR] = 1;
        }
        else {
            unlink( '/var/cpanel/email_send_limits/max_deferfail_' . $domain ) if exists $fs_limits->{ 'max_deferfail_' . $domain };
        }
    }
}

sub _fetch_fs_limits_list {
    my $self = shift;
    if ( opendir( my $email_send_limits_dh, '/var/cpanel/email_send_limits/' ) ) {
        return { map { /^\./ ? () : ( $_ => undef ) } ( readdir($email_send_limits_dh) ) };
    }
}

sub _sync_limit_to_fs {
    my ( $self, $domain ) = @_;

    return if $self->{'import'};

    my ( $max_emails, $max_deferfail ) = $self->_check_email_limits($domain);

    if ($max_emails) {
        open( my $email_send_limits_fh, '>', '/var/cpanel/email_send_limits/max_emails_' . $domain );
        print {$email_send_limits_fh} $self->{'internal_store'}{'email_limits'}{$domain}->[$CURRENT_EMAILS_PER_HOUR] . '/' . $self->{'internal_store'}{'email_limits'}{$domain}->[$MAX_EMAIL_PER_HOUR];
        $self->{'internal_store'}{'email_limits'}{$domain}->[$REACHED_MAX_EMAIL_PER_HOUR] = 1;
        $self->{'tailwatch_obj'}->log("[$domain] Max Email/Hour Limit reached ($max_emails)");
    }
    if ($max_deferfail) {
        my $EMAIL_DEFER_THRESHOLD = Cpanel::Email::DeferThreshold::defer_threshold();
        open( my $email_send_limits_fh, '>', '/var/cpanel/email_send_limits/max_deferfail_' . $domain );
        print {$email_send_limits_fh} $self->{'internal_store'}{'email_limits'}{$domain}->[$CURRENT_DEFER_FAIL] . '/'
          . $EMAIL_DEFER_THRESHOLD . ' ('
          . int( ( $self->{'internal_store'}{'email_limits'}{$domain}->[$CURRENT_DEFER_FAIL] / ( $self->{'internal_store'}{'email_limits'}{$domain}->[$CURRENT_EMAILS_PER_HOUR] + $self->{'internal_store'}{'email_limits'}{$domain}->[$CURRENT_DEFER_FAIL] ) ) * 100 ) . '%)';

        $self->{'internal_store'}{'email_limits'}{$domain}->[$REACHED_MAX_DEFER_FAIL_PER_HOUR] = 1;
        $self->{'tailwatch_obj'}->log("[$domain] Defer/Fail Percentage  Limit reached ($max_deferfail)");
    }
}

sub _check_email_limits {
    my ( $self, $domain ) = @_;

    if (   !defined $self->{'internal_store'}{'email_limits'}{$domain}->[$MAX_EMAIL_PER_HOUR]
        || !defined $self->{'internal_store'}{'email_limits'}{$domain}->[$MAX_DEFER_FAIL_PERCENTAGE] ) {
        return ( 0, 0 ) if !exists $self->{'internal_store'}{'email_limits'}{'*'};
        $self->{'internal_store'}{'email_limits'}{$domain}->[$MAX_EMAIL_PER_HOUR]        ||= $self->{'internal_store'}{'email_limits'}{'*'}->[$MAX_EMAIL_PER_HOUR];
        $self->{'internal_store'}{'email_limits'}{$domain}->[$MAX_DEFER_FAIL_PERCENTAGE] ||= $self->{'internal_store'}{'email_limits'}{'*'}->[$MAX_DEFER_FAIL_PERCENTAGE];
    }

    my $EMAIL_DEFER_THRESHOLD = Cpanel::Email::DeferThreshold::defer_threshold();
    $self->{'tailwatch_obj'}->debug(
        "_check_email_limits [$domain]
        MAX_EMAIL_PER_HOUR = $self->{'internal_store'}{'email_limits'}{$domain}->[$MAX_EMAIL_PER_HOUR]
        MAX_DEFER_FAIL_PERCENTAGE = $self->{'internal_store'}{'email_limits'}{$domain}->[$MAX_DEFER_FAIL_PERCENTAGE]
        MIN_DEFER_FAIL_TO_TRIGGER_PROTECTION = $EMAIL_DEFER_THRESHOLD
        CURRENT_EMAILS_PER_HOUR = $self->{'internal_store'}{'email_limits'}{$domain}->[$CURRENT_EMAILS_PER_HOUR]
        CURRENT_DEFER_FAIL = $self->{'internal_store'}{'email_limits'}{$domain}->[$CURRENT_DEFER_FAIL]
        REACHED_MAX_EMAIL_PER_HOUR = $self->{'internal_store'}{'email_limits'}{$domain}->[$REACHED_MAX_EMAIL_PER_HOUR]
        REACHED_MAX_DEFER_FAIL_PER_HOUR = $self->{'internal_store'}{'email_limits'}{$domain}->[$REACHED_MAX_DEFER_FAIL_PER_HOUR]"
    ) if $self->{'tailwatch_obj'}->{'debug'};

    if ( $self->{'internal_store'}{'email_limits'}{$domain}->[$MAX_EMAIL_PER_HOUR] || $self->{'internal_store'}{'email_limits'}{$domain}->[$MAX_DEFER_FAIL_PERCENTAGE] ) {
        my ( $max_email, $max_deferfail );
        if (  !$self->{'internal_store'}{'email_limits'}{$domain}->[$REACHED_MAX_EMAIL_PER_HOUR]
            && $self->{'internal_store'}{'email_limits'}{$domain}->[$MAX_EMAIL_PER_HOUR]
            && $self->{'internal_store'}{'email_limits'}{$domain}->[$MAX_EMAIL_PER_HOUR] ne 'unlimited'
            && $self->{'internal_store'}{'email_limits'}{$domain}->[$CURRENT_EMAILS_PER_HOUR]
            && $self->{'internal_store'}{'email_limits'}{$domain}->[$CURRENT_EMAILS_PER_HOUR] >= $self->{'internal_store'}{'email_limits'}{$domain}->[$MAX_EMAIL_PER_HOUR] ) {
            $max_email = $self->{'internal_store'}{'email_limits'}{$domain}->[$MAX_EMAIL_PER_HOUR];
        }
        if (  !$self->{'internal_store'}{'email_limits'}{$domain}->[$REACHED_MAX_DEFER_FAIL_PER_HOUR]
            && $self->{'internal_store'}{'email_limits'}{$domain}->[$MAX_DEFER_FAIL_PERCENTAGE]
            && $self->{'internal_store'}{'email_limits'}{$domain}->[$MAX_DEFER_FAIL_PERCENTAGE] ne 'unlimited'
            && $self->{'internal_store'}{'email_limits'}{$domain}->[$CURRENT_DEFER_FAIL]
            && $self->{'internal_store'}{'email_limits'}{$domain}->[$CURRENT_DEFER_FAIL] >= $EMAIL_DEFER_THRESHOLD
            && ( ( $self->{'internal_store'}{'email_limits'}{$domain}->[$CURRENT_DEFER_FAIL] / ( $self->{'internal_store'}{'email_limits'}{$domain}->[$CURRENT_EMAILS_PER_HOUR] + $self->{'internal_store'}{'email_limits'}{$domain}->[$CURRENT_DEFER_FAIL] ) ) * 100 ) >= $self->{'internal_store'}{'email_limits'}{$domain}->[$MAX_DEFER_FAIL_PERCENTAGE] ) {
            $max_deferfail = $self->{'internal_store'}{'email_limits'}{$domain}->[$MAX_DEFER_FAIL_PERCENTAGE];
        }
        return ( $max_email, $max_deferfail );
    }
    return ( 0, 0 );
}

sub parse_ipdata_from_args {
    return if join( '', @{ $_[1] } ) !~ tr/\[//;

    if ( my $ip = ( grep { index( $_, '[' ) == 0 } @{ $_[1] } )[0] ) {
        $ip =~ tr/[]//d;
        return $ip if $ip !~ tr{:}{};    # no port

        return split( m/:/, $ip ) if ( $ip =~ tr{:}{} ) == 1;    # ip, port

        my @ipdata = split( m/:/, $ip );                         # ipv6, port
        my $port   = pop @ipdata;
        return ( join( ':', @ipdata ), $port );
    }
    return;
}

sub parse_bracketed_host {
    my ( $self, $host, $port ) = @_;
    $host =~ s/^\(?\[//;
    $host =~ s/\]\)?//;
    if ( $host =~ tr/:// ) {
        my @host_data = split( m/:/, $host );
        $port = pop @host_data;
        $host = join( ':', @host_data );
    }
    return ( $host, $port );
}

sub _process_eximstats_insert {
    my ( $self, $table, $query, $keys_ref, $values_ref ) = @_;
    my $all_valid = 1;
    for my $keynum ( 0 .. $#$values_ref ) {
        if ( !defined $values_ref->[$keynum] ) {
            $all_valid = 0;
            last;
        }
    }

    if ( $all_valid && $self->{'buffered_sql'} ) {
        push @{ $self->{'sql_buffer'} }, $query . ' (' . join( ',', @$keys_ref ) . ') VALUES(' . join(
            ',',
            map {
                # BEGIN INLINE QUOTE CACHE
                # inline the quote cache since its called ~ 1267244 times for a 150k line file
                (    # INLINED QUOTE CACHE
                    exists $self->{'quote_cache'}->{$_}    # INLINED QUOTE CACHE
                    ?                                      # INLINED QUOTE CACHE
                      $self->{'quote_cache'}->{$_}         # INLINED QUOTE CACHE
                    :                                      # INLINED QUOTE CACHE
                      (
                        $self->{'quote_cache'}->{$_} = (
                            $_ =~ tr{-,& /*+|@."<>()[]:=A-Za-z0-9_}{}c    # USE quote if the string contains any characters except the safe ones in this tr
                            ? $self->{'dbh'}->quote($_)
                            : qq{'$_'}
                        )
                      )                                                   # INLINED QUOTE CACHE
                  )                                                       # INLINED QUOTE CACHE
                                                                          # END INLINE QUOTE CACHE
            } @$values_ref
        ) . ')' . ";\n";
        return 1;
    }

    my ( @valid_keys, @valid_values );
    if ($all_valid) {
        @valid_keys   = @{$keys_ref};
        @valid_values = @{$values_ref};

    }
    else {
        for my $keynum ( 0 .. $#$keys_ref ) {
            if ( !defined $values_ref->[$keynum] ) {

                next;
            }

            push @valid_keys,   $keys_ref->[$keynum];
            push @valid_values, $values_ref->[$keynum];
        }
    }

    if ( $self->{'buffered_sql'} ) {
        push @{ $self->{'sql_buffer'} }, $query . ' (' . join( ',', @valid_keys ) . ') VALUES(' . join(
            ',',
            map {
                # BEGIN INLINE QUOTE CACHE
                # inline the quote cache since its called ~ 1267244 times for a 150k line file
                (    # INLINED QUOTE CACHE
                    exists $self->{'quote_cache'}->{$_}    # INLINED QUOTE CACHE
                    ?                                      # INLINED QUOTE CACHE
                      $self->{'quote_cache'}->{$_}         # INLINED QUOTE CACHE
                    :                                                                 # INLINED QUOTE CACHE
                      ( $self->{'quote_cache'}->{$_} = $self->{'dbh'}->quote($_) )    # INLINED QUOTE CACHE
                  )                                                                   # INLINED QUOTE CACHE
                                                                                      # END INLINE QUOTE CACHE
            } @valid_values
        ) . ')' . ";\n";
        return 1;
    }

    $query .= ' (' . join( ',', @valid_keys ) . ') VALUES(' . join( ',', ('?') x scalar @valid_keys ) . ')';

    return $self->_process_eximstats_call(
        $table,
        $query,
        \@valid_values
    );

}

*_process_eximstats_update = \&_process_eximstats_call;

sub _process_eximstats_call {
    my ( $self, $table, $query, $values_ref ) = @_;

    return $self->_get_sth_or_string_as_sql_string_with_values( $query, $values_ref ) if $self->{'sql_only'};

    my $sth = $self->_ensure_sth($query);

    if ( !$sth ) {
        $self->{'tailwatch_obj'}->log("[SQLERR] Could not prepare query, logging SQL to /var/cpanel/sql");
        $self->{'tailwatch_obj'}->log_sql( $self->_get_sth_or_string_as_sql_string_with_values( $query, $values_ref ) );
        return 0;
    }

    if ( $self->{'buffered_sql'} ) {
        push @{ $self->{'sql_buffer'} }, $self->_get_sth_or_string_as_sql_string_with_values( $sth, $values_ref ) . ";\n";
        return 1;
    }

    if ( !$self->_sql_execute( $self->{'tailwatch_obj'}, $table, $sth, $values_ref ) ) {
        $self->{'tailwatch_obj'}->log("[SQLERR] Could not execute query, logging SQL to /var/cpanel/sql");
        $self->{'tailwatch_obj'}->log_sql( $self->_get_sth_or_string_as_sql_string_with_values( $sth, $values_ref ) );
        return 0;
    }

    return 1;
}

sub commit_buffer {
    my ($self) = @_;

    return if !$self->{'buffered_sql'};

    return 1 if !scalar @{ $self->{'sql_buffer'} };

    $self->_ensure_dbh();

    my $error_occurred = 0;
    my $tries          = 0;
    while ( $tries++ < $MAX_LOCKED_DB_RETRIES ) {

        local $@;
        my ( $err, $is_dupe, $is_locked );
        eval {
            $self->{'dbh'}->begin_work();
            $self->{'dbh'}->do( join( '', @{ $self->{'sql_buffer'} } ) );
            $self->{'dbh'}->commit();
        };

        if ($@) {
            $err = $@;

            # Ignoring errors here for now
            eval { $self->{'dbh'}->rollback(); };

            # tries already incremented
            if ( $MAX_LOCKED_DB_RETRIES > $tries && ( $is_locked = $self->_error_is_locked( $err, $DBI::errstr ) ) ) {
                _sleep(1);
                next;
            }
            $is_dupe = $self->_error_is_dupe( $err, $DBI::errstr );

            if ( !$is_dupe ) {
                my $error_message = $err ? Cpanel::Exception::get_string_no_id($err) : $DBI::errstr || '';
                $self->{'tailwatch_obj'}->error("[SQLERR] There were SQL commands that did not complete successfully. Check the SQL log for which commands failed in /var/cpanel/sql/eximstats.sql:");
                $self->{'tailwatch_obj'}->log_sql( join( '', @{ $self->{'sql_buffer'} } ) );

                $error_occurred = 1;
            }
            else {
                # We got a duplicate, so unroll the buffer and attempt each line
                $error_occurred = $self->_commit_sql_buffer_by_line();
            }
        }

        last if !$err || $err && !$is_locked;
    }

    $self->{'sql_buffer'} = [];

    return $error_occurred ? 0 : 1;
}

sub _commit_sql_buffer_by_line {
    my ($self) = @_;

    my $error_occurred = 0;
    my $err;
    my @errors;

    # We got a duplicate, so unroll the buffer and attempt each line
    my $write_sql_log_file = 0;

    for my $statement ( @{ $self->{'sql_buffer'} } ) {
        chomp($statement);
        next if !length $statement;

        my $tries     = 0;
        my $is_locked = 0;
        while ( $tries++ < $MAX_LOCKED_DB_RETRIES ) {
            eval { $self->{'dbh'}->do($statement); };
            if ($@) {
                $err = $@;

                # tries already incremented
                if ( $MAX_LOCKED_DB_RETRIES > $tries && ( $is_locked = $self->_error_is_locked( $err, $DBI::errstr ) ) ) {
                    _sleep(1);
                    next;
                }
                my $is_dupe = $self->_error_is_dupe( $err, $DBI::errstr );

                if ( $LOG_DUPLICATES || !$is_dupe ) {
                    $write_sql_log_file = 1 if !$is_dupe;

                    # arrayref for speed
                    push @errors, [ $statement, $err, $DBI::errstr, $is_dupe ];
                }
            }

            last if !$err || $err && !$is_locked;
        }
    }

    if (@errors) {
        if ($write_sql_log_file) {
            $self->{'tailwatch_obj'}->error("[SQLERR] There were SQL commands that did not complete successfully. Check the SQL log for which commands failed in /var/cpanel/sql/eximstats.sql:");
        }
        else {
            $self->{'tailwatch_obj'}->error("[SQLERR] There were SQL commands that did not complete successfully.");    # all dupes
        }

        # 0 => statement, 1 => exception, 2 => $DBI::errstr, 3 => is_dupe
        for my $error (@errors) {
            my $error_message = $error->[1] ? Cpanel::Exception::get_string_no_id( $error->[1] ) : $error->[2] || '';
            $self->{'tailwatch_obj'}->error($error_message);

            # Do not log duplicates since we will never be able to reinsert them
            # and it will always result in failure. Duplicates
            # should be considered a bug in this module or a corrupt
            # database.
            $self->{'tailwatch_obj'}->log_sql( $error->[0] ) unless $error->[3];    # unless is_dupe
        }

        $error_occurred = 1;
    }

    return $error_occurred;
}

sub _sleep {
    return sleep( $_[0] || 1 );
}

sub _error_is_dupe {
    my ( $self, $error, $dbi_error ) = @_;

    local $@;
    if ( eval { $error->isa('Cpanel::Exception::Database::Error') } ) {
        return $error->failure_is('SQLITE_CONSTRAINT') ? 1 : 0;
    }
    elsif ( length $dbi_error && $dbi_error =~ m/^UNIQUE/ ) {
        return 1;
    }

    return 0;
}

sub _error_is_locked {
    my ( $self, $error, $dbi_error ) = @_;

    local $@;
    if ( eval { $error->isa('Cpanel::Exception::Database::Error') } ) {
        return $error->failure_is('SQLITE_LOCKED') ? 1 : 0;
    }
    elsif ( length $dbi_error && $dbi_error =~ m/^database is locked/ ) {
        return 1;
    }

    return 0;
}

sub import_sql_file {
    my ( $self, $file ) = @_;

    # do not create task if $file doesn't exist or if an WHM upgrade is in progress
    return 1 if not -e $file or ( -e $_UPGRADE_IN_PROGRESS_FILE and not -e q{/var/cpanel/dev_sandbox} );

    # note, Cpanel::TaskProcessors::TailwatchTasks::eximstats_import_sql_file will not process
    # $file if another eximstats_import_sql_file task is still in progress, even if $file exists
    return eval { Cpanel::ServerTasks::queue_task( ['TailwatchTasks'], qq{eximstats_import_sql_file $file} ); };
}

sub _get_domain_and_user_from_address_and_deliveredto {
    my ( $self, $tailwatch_obj, $address, $deliveredto ) = @_;
    my ( $deliverydomain, $deliveryuser );

    my $delivery_target = $deliveredto =~ tr{%@+}{} ? $deliveredto : $address;

    if ( $delivery_target =~ tr{%@+}{} ) {
        my $domain = ( split( m/[\%\@\+]+/, $delivery_target ) )[-1];

        if ( length $domain && $domain eq $tailwatch_obj->{'global_share'}{'data_cache'}{'hostname'} ) {
            $deliveryuser   = ( split( m/[\%\@\+]+/, $delivery_target ) )[0];
            $deliverydomain = $tailwatch_obj->{'global_share'}{'data_cache'}{'user_domain_map'}{$deliveryuser};
        }
        else {

            # If the cache is out of date, we force it up to date
            if ( $domain && !$self->{'import'} && !exists $tailwatch_obj->{'global_share'}{'data_cache'}{'domain_user_map'}{$domain} && $tailwatch_obj->{'global_share'}{'data_cache'}->{'cache_time'} <= ( stat('/etc/userdomains') )[9] ) {
                $tailwatch_obj->ensure_global_share(1);    #force recache
            }

            if (   $domain
                && exists $tailwatch_obj->{'global_share'}{'data_cache'}{'domain_user_map'}{$domain}
                && $tailwatch_obj->{'global_share'}{'data_cache'}{'domain_user_map'}{$domain} ) {
                $deliverydomain = $domain;
                $deliveryuser   = $tailwatch_obj->{'global_share'}{'data_cache'}{'domain_user_map'}{$domain};
            }
            else {
                $deliveryuser = '-system-';
            }
        }
    }
    else {
        $deliveryuser   = $delivery_target;
        $deliverydomain = $tailwatch_obj->{'global_share'}{'data_cache'}{'user_domain_map'}{$deliveryuser};

    }
    $deliveryuser   ||= '';
    $deliverydomain ||= '';

    return ( $deliverydomain, $deliveryuser );
}

sub _send_limit_exceeded_notification {
    my $self   = shift;
    my $domain = shift;
    my $type   = shift;

    require Cpanel::Notify::Deferred;
    require Cpanel::AcctUtils::DomainOwner::Tiny;
    require Cpanel::Config::LoadCpConf;
    require Cpanel::Config::LoadCpUserFile;

    my $user = Cpanel::AcctUtils::DomainOwner::Tiny::getdomainowner( $domain, { 'default' => '' } );
    return if !$user;    # If user is blank, then the domain in question is not configured on the system
    my $cpuserconf = Cpanel::Config::LoadCpUserFile::load($user);
    my $cpconf     = Cpanel::Config::LoadCpConf::loadcpconf();
    my $threshold  = $cpconf->{'emailsperdaynotify'};
    my $limit_type;
    my $notification = 'Mail::SendLimitExceeded';
    if ( $type eq 'hourly' ) {
        mkdir( '/var/cpanel/email_send_limits/hourly_notify', 0750 ) if !-e '/var/cpanel/email_send_limits/hourly_notify';
        if ( -e '/var/cpanel/email_send_limits/hourly_notify/' . $domain ) {

            # we have already notified this one in the last hour!
            return;
        }

        # Create the touchfile, so we don't notify again for a bit.
        if ( open( my $hourly_limit_fh, '>', '/var/cpanel/email_send_limits/hourly_notify/' . $domain ) ) {
            close $hourly_limit_fh;
        }

        $threshold  = $cpconf->{'maxemailsperhour'};
        $limit_type = 'global';

        if ( $cpuserconf->{'MAX_EMAIL_PER_HOUR'} && $cpuserconf->{'MAX_EMAIL_PER_HOUR'} ne 'default' ) {
            $threshold  = $cpuserconf->{'MAX_EMAIL_PER_HOUR'};
            $limit_type = 'account';
        }
        if ( $cpuserconf->{ 'MAX_EMAIL_PER_HOUR-' . $domain } && $cpuserconf->{ 'MAX_EMAIL_PER_HOUR-' . $domain } ne 'default' ) {
            $threshold  = $cpuserconf->{ 'MAX_EMAIL_PER_HOUR-' . $domain };
            $limit_type = 'domain';
        }

        $notification = 'Mail::HourlyLimitExceeded';
    }

    Cpanel::Notify::Deferred::notify(
        interval         => 1,
        class            => $notification,
        application      => $notification,
        constructor_args => [
            'domain'     => $domain,
            'user'       => $user,
            'threshold'  => $threshold,
            'limit_type' => $limit_type,
        ]
    );

    return;
}
1;

__END__

=head1 NAME

Cpanel::TailWatch::Eximstats

=head1 SYNOPSIS

N/A, driver for use by Cpanel::TailWatch.

=head1 DESCRIPTION

Eximstats driver used by Cpanel::TailWatch.

=head1 SUBROUTINES

=head2 init

Includes modules required by this driver.

=head2 new

Creates instance of this driver.

=head2 import_sql_file

If C</var/cpanel/eximstats.sql> exists and C<$_UPGRADE_IN_PROGRESS_FILE> doesn't,
create a C<queueprocd> task to import the C<eximstats.sql> file. The task is
defined in C<Cpanel::TaskProcessors::TailwatchTasks>.

=head1 SEE ALSO

L<Cpanel::TaskProcessors::TailwatchTasks>

=head1 LICENSE AND COPYRIGHT

   Copyright 2022 cPanel, L.L.C.
