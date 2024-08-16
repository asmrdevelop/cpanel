package Cpanel::Net::Base;

# cpanel - Cpanel/Net/Base.pm                      Copyright 2022 cPanel, L.L.C.
#                                                           All rights reserved.
# copyright@cpanel.net                                         http://cpanel.net
# This code is subject to the cPanel license. Unauthorized copying is prohibited

#----------------------------------------------------------------------
# This is a base class. Do not instantiate directly.
#----------------------------------------------------------------------

use strict;
use warnings;

use IO::SigGuard qw( send );

use Cpanel::Autodie             ();
use Cpanel::Autodie             ();
use Cpanel::Autodie             ();
use Cpanel::Exception           ();
use Cpanel::Socket::UNIX::Micro ();
use Cpanel::Socket::Timeout     ();
use Cpanel::Hulk::Constants     ();

our $TIMEOUT         = 10;
our $CONNECT_TIMEOUT = 5;

sub new {
    my ( $class, %OPTS ) = @_;

    die Cpanel::Exception::create( 'MissingParameter', [ 'name' => 'socket_path' ] ) if !length $OPTS{'socket_path'};

    my $self = { 'socket_path' => $OPTS{'socket_path'} };

    return bless $self, $class;
}

###########################################################################
#
# Method:
#    connect_to_unix_socket
#
# Description:
#    This function connects to the socket that was given as
#    'socket_path' when creating the object or die with an
#    an execption.
#
# Arguments:
#   None
#
# Returns:
#   1 - Successful connection to the unix socket
#
sub connect_to_unix_socket {
    my ($self) = @_;

    if ( !$self->{'socket_path'} ) {
        die "Implementer error: “socket_path” must be defined in the object before calling “connect_to_unix_socket”.";
    }

    if ( $self->{'socket'} ) {
        die "$self: socket is already created!";
    }

    Cpanel::Autodie::socket( $self->{'socket'}, $Cpanel::Hulk::Constants::AF_UNIX, $Cpanel::Hulk::Constants::SOCK_STREAM, 0 );

    my $usock = Cpanel::Socket::UNIX::Micro::micro_sockaddr_un( $self->{'socket_path'} );

    my $connect_timeout = Cpanel::Socket::Timeout::create_write( $self->{'socket'}, $CONNECT_TIMEOUT );

    Cpanel::Autodie::connect( $self->{'socket'}, $usock );

    return 1;
}

###########################################################################
#
# Method:
#    read_response
#
# Description:
#    This function reads a single response from the socket
#    that the object is connected to or will die with
#    an exception. This includes a 10-second timeout.
#
# Arguments:
#   $size  -  The length of the data to attempt to read.
#
# Returns:
#   The raw data read from the socket.
#

sub read_response {
    my ( $self, $size ) = @_;

    if ( !$self->{'socket'} ) {
        die "Implementer error: “socket” must be defined in the object before calling “read_response”.";
    }
    if ( !$size ) {
        die "“read_response” requires a “size”.";
    }

    $self->{'_read_timeout'} ||= Cpanel::Socket::Timeout::create_read( $self->{'socket'}, $TIMEOUT );

    my $buffer;

    Cpanel::Autodie::sysread_sigguard( $self->{'socket'}, $buffer, $size );

    return $buffer;
}

###########################################################################
#
# Method:
#    write_message
#
# Description:
#    This function writes data to the socket
#    that the object is connected to or will die with
#    an exception. This call has a 10-second timeout.
#
# Arguments:
#   $message    - The message to write to the socket
#
# Returns:
#   The number of bytes written to the socket
#
sub write_message {
    my ( $self, $message ) = @_;

    if ( !$self->{'socket'} ) {
        die "Implementer error: “socket” must be defined in the object before calling “write_message”.";
    }

    $self->{'_write_timeout'} ||= Cpanel::Socket::Timeout::create_write( $self->{'socket'}, $TIMEOUT );

    local $!;
    return IO::SigGuard::send( $self->{'socket'}, $message, $Cpanel::Socket::Constants::MSG_NOSIGNAL ) // do {
        die Cpanel::Exception::create( 'IO::WriteError', [ error => $!, length => length($message) ] );
    };
}

###########################################################################
#
# Method:
#    close_socket
#
# Description:
#    This function closes the socket
#
# Arguments:
#   None
#
# Returns:
#   True if the socket has been closed or
#    generates an exception.
#
sub close_socket {
    my ($self) = @_;

    if ( !$self->{'socket'} ) {
        die "Implementer error: “socket” must be defined in the object before calling “close_socket”.";
    }

    return Cpanel::Autodie::close( $self->{'socket'} );
}

###########################################################################
#
# Method:
#    get_socket_path
#
# Description:
#    Returns the path to the unix socket
#
# Arguments:
#   None
#
# Returns:
#   The path to the unix socket
#
sub get_socket_path {
    my ($self) = @_;

    return $self->{'socket_path'};
}

#for tests only
sub _get_socket {
    my ($self) = @_;

    return $self->{'socket'};
}

1;
