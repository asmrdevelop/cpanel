package Cpanel::Server::Handlers::WebSocket;

# cpanel - Cpanel/Server/Handlers/WebSocket.pm     Copyright 2022 cPanel, L.L.C.
#                                                           All rights reserved.
# copyright@cpanel.net                                         http://cpanel.net
# This code is subject to the cPanel license. Unauthorized copying is prohibited

use strict;
use warnings;

=encoding utf-8

=head1 NAME

Cpanel::Server::Handlers::WebSocket - WebSocket handler for cpsrvd

=head1 SYNOPSIS

    #This is how this class is normally instantiated.
    my $handler_obj = $server_obj->get_handler('WebSocket');

    $handler_obj->handler($ws_module);

=head1 DESCRIPTION

This module interfaces with cpsrvd to call WebSocket modules as requests
dictate. It subclasses L<Cpanel::Server::Handler>.

=cut

use parent 'Cpanel::Server::Handler';

use Try::Tiny;

#Stub out Module::Load::load() since CPAN modules use it
#and we likely already have our own loader logic already in memory.
use Cpanel::Module::Load ();    # PPI USE OK - stub out Module::Load

use Net::WebSocket::Handshake::Server     ();
use Net::WebSocket::PMCE::deflate::Server ();
use Net::WebSocket::Parser                ();

use Cpanel::Autodie                    ();
use Cpanel::Exception                  ();
use Cpanel::FHUtils::Autoflush         ();
use Cpanel::FHUtils::Blocking          ();
use Cpanel::Server::WebSocket::Courier ();
use Cpanel::Server::Handlers::Modular  ();

#overridden in tests
our $_WS_MODULE_BASE = 'Cpanel::Server::WebSocket';

sub _MODULE_BASE { return $_WS_MODULE_BASE }

=head1 METHODS

=head2 I<OBJ>->handler( MODULE_NAME )

This queries the server object (passed into C<new()>) to determine
the connection parameters (e.g., extensions or subprotocols).
It then instantiates the proper WebSocket module and calls its C<run()>
method.

WebSocket application modules exist in the L<Cpanel::Server::WebSocket::App::*>
namespace; e.g., the C<Shell> WebSocket module is
L<Cpanel::Server::WebSocket::App::Shell>.

=head1 SEE ALSO

L<Cpanel::Server::Handlers::SSE> follows a similar pattern.

=cut

sub handler {
    my ( $self, $module_name ) = @_;

    my $server_obj = $self->get_server_obj();

    my $full_mod = Cpanel::Server::Handlers::Modular::load_and_authz_module( $server_obj, _MODULE_BASE(), $module_name );

    $self->_do_handshake();

    # cpsrvd’s die handler causes an HTTP 500 response to be sent.
    # That’s obviously wrong after a successful WebSocket handshake.
    #
    # As of this writing that die handler no-ops when $^S is truthy;
    # the problem is that if you eval { require $module } and $module
    # exists but itself use()s a nonexistent module, then cpsrvd’s die
    # handler will fire with *falsy* $^S because the nonexistent module
    # is seen first in Perl’s compilation phase, during which $^S is falsy.
    #
    # We thus need to disable cpsrvd’s die handler entirely here
    # to prevent weirdness like that.
    #
    local $SIG{'__DIE__'} = 'DEFAULT';

    $server_obj->logger()->logaccess();

    my $max_pings = $full_mod->MAX_PINGS();

    alarm $full_mod->TIMEOUT();

    my $courier = Cpanel::Server::WebSocket::Courier->new(
        socket     => $self->get_server_obj()->connection()->get_socket(),
        compressor => $self->{'_compressor'},
        max_pings  => $max_pings,
    );

    #When cpsrvd restarts it sends SIGHUP to all tracked child processes.
    #Since we want WebSocket connections to persist through a cpsrvd restart
    #we ignore SIGHUP.
    local $SIG{'HUP'} = 'IGNORE';

    # Ensure that this process is terminated on logout.
    # NB: There’s no session if, e.g., we were called with an API token.
    $self->_register_process_in_session_if_needed();

    return $full_mod->new($server_obj)->run($courier);
}

sub _do_handshake {
    my ($self) = @_;

    my $cpsrvd_request = $self->get_server_obj()->request();

    my $ws_deflate = Net::WebSocket::PMCE::deflate::Server->new();
    my $hsk        = Net::WebSocket::Handshake::Server->new(
        extensions => [$ws_deflate],
    );

    try {
        $hsk->valid_method_or_die( $cpsrvd_request->get_request_method() );
        $hsk->valid_protocol_or_die( 'HTTP/' . $cpsrvd_request->get_protocol() );
        $hsk->consume_headers( %{ $cpsrvd_request->get_headers() } );
    }
    catch {
        if ( try { $_->isa('Net::WebSocket::X::Base') } ) {
            die Cpanel::Exception::create_raw( 'cpsrvd::BadRequest', $_->get_message() );
        }

        local $@ = $_;
        die;
    };

    if ( $ws_deflate->ok_to_use() ) {
        $self->{'_compressor'} = $ws_deflate->create_data_object();
    }

    my $client_skt = $self->get_server_obj()->connection()->get_socket();

    Cpanel::FHUtils::Autoflush::enable($client_skt);
    Cpanel::FHUtils::Blocking::set_blocking($client_skt);

    Cpanel::Autodie::syswrite_sigguard( $client_skt, $hsk->to_string() );

    Cpanel::FHUtils::Blocking::set_non_blocking($client_skt);

    return $client_skt;
}

#----------------------------------------------------------------------

=head1 HOW TO WRITE A WEBSOCKET APPLICATION MODULE

Example: C<Cpanel::Server::WebSocket::cpanel::MyCoolApp> is available
via the URL C</websocket/MyCoolApp> from cPanel—but B<only> from cPanel.
Likewise, C<Cpanel::Server::WebSocket::whostmgr::MyCoolApp> is available
via the same URL but from WHM—and B<only> WHM.

=over

=item * C<TIMEOUT()> - Returns the value to pass to C<alarm()> prior to
calling C<run()>. This can be 0 if the process should live indefinitely.
Usually defined as constant.

=item * C<new()> - Currently just expected to instantiate the module.

=item * C<run(COURIER)> - Runs the actual application. It receives an instance
of L<Cpanel::Server::WebSocket::Courier>, which your application will use to
interact with the client.

=item * C<_MAX_PINGS()> - Optional. Defines the C<max_pings> value to give
to L<Cpanel::Server::WebSocket::Courier>.

This is an I<indirect> form of inactivity timeout; how long it actually
means to wait depends on how often your application calls the courier’s
C<check_heartbeat()> method. If you set _MAX_PINGS == 10, and send that
heartbeat every 3 seconds, that’s a much shorter timeout than if you say
_MAX_PINGS == 3 but only send the heartbeat once per minute.

=back

B<ADDITIONALLY:> Each application must subclass either
L<Cpanel::Server::WebSocket::cpanel> or L<Cpanel::Server::WebSocket::whostmgr>.
These define the following (which ordinarily you, the application module
author, B<don’t> need to worry about):

=over

=item * C<verify_access()> - Receives an instance of L<Cpanel::Server>.
Receives no arguments. Return truthy to confirm
access; a falsey return will reject access. Executes as a class method.

=back

What you, application module author, I<will> need to implement are any
methods that that additional parent class requires.

NB: To write an application that can run in both cPanel I<and> WHM,
create a base class that implements the bulk of the functionality, then
create separate cPanel and WHM subclasses that inherit from both your
application’s base class as well as whatever base class implements
C<verify_access()>. See the “MysqlDump” modules for an example of this.

=cut

1;
