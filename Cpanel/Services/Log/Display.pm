package Cpanel::Services::Log::Display;

# cpanel - Cpanel/Services/Log/Display.pm          Copyright 2022 cPanel, L.L.C.
#                                                           All rights reserved.
# copyright@cpanel.net                                         http://cpanel.net
# This code is subject to the cPanel license. Unauthorized copying is prohibited

use strict;
use warnings;

use Cpanel::Services::Log ();
use Cpanel::Exception     ();

###########################################################################
#
# Method:
#   new
#
# Description:
#   This module is used to display a service's
#   startup log as well as any recent log messages.
#
# Parameters:
#   output_obj   - A Cpanel::Output object
#   service      - The service to display the logs file.
#   service_via_systemd - The return from Cpanel::RestartSrv::Systemd::has_service_via_systemd for the service
#
# Returns:
#   A Cpanel::Services::Log::Display object
#
sub new {
    my ( $class, %OPTS ) = @_;

    foreach my $param (qw(output_obj service)) {
        die Cpanel::Exception::create( 'MissingParameter', [ 'name' => $param ] ) if !defined $OPTS{$param};
    }

    my $self = {%OPTS};

    return bless $self, $class;
}

###########################################################################
#
# Method:
#   show_startup_log
#
# Description:
#   Output the startup log and recent log messages to
#   the output object.
#
# Parameters:
#   None
#
# Returns:
#   1
#

sub show_startup_log {
    my ($self) = @_;

    my ( $startup_log_ok, $startup_log ) = Cpanel::Services::Log::fetch_service_startup_log( $self->{'service'}, $self->{'service_via_systemd'} );
    if ( $startup_log_ok && $startup_log ) {
        $self->{'output_obj'}->display_message_set( "Startup Log", $startup_log );
    }

    my ( $log_messages_ok, $log_messages ) = Cpanel::Services::Log::fetch_service_log_messages( $self->{'service'}, $self->{'service'} );
    if ( $log_messages_ok && $log_messages ) {
        $self->{'output_obj'}->display_message_set( "Log Messages", $log_messages );
    }

    return 1;
}

1;
