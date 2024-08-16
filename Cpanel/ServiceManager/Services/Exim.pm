package Cpanel::ServiceManager::Services::Exim;

# cpanel - Cpanel/ServiceManager/Services/Exim.pm  Copyright 2022 cPanel, L.L.C.
#                                                           All rights reserved.
# copyright@cpanel.net                                         http://cpanel.net
# This code is subject to the cPanel license. Unauthorized copying is prohibited

use strict;

use Moo;
extends 'Cpanel::ServiceManager::Base';

use Cpanel::FileUtils::TouchFile ();
use Cpanel::Exim                 ();
use Cpanel::RestartSrv           ();
use Cpanel::RestartSrv::Systemd  ();

# TODO: does 587 need to be included here as well as configured ports?
has '+processowner'     => ( is => 'ro', default => 'mailnull' );
has '+service_package'  => ( is => 'ro', default => 'exim' );
has '+restart_attempts' => ( is => 'ro', default => 5 );
has '+support_reload'   => ( is => 'ro', default => 1 );

# when using outgoing process... we want to check two pids for the same service...
has '+has_single_pid' => ( is => 'ro', default => sub { shift->use_exim_outgoing_process ? 0 : 1 } );

has '+doomed_rules'             => ( is => 'ro', lazy => 1, default => sub { [qw{ exim }] } );
has '+ports'                    => ( is => 'ro', lazy => 1, default => sub { [qw{ 25 465 }] } );
has 'use_exim_outgoing_process' => ( is => 'ro', lazy => 1, default => sub { -e q{/etc/exim_outgoing.conf} ? 1                         : 0 } );
has '+service_binary'           => ( is => 'ro', lazy => 1, default => sub { -x Cpanel::Exim::find_exim()  ? Cpanel::Exim::find_exim() : undef } );
has '+pidfile' => (
    is      => 'ro',
    lazy    => 1,
    default => sub { Cpanel::RestartSrv::Systemd::has_service_via_systemd('exim') ? '/var/spool/exim/exim-daemon.pid' : undef }
);

# case 148421: We have to look at the process table as looking for this pid
#              file will break mail scanner.
# exim can run up to 2 processes: /var/spool/exim/exim-daemon.pid and /var/spool/exim/exim-outgoing.pid
#   the second pid file was introduced in 11.50
#   we should consider to use them

sub start {
    my $self = shift;

    if ( !Cpanel::RestartSrv::Systemd::has_service_via_systemd('exim') ) {

        # force to doom processes that might exist that we (--status) cannot view
        eval { $self->service_manager->stop($self) };
    }

    Cpanel::FileUtils::TouchFile::touchfile('/etc/recent_authed_mail_ips');
    chmod 0644, '/etc/recent_authed_mail_ips';
    Cpanel::RestartSrv::logged_startup( $self->service(), 0, ['/usr/local/cpanel/scripts/checkexim.pl'], 'wait' => 1 );
    return 0 if $?;
    return $self->SUPER::start(@_);
}

sub get_status_string {
    my $self = shift;

    my $status = $self->SUPER::get_status_string(@_);

    # also need to check for the second exim outgoing process
    if ( $self->use_exim_outgoing_process() ) {

        # on centos 5/6 we need to make an extra call to check_service because it won't find the other exim process #
        if ( !Cpanel::RestartSrv::Systemd::has_service_via_systemd('exim') ) {

            # need to call both as we do not use the PID file
            #   and we have no guarantee in which order the parent function
            #   will view the processes
            # do not trust the status string, and build our own ( to avoid on extra loop )
            $status = Cpanel::RestartSrv::check_service( service => $self->service, pidfile => q{/var/spool/exim/exim-daemon.pid} )    || '';
            $status .= Cpanel::RestartSrv::check_service( service => $self->service, pidfile => q{/var/spool/exim/exim-outgoing.pid} ) || '';

        }

        $status //= '';

        # if exim is being used with the outgoing queue, we need both the incoming and outgoing to be present in the status text #
        # if not viewing exim-daemon or not outgoing.pid then go pid
        # wait so we can view the two PIDs... could loop for a while..
        if ( $status !~ m/exim-daemon\.pid/ || $status !~ m/outgoing\.pid/ ) {
            return '';
        }
    }

    return $status;
}

sub restart_attempt {
    my ( $self, $p_attempt ) = @_;

    if ( 3 == $p_attempt ) {

        #if we are using dovecot auth the socket may be stuck
        Cpanel::RestartSrv::logged_startup( $self->service(), 0, ['/usr/local/cpanel/scripts/restartsrv_dovecot'], 'wait' => 1 );
        return 0 if $?;
    }

    if ( 4 == $p_attempt ) {

        #if the mail server type was changed and the system didn't rebuild the config we will try that now
        Cpanel::RestartSrv::logged_startup( $self->service(), 0, ['/usr/local/cpanel/scripts/buildeximconf'], 'wait' => 1 );
        return 0 if $?;
    }

    return 1;
}

1;
