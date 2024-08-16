package Cpanel::LastLogin::Tiny;

# cpanel - Cpanel/LastLogin/Tiny.pm                Copyright 2022 cPanel, L.L.C.
#                                                           All rights reserved.
# copyright@cpanel.net                                         http://cpanel.net
# This code is subject to the cPanel license. Unauthorized copying is prohibited

use strict;

use Try::Tiny;

use Cpanel::LoadFile::ReadFast ();
use Cpanel::Fcntl::Constants   ();
use Cpanel::FileUtils::Open    ();
use Cpanel::Debug              ();
use Cpanel::PwCache            ();
use Cpanel::Time::Local        ();
use Cpanel::Validate::IP::v4   ();
#
#   DO NOT USE XS HERE OR IT WILL BREAK SOURCE IP CHECK
#
#
our $MAX_HOSTS_TO_STORE    = 15;
our $CURRENT_HOST_POSITION = -1;
our $LAST_HOST_POSITION    = -2;

#Technically this should be called:
#
#   get_previous_login_ip_unless_there_is_not_one_then_return_current_ip_as_to_not_break_securitypolicy()
#
#...but we’re lazy. :)
#
#   For team-users it will record *all* logins, not just if the IP address
#   changed.
sub lastlogin {
    my $currenthost = $ENV{'REMOTE_HOST'} || $ENV{'REMOTE_ADDR'};

    my $homedir = $Cpanel::homedir || Cpanel::PwCache::gethomedir();
    my $ll_file = "$homedir/" . ( $ENV{TEAM_USER} ? "$ENV{TEAM_USER}/" : '' ) . ".lastlogin";

    my $previous_host;

    try {
        Cpanel::FileUtils::Open::sysopen_with_real_perms( my $ll_fh, $ll_file, 'O_RDWR|O_NOFOLLOW|O_CREAT', 0600 ) or do {

            #We don't warn() if we failed to open a file in /var/cpanel.
            if ( $ll_file =~ m{^/var/cpanel/} ) {

                #This newline will be stripped out in the catch {},
                #which leaves an empty string, which signals that logic
                #not to warn().
                die "\n";
            }

            die "open($ll_file) failed: $!\n";
        };

        my %valid_ipv4;
        my @previous_hosts;
        {
            my $data;
            Cpanel::LoadFile::ReadFast::read_all_fast( $ll_fh, $data );
            @previous_hosts =                                                                                                                 #
              grep { $valid_ipv4{ ( split( m{ \#}, $_ ) )[0] } //= Cpanel::Validate::IP::v4::is_valid_ipv4( ( split( m{ \#}, $_ ) )[0] ) }    #
              split( m{\n}, $data );                                                                                                          #
        }

        $previous_host = $previous_hosts[$CURRENT_HOST_POSITION];
        $previous_host &&= _strip_comment($previous_host);

        # Do not write the file if it is not going to change & not a team-user
        my $update_previous_host_timestamp = 0;
        if ( $previous_host && $previous_host eq $currenthost && !$ENV{TEAM_USER} ) {
            $update_previous_host_timestamp = 1;
            $previous_host                  = _strip_comment( $previous_hosts[$LAST_HOST_POSITION] || $previous_host );
        }

        if ( length $currenthost && Cpanel::Validate::IP::v4::is_valid_ipv4($currenthost) ) {

            my $timestamp = Cpanel::Time::Local::localtime2timestamp();

            while ( scalar @previous_hosts >= $MAX_HOSTS_TO_STORE ) {
                shift @previous_hosts;
            }

            seek( $ll_fh, 0, $Cpanel::Fcntl::Constants::SEEK_SET ) or do {
                die "seek() on “$ll_file” failed: $!\n";
            };

            # The most recently stored host is the same as the current
            # host so remove it from the list so it can be re-added
            # with the latest time stamp
            pop @previous_hosts if $update_previous_host_timestamp;

            my $content = join(
                "\n",
                @previous_hosts,
                "$currenthost # $timestamp",
            );

            print {$ll_fh} $content or do {
                die "write to “$ll_file” failed: $!\n";
            };

            truncate( $ll_fh, tell($ll_fh) ) or do {
                die "truncate() on “$ll_file” failed: $!\n";
            };
        }

        close $ll_fh or do {
            die "close() on “$ll_file” failed: $!\n";
        };
    }
    catch {
        my $err = $_;
        chomp $err;

        Cpanel::Debug::log_warn($err) if length $err;
    };

    return $previous_host || $currenthost || q<>;
}

sub _strip_comment {
    return ( split( m{ \#}, $_[0] ) )[0];
}

1;
