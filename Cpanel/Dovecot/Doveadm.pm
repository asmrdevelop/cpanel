package Cpanel::Dovecot::Doveadm;

# cpanel - Cpanel/Dovecot/Doveadm.pm               Copyright 2022 cPanel, L.L.C.
#                                                           All rights reserved.
# copyright@cpanel.net                                         http://cpanel.net
# This code is subject to the cPanel license. Unauthorized copying is prohibited

use cPstrict;

use Cpanel::Autodie             ();
use Cpanel::Context             ();
use Cpanel::Exception           ();
use Cpanel::FHUtils::Autoflush  ();
use Cpanel::Socket::UNIX::Micro ();
use Cpanel::Socket::Constants   ();

#override in a subclass to test
use constant {
    SOCK_PATH => '/var/run/dovecot/doveadm-server',
    LF        => "\x0a",

    _DEBUG => 0,
};

=encoding utf-8

=head1 NAME

Cpanel::Dovecot::Doveadm

=head1 DESCRIPTION

This module implements a client for the Doveadm protocol described at
L<http://wiki2.dovecot.org/Design/DoveadmProtocol>.

=head1 RETURN FORMAT

Doveadm’s protocol doesn’t actually divide its responses into records;
the caller is expected to do that manually. :-(

=head1 ERROR RESPONSE

Errors result in a thrown C<Cpanel::Exception> subclass instance:

=over

=item * C<Doveadm::UnrecognizedResponse> - When the response doesn’t
match the protocol as documented. This can happen for certain queries,
e.g., (C<mailbox status>, C<messages vsizeee>, C<INBOX>).

=item * C<Doveadm::Error> - When Doveadm indicates an error as documented.

=back

=cut

=head2 new( )

Instantiate a Cpanel::Dovecot::Doveadm instance.

=head3 Arguments

None.

=head3 Returns

An instance of Cpanel::Dovecot::Doveadm.

=head3 Exceptions

An exception may be thrown if the handshake w/ doveadm fails.

=cut

sub new {
    my ($class) = @_;

    my $self = bless [], $class;

    $self->_setup_connection();
    return $self;
}

sub _connect_to_dovecot {
    my ($class) = @_;
    my $socket;

    Cpanel::Autodie::socket( $socket, $Cpanel::Socket::Constants::AF_UNIX, $Cpanel::Socket::Constants::SOCK_STREAM, 0 );

    my $socket_path = $class->SOCK_PATH();
    my $usock       = Cpanel::Socket::UNIX::Micro::micro_sockaddr_un($socket_path);
    Cpanel::Autodie::connect( $socket, $usock );

    Cpanel::FHUtils::Autoflush::enable($socket);

    return $socket;
}

sub _setup_connection {
    my ($self) = @_;

    $self->[0] = $self->_connect_to_dovecot();

    #Might as well do this here …
    return $self->_handshake_local();
}

=head2 do( SCALAR, SCALAR .. )

Send a command to the doveadm server to perform a command.

=head3 Arguments

See http://wiki2.dovecot.org/Design/DoveadmProtocol

=head3 Returns

If the function is successful a list of scalars will be returned representing the return of the
command sent to the doveadm server.

=head3 Exceptions

If the command fails or the server sends back an unrecognized response, an exception will be thrown.

=cut

sub do {
    my $self = shift;
    return $self->_do_cmd( q<>, @_ );
}

=head2 do_verbose( SCALAR, SCALAR .. )

Send a command to the doveadm server to perform a command with the verbose flag set.

=head3 Arguments

See http://wiki2.dovecot.org/Design/DoveadmProtocol

=head3 Returns

If the function is successful a list of scalars will be returned representing the return of the
command sent to the doveadm server.

=head3 Exceptions

If the command fails or the server sends back an unrecognized response, an exception will be thrown.

=cut

sub do_verbose {
    my $self = shift;
    return $self->_do_cmd( 'v', @_ );
}

=head2 do_debug( SCALAR, SCALAR .. )

Send a command to the doveadm server to perform a command with the debug flag set.

=head3 Arguments

See http://wiki2.dovecot.org/Design/DoveadmProtocol

=head3 Returns

If the function is successful a list of scalars will be returned representing the return of the
command sent to the doveadm server.

=head3 Exceptions

If the command fails or the server sends back an unrecognized response, an exception will be thrown.

=cut

sub do_debug {
    my $self = shift;
    return $self->_do_cmd( 'D', @_ );
}

#----------------------------------------------------------------------

sub _do_cmd {
    my ( $self, $flags, @cmd ) = @_;

    Cpanel::Context::must_be_list();

    # Dovecot may disconnect if we IDLE for too long
    # in that case we need to reconnect
    local $SIG{'PIPE'} = sub { die 'doveadm: SIGPIPE'; };
    local $@;
    for ( 1 .. 2 ) {
        my ( $response, $status );
        eval {
            $self->_send_command( $flags, @cmd );

            local $!;

            $response = $self->_readline();
            $status   = $self->_readline();
        };

        if ($@) {
            if ( index( $@, 'SIGPIPE' ) > -1 ) {
                $self->_setup_connection();
                next;
            }
            die;
        }

        print STDERR "doveadm-response: $response" if _DEBUG;
        print STDERR "doveadm-status  : $status"   if _DEBUG;

        #Success
        if ( 0 == index( $status, '+' ) ) {
            chomp $response;
            return split m<\t>, $response;
        }
        elsif ( 0 == index( $status, '-' ) ) {

            chomp( $response, $status );

            # doveadm has, in previous versions, change their protocol somewhat.
            # If you see issues with mailbox conversion hanging, check HB-6346
            # for details

            # A lone - just means there was no actual error returned
            if ( $status ne '-' ) {
                die Cpanel::Exception::create(
                    'Doveadm::Error',
                    [
                        message => $response,
                        status  => substr( $status, 1 ),
                        command => [ $flags, @cmd ],
                    ]
                );
            }
            if ( grep /rescan/, @cmd ) {
                die Cpanel::Exception::create(
                    'Doveadm::Error',
                    [
                        message => $response,
                        status  => substr( $status, 1 ),
                        command => [ $flags, @cmd ],
                    ]
                );
            }
        }

        # Response can be empty, so nothing to report
        if ( !$response ) {
            return;
        }

        die Cpanel::Exception::create(
            'Doveadm::Error',
            [
                message => $response,
                status  => substr( $status, 1 ),
                command => [ $flags, @cmd ],
            ]
        );
    }

    die "doveadm: never reached";
}

sub _handshake_local {
    my ($self) = @_;

    local $!;

    # dovecot >= 2.3.0 requires that the
    # client must send the VERSION first.
    $self->_send_command(qw( VERSION doveadm-server 1 0 ));

    my $read = $self->_readline();

    if ( $read ne '+' . LF ) {
        die "Unrecognized server handshake!";
    }

    return 1;
}

sub _send_command {
    my ( $self, @cmd ) = @_;

    if ( grep { tr/\t\r\n\000\001// } @cmd ) {
        die "doveadm: commands may not contain literal tabs, returns, newlines, null, or start of heading characters: “@cmd”";
    }

    print STDERR "doveadm-request : [" . join( '][', @cmd ) . "]\n" if _DEBUG;

    return $self->_send( join "\t", @cmd );
}

sub _send {
    my ( $self, $str ) = @_;

    print { $self->[0] } $str, LF or die "doveadm write($str): $!";

    return;
}

my $line;

sub _readline {
    my ($self) = @_;

    $line = readline $self->[0];
    die "doveadm read: $!" if $!;

    return $line;
}

1;
