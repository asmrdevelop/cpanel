package Cpanel::Server::Connection;

# cpanel - Cpanel/Server/Connection.pm             Copyright 2022 cPanel, L.L.C.
#                                                           All rights reserved.
# copyright@cpanel.net                                         http://cpanel.net
# This code is subject to the cPanel license. Unauthorized copying is prohibited

use strict;
use warnings;

use Socket                    ();
use Cpanel::Exception         ();
use Cpanel::Hulk::Constants   ();
use Cpanel::WebService        ();
use Cpanel::IP::Collapse      ();
use Cpanel::LoadModule        ();
use Cpanel::Socket::Constants ();
use Cpanel::TCP::Close        ();

use Class::XSAccessor (
    getters => {
        get_request_count     => '_request_count',
        get_is_last_request   => '_is_last_request',
        get_keepalive_timeout => '_keepalive_timeout',
        get_socket            => '_socket',
        get_sockname          => '_sockname',
        logger                => '_logger',
    },
    setters => {
        set_is_last_request   => '_is_last_request',
        set_keepalive_timeout => '_keepalive_timeout',
        set_socket            => '_socket',
        set_sockname          => '_sockname',
    },
);

use parent 'Cpanel::Server::LogAccess';

our $TCP_CORK = 3;
use constant IPPROTO_TCP   => Socket::IPPROTO_TCP();
use constant is_ssl_socket => 0;

our $DEFAULT_KEEP_ALIVE_TIMEOUT = 60;

=encoding utf-8

=head1 METHODS

=cut

########################################################
#
# Method:
#   new
#
# Description:
#   Creates a connection object for a Cpanel::Server
#   object
#
# Parameters:
#   CPCONF       - A loadcpconf hashref
#   (required)
#
#   DEBUG        - Debug mode on or off
#   (required)
#
#   logs         - A Cpanel::Server::Logs object
#   (required)
#
#   socket       - The socket the server is connected to
#   (required)
#
#   logger       - A Cpanel::Server::Logger object
#   (required)
#
#
# Returns:
#   A Cpanel::Server::Connection object
#
sub new {
    my ( $class, %OPTS ) = @_;
    return bless {
        '_log-http-requests' => $OPTS{'CPCONF'}{'log-http-requests'} ? 1 : 0,
        '_DEBUG'             => $OPTS{'DEBUG'} || 0,
        '_logs'              => ( $OPTS{'logs'}   || die Cpanel::Exception::create( 'MissingParameter', [ 'name' => 'logs' ] ) ),      # Cpanel::Server::Logs object
        '_logger'            => ( $OPTS{'logger'} || die Cpanel::Exception::create( 'MissingParameter', [ 'name' => 'logger' ] ) ),    # Cpanel::Server::Logger object
        '_socket'            => ( $OPTS{'socket'} || die Cpanel::Exception::create( 'MissingParameter', [ 'name' => 'socket' ] ) ),
        '_request_count'     => 0,
        '_keepalive_timeout' => $DEFAULT_KEEP_ALIVE_TIMEOUT,
    }, $class;
}

sub increment_request_count {
    return ++$_[0]->{'_request_count'};
}

sub set_SIGPIPE {
    return ( $_[0]->{'_hassigPIPE'} = 1 );
}

=head2 I<OBJ>->forgo_sigpipe_logging()

This tells the connection object not to log when the connection ends
via SIGPIPE. This is useful, e.g., with SSE, where the browser
shuts the connection down by closing the socket, which will eventually
prompt a SIGPIPE/EPIPE when the server tries to write to a client that’s
not there anymore.

=cut

sub forgo_sigpipe_logging {
    my ($self) = @_;
    $self->{'_forgo_sigpipe_logging'} = 1;
    return $self;
}

sub write_buffer {    ## no critic qw(Subroutines::RequireArgUnpacking)

    #    my ( $self, $buffer ) = @_;

    # For debug
    # use Data::Dumper;
    # print STDERR Carp::longmess("[write_buffer][" . Dumper($buffer) . "]") . "\n";

    my $bytes_written = 0;
    my $ref_buffer    = ref $_[1] ? $_[1] : \$_[1];
    my $total_length  = length $$ref_buffer;
    my $bytes_written_this_loop;
    while ( $bytes_written_this_loop = syswrite( $_[0]->{'_socket'}, $$ref_buffer, ( $total_length - $bytes_written ), $bytes_written ) ) {
        $bytes_written += $bytes_written_this_loop;
        last if ( $total_length - $bytes_written ) == 0;
    }
    $_[0]->check_pipehandler_globals();

    return $bytes_written;
}

sub check_pipehandler_globals {
    if ( $_[0]->{'_hassigPIPE'} || $! == $Cpanel::Hulk::Constants::EPIPE || $! == $Cpanel::Hulk::Constants::ECONNRESET ) {
        return $_[0]->pipehandler();
    }
    return 0;
}

sub pipehandler {
    my ($self) = @_;

    if ( !$self->{'_forgo_sigpipe_logging'} ) {
        if ( !$self->logger()->access_log_is_stdout() ) {
            $self->logger()->logaccess();
        }

        if ( $self->{'_log-http-requests'} ) {
            $self->get_log('request')->info( "pipehandler() called " . $self->get_request_count() . "." );
        }
    }

    $self->postsend_object();
    $self->killconnection('pipe handler');

    if ( ${ $self->{'_DEBUG'} } ) {
        Cpanel::LoadModule::load_perl_module('Cpanel::Carp');
        syswrite( STDERR, "$0 [$$]: " . Cpanel::Carp::safe_longmess('SIGPIPE received') );
        kill( 'KILL', $$ );                   #try to force outselves out of memory
        CORE::die('Received PIPE signal');    #must use die see dbd-oracle-timeout.pod
    }
    else {
        kill( 'KILL', $$ );                   #try to force outselves out of memory
        CORE::die('Received PIPE signal');    #must use die see dbd-oracle-timeout.pod
    }

    return;
}

sub presend_object {
    my ( $self, $fh_to_set ) = @_;

    $fh_to_set ||= $self->{'_socket'};

    if ( !$fh_to_set ) {
        Cpanel::LoadModule::load_perl_module('Cpanel::Carp');
        die Cpanel::Carp::safe_longmess("'_socket' is required to presend_object");
    }
    my $fno = fileno($fh_to_set);
    return unless defined $fno && $fno >= 0;

    return setsockopt( $fh_to_set, IPPROTO_TCP, $TCP_CORK, 1 );
}

sub postsend_object {
    my ( $self, $fh_to_set ) = @_;

    $fh_to_set ||= $self->{'_socket'};

    if ( !$fh_to_set ) {
        Cpanel::LoadModule::load_perl_module('Cpanel::Carp');
        die Cpanel::Carp::safe_longmess("'_socket' is required to postsend_object");
    }

    my $fno = fileno($fh_to_set);
    return unless defined $fno && $fno >= 0;

    return setsockopt( $fh_to_set, IPPROTO_TCP, $TCP_CORK, 0 );
}

#Use this to signal to the TCP peer that this side is done sending data.
sub shutdown_connection_write {
    my ($self) = @_;

    die "Socket is already gone!" if !$self->{'_socket'};

    # NB: There’s little point in warn()ing here; the only likely
    # error is ENOTCONN, which can happen in normal operation if
    # the client already closed the connection.
    $self->{'_socket'}->shutdown( Socket::SHUT_WR() );

    return;
}

sub shutdown_connection {
    my ($self) = @_;
    if ( $self->{'_socket'} ) {

        # We used to make sure we flush out the socket.. this is very important as ajax stuff may fail otherwise
        # Probably do not need to flush as all sockets w IO::Socket > 1.18
        # have autoflush turned on
        #
        #$self->{'_socket'}->flush();

        # First let the client know that we’re done writing.
        $self->shutdown_connection_write();

        Cpanel::TCP::Close::close_avoid_rst( $self->{'_socket'} );

        delete $self->{'_socket'};
        return 1;
    }

    return 0;
}

# needs test
sub killconnection {
    my ( $self, $msg, $exit_code ) = @_;

    if ( $self->{'_log-http-requests'} ) {
        $self->get_log('request')->info( "[killconnection " . $self->get_request_count() . "] [$msg]" );
    }
    $self->shutdown_connection();
    if ( $self->{'_log-http-requests'} ) {
        $self->get_log('request')->info( "[killconnection exit " . $self->get_request_count() . "]" );
    }

    exit( $exit_code ? $exit_code : 0 );
}

sub setup_hostinfo_env {
    my ($self) = @_;

    my $socket   = $self->get_socket();
    my $peername = $socket->peername();
    my $sockname = $self->get_sockname() || $socket->sockname();

    my $sock_type = unpack( 'S', $peername || $sockname );

    if ( $sock_type == $Cpanel::Socket::Constants::AF_INET6 ) {
        my $ip;
        ( $ENV{'REMOTE_PORT'}, $ip ) = ( unpack( 'SnNH32', $peername ) )[ 1, 3 ];                                                    ## no critic qw(Variables::RequireLocalizedPunctuationVars)
        $ENV{'REMOTE_ADDR'} = Cpanel::IP::Collapse::collapse( join( '.', join( ":", unpack( "H4" x 8, pack( "H32", $ip ) ) ) ) );    ## no critic qw(Variables::RequireLocalizedPunctuationVars)
        ( $ENV{'SERVER_PORT'}, $ip ) = ( unpack( 'SnNH32', $sockname ) )[ 1, 3 ];                                                    ## no critic qw(Variables::RequireLocalizedPunctuationVars)
        $ENV{'SERVER_ADDR'} = Cpanel::IP::Collapse::collapse( join( '.', join( ":", unpack( "H4" x 8, pack( "H32", $ip ) ) ) ) );    ## no critic qw(Variables::RequireLocalizedPunctuationVars)
    }

    else {
        @ENV{ 'REMOTE_ADDR', 'REMOTE_PORT', 'SERVER_ADDR', 'SERVER_PORT' } = (
            ( $peername ? Socket::inet_ntoa( ( Socket::unpack_sockaddr_in($peername) )[1] ) : undef ),
            ( $peername ? ( Socket::unpack_sockaddr_in($peername) )[0]                      : undef ),
            ( $sockname ? Socket::inet_ntoa( ( Socket::unpack_sockaddr_in($sockname) )[1] ) : undef ),
            ( $sockname ? ( Socket::unpack_sockaddr_in($sockname) )[0]                      : undef )
        );
    }

    my $name;
    if ( $self->{'CPCONF'}{'dnslookuponconnect'} && !Cpanel::WebService::remote_host_is_localhost() ) {
        eval {
            local $SIG{'ALRM'} = sub {
                die 'Dns lookup failure';
            };
            alarm(1);
            $name = ( gethostbyname( $ENV{'REMOTE_ADDR'} ) )[0];
            alarm(0);
        };
    }
    if ( !$name || $name eq 'tcp' ) {
        $ENV{'REMOTE_HOST'} = $ENV{'REMOTE_ADDR'};
    }
    else {
        $ENV{'REMOTE_HOST'} = $name;
    }
    return 1;
}

1;
