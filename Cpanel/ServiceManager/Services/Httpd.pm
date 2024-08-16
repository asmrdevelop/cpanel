package Cpanel::ServiceManager::Services::Httpd;

# cpanel - Cpanel/ServiceManager/Services/Httpd.pm Copyright 2022 cPanel, L.L.C.
#                                                           All rights reserved.
# copyright@cpanel.net                                         http://cpanel.net
# This code is subject to the cPanel license. Unauthorized copying is prohibited

use strict;
use warnings;

use Moo;
use Cpanel::ConfigFiles::Apache 'apache_paths_facade';    # see POD for import specifics
use Cpanel::ServiceManager::Base        ();
use Cpanel::Exception                   ();
use Cpanel::HttpUtils::ApRestart        ();
use Cpanel::HttpUtils::ApRestart::Defer ();
use Cpanel::DIp::Group                  ();

extends 'Cpanel::ServiceManager::Base';

use Cpanel::RestartSrv ();

has '+startup_timeout' => ( is => 'ro', lazy => 1, default => sub { Cpanel::HttpUtils::ApRestart::get_forced_startup_timeout() } );
has '+pidfile'         => ( is => 'ro', lazy => 1, default => sub { Cpanel::HttpUtils::ApRestart::DEFAULT_PID_FILE_LOCATION() } );
has '+pid_exe'         => ( is => 'ro', lazy => 1, default => sub { Cpanel::HttpUtils::ApRestart::get_webserver_process_names_regex() } );
has '+doomed_rules'    => ( is => 'ro', lazy => 1, default => sub { [ Cpanel::HttpUtils::ApRestart::get_webserver_process_names() ] } );
has '+startup_args'    => ( is => 'ro', lazy => 1, default => sub { [qw{ start }] } );
has '+ports'           => ( is => 'ro', lazy => 1, builder => 1 );
has '+service_binary'  => ( is => 'ro', lazy => 1, default => sub { return apache_paths_facade->bin_apachectl(); } );

has '+is_cpanel_service'   => ( is => 'ro', default => 1 );
has '+restart_attempts'    => ( is => 'ro', default => 3 );
has '+block_fresh_install' => ( is => 'ro', default => 1 );

our $APACHE_BUILD_FLAG_FILE = '/var/cpanel/mgmt_queue/apache_update_no_restart';

sub _build_ports {
    my ($self) = @_;

    my $cpconf = $self->cpconf;

    my @ports = map { defined $_->[0] ? int( ( split /:/, $_->[0], 2 )[1] ) : $_->[1] } (
        [ $cpconf->{'apache_port'},     80 ],
        [ $cpconf->{'apache_ssl_port'}, 443 ],
    );

    return \@ports;
}

sub start_check {
    my $self = shift;
    if ( -e $APACHE_BUILD_FLAG_FILE ) {
        print STDERR "An Apache build is currently in progress. The existence of the $APACHE_BUILD_FLAG_FILE file disables manual starts. If you start Apache now, you may cause a broken Apache build.\n";
        return 0;
    }
    return 1;
}

sub start {
    my $self = shift;
    system '/usr/local/cpanel/scripts/ensure_conf_dir_crt_key';
    attempt_apache_php_fpm();
    return $self->SUPER::start(@_);
}

sub restart {
    my $self = shift;
    attempt_apache_php_fpm();
    return $self->SUPER::restart(@_);
}

sub restart_check {
    my $self = shift;

    if ( -e $APACHE_BUILD_FLAG_FILE ) {
        print STDERR "An Apache build is currently in progress. The existence of the $APACHE_BUILD_FLAG_FILE file disables restarts. If you restart Apache now, you may cause a broken Apache build.\n";
        return 0;
    }

    # restartsrv doesn't support options so we have to do an ENV
    # When SKIP_DEFERRAL_CHECK is set we are doing a forced apache
    # restart and we have a lock on httpd.conf already.  In this case
    # we need to ignore the defer check as its a lock on httpd.conf
    # which will result in a deadlock if we check it.
    if ( $ENV{'SKIP_DEFERRAL_CHECK'} ) {
        print STDERR "Executing a forced apache restart.  Deferrals will be ignored.\n";
        return 1;
    }    # a forced restart
    my $try = 0;
  TEST: {
        if ( Cpanel::HttpUtils::ApRestart::Defer::is_deferred() ) {
            if ( $try++ < 10 ) {
                print STDERR "Restarts are currently deferred.  Waiting and then trying again.\n";
                sleep 5;
                redo TEST;
            }
            else {
                print STDERR "Apache could not be restarted because the deferral lasted too long.\n";
                return 0;
            }
        }
    }
    return 1;
}

sub restart_attempt {
    my ( $self, $p_attempt ) = @_;

    # on the third restart attemp, do a last ditch effort by rebuilding the config #
    if ( $p_attempt == 2 ) {
        $self->logger()->info( q{The service '} . $self->service() . q{' failed to restart at least three times. The system will now rebuild the httpd.conf file.} );

        # Cpanel::HttpUtils::ApRestart sets SKIP_DEFERRAL_CHECK since it holds a lock
        # when it called restartsrv_httpd in order to do a forced restart when
        # a graceful restart fails.  This is the only way we know that a lock
        # is being held.
        Cpanel::RestartSrv::logged_startup( $self->service(), 1, [ '/usr/local/cpanel/scripts/rebuildhttpdconf', $ENV{'SKIP_DEFERRAL_CHECK'} ? '--nolock' : () ], 'wait' => 1 );
        return 0 if $?;
    }

    return 1;
}

sub restart_gracefully {
    my $self = shift;
    return unless $self->restart_check();
    attempt_apache_php_fpm();
    return !system( apache_paths_facade->bin_apachectl(), 'graceful' );
}

sub stop_check {
    my $self = shift;
    if ( -e '/var/cpanel/mgmt_queue/apache_update_no_restart' ) {
        my $error = 'An Apache build is currently in progress. The existence of the /var/cpanel/mgmt_queue/apache_update_no_restart file disables manual stops. If you stop Apache now, you may cause a broken Apache build.';
        die Cpanel::Exception::create( 'Services::RestartError', [ 'service' => $self->service(), 'error' => $error ] );
    }
    return 1;
}

sub stop {
    my $self = shift;
    my $ret  = $self->SUPER::stop(@_);
    $self->cleanup() if $ret;
    return $ret;
}

sub cleanup {
    my $self = shift;

    # Clean up
    my @to_clean = (
        apache_paths_facade->dir_run() . '/httpd.scoreboard',
        Cpanel::HttpUtils::ApRestart::DEFAULT_PID_FILE_LOCATION(),
        apache_paths_facade->dir_run() . '/rewrite_lock'
    );

    foreach my $f (@to_clean) {
        next unless -e $f;
        unlink $f or warn "The system was unable to remove a file: $!";
    }

    return 1;
}

sub attempt_apache_php_fpm {

    # ZC-11540: no critic used, this code already existed, I just took it from a private routine to a public
    my $out = `/usr/local/cpanel/scripts/restartsrv_apache_php_fpm --graceful 2>&1`;    ## no critic qw(Cpanel::ProhibitQxAndBackticks)
    warn "$out\nrestartsrv_apache_php_fpm --graceful exited unclean\n" if $?;
    return $? ? 0 : 1;
}

sub kill_apps_on_ports {
    my $self = shift;

    # CPANEL-38011: Don't kill IPs listed in /etc/reservedips, since apache
    # doesn't listen on those IPs and other services may be configured to
    # listen on that port.

    return $self->SUPER::kill_apps_on_ports( 'exclude_ips' => [ Cpanel::DIp::Group::getreservedipslist() ] );
}

1;
