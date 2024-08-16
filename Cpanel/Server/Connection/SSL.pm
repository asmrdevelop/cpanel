package Cpanel::Server::Connection::SSL;

# cpanel - Cpanel/Server/Connection/SSL.pm         Copyright 2022 cPanel, L.L.C.
#                                                           All rights reserved.
# copyright@cpanel.net                                         http://cpanel.net
# This code is subject to the cPanel license. Unauthorized copying is prohibited

use strict;
use warnings;
use Cpanel::CPAN::Net::SSLeay::Fast ();

use parent 'Cpanel::Server::Connection';

use constant is_ssl_socket => 1;

use Class::XSAccessor (
    getters => {
        'Net_SSLeay_obj' => '_Net_SSLeay_obj',
    }
);

sub new {
    my ( $class, %OPTS ) = @_;

    my $self = bless $class->SUPER::new(%OPTS), $class;

    $self->{'_Net_SSLeay_obj'} = $self->{'_socket'}->_get_ssl_object();

    return $self;
}

sub set_socket {
    my ( $self, $socket ) = @_;
    $self->{'_Net_SSLeay_obj'} = $socket->_get_ssl_object();
    $self->{'_socket'}         = $socket;
    return;
}

sub write_buffer {
    my ( $self, $buffer ) = @_;

    # For debug
    # use Data::Dumper;
    # print STDERR Carp::longmess("[write_buffer][" . Dumper($buffer) . "]") . "\n";

    my $bytes_written = Cpanel::CPAN::Net::SSLeay::Fast::ssl_write_all( $self->{'_Net_SSLeay_obj'}, $buffer );

    # CPANEL-32529: $bytes_written can be undef, meaning that some kind of error happened.
    if ( !defined $bytes_written ) {
        my $errno = $!;

        require Net::SSLeay;

        my $ssl_obj    = $self->{'_Net_SSLeay_obj'};
        my $error_code = Net::SSLeay::get_error( $ssl_obj, -1 );    # -1 is what Net::SSLeay::partial_write() must have returned if $bytes_written is undef

        if ( $error_code == Net::SSLeay::constant('ERROR_SYSCALL') && !$errno ) {
            require Cpanel::Hulk::Constants;
            $! = $Cpanel::Hulk::Constants::ECONNRESET;              ## no critic(Variables::RequireLocalizedPunctuationVars)
                                                                    # signals to check_pipehandler_globals() to tear things down quietly
        }
        else {                                                      # no idea what happened, but it's not good, so bail out noisily
            require Cpanel::Exception;
            die Cpanel::Exception::create( 'NetSSLeay', [ function => 'ssl_write_all', arguments => [$buffer], error_codes => [$error_code], errno => $errno ] );
        }
    }

    $self->check_pipehandler_globals();
    return $bytes_written;
}

sub shutdown_connection {
    my ($self) = @_;

    if ( $self->{'_socket'} ) {

        # A manual SSL shutdown allows the parent class to avoid
        # trouble from RST packets, e.g., if the socket still has
        # data to read when the connection is closed.
        #
        $self->{'_socket'}->stop_SSL(
            SSL_fast_shutdown => 1,
        );
    }

    return $self->SUPER::shutdown_connection();
}

1;
