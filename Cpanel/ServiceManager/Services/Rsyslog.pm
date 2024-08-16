package Cpanel::ServiceManager::Services::Rsyslog;

# cpanel - Cpanel/ServiceManager/Services/Rsyslog.pm
#                                                  Copyright 2022 cPanel, L.L.C.
#                                                           All rights reserved.
# copyright@cpanel.net                                         http://cpanel.net
# This code is subject to the cPanel license. Unauthorized copying is prohibited

use strict;
use warnings;

use Moo;
use Cpanel::ServiceManager       ();
use Cpanel::ServiceManager::Base ();
use Cpanel::OS                   ();

extends 'Cpanel::ServiceManager::Base';

has '+service_package' => ( is => 'ro', default => 'rsyslog' );
has '+pidfile'         => ( is => 'ro', default => sub { !Cpanel::OS::is_systemd() ? '/var/run/syslogd.pid' : undef } );
has '+service_binary'  => ( is => 'ro', default => '/sbin/rsyslogd' );

has '+is_enabled' => ( is => 'ro', lazy => 1, default => sub { -x '/sbin/rsyslogd' } );

# For most services, we allow the user to stop the service, but not restart it,
# if the service is disabled.  However, since other syslog daemons use the same
# PID file, if someone was not using rsyslog, they'd end up stopping the syslog
# daemon and not restarting it.  This prevents them from doing so.
sub stop_check {
    my ($self) = @_;
    my %exception_parameters = ( 'service' => $self->service() );

    # when the service is disabled, we just don't do anything #
    $self->_generate_disabled_exception( \%exception_parameters )
      if !$self->is_enabled();

    return;
}

after stop => sub {
    my ( $self, $service, $type ) = @_;

    # Debian-based systems require shutting down syslog.socket. Currently only
    # Ubuntu needs this, though that may change in the future.
    return unless Cpanel::OS::rsyslog_triggered_by_socket();

    my $syslog = Cpanel::ServiceManager->new( 'service' => 'syslog' );
    $syslog->service_manager()->stop( $self, 'socket' );

    return;
};

1;
