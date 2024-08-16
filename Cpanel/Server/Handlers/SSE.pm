package Cpanel::Server::Handlers::SSE;

# cpanel - Cpanel/Server/Handlers/SSE.pm           Copyright 2022 cPanel, L.L.C.
#                                                           All rights reserved.
# copyright@cpanel.net                                         http://cpanel.net
# This code is subject to the cPanel license. Unauthorized copying is prohibited

use strict;
use warnings;

=encoding utf-8

=head1 NAME

Cpanel::Server::Handlers::SSE - SSE handler for cpsrvd

=head1 SYNOPSIS

    # This is how this class is normally instantiated.
    my $handler_obj = $server_obj->get_handler('SSE');

    # Assumes that there is a “ProcessRequest” SSE module
    # under “Cpanel::Server::SSE”. See Cpanel::Server::Handlers::Modular
    # for more details.
    $handler_obj->handler('ProcessRequest', [ 1101 ]);

=head1 DESCRIPTION

This module interfaces with cpsrvd to call SSE modules as requests dictate.
It subclasses L<Cpanel::Server::Handler> and implements the module-loading
behavior described in L<Cpanel::Server::Handlers::Modular>.

=cut

#----------------------------------------------------------------------

use parent 'Cpanel::Server::Handler';

use Try::Tiny;

use Cpanel::Exception                 ();
use Cpanel::LoadModule                ();
use Cpanel::Server::Handlers::Modular ();

my $SSE_MIME_TYPE = 'text/event-stream';

#overridden in tests
our $_SSE_MODULE_BASE = 'Cpanel::Server::SSE';

sub _MODULE_BASE { return $_SSE_MODULE_BASE }

#----------------------------------------------------------------------

=head1 METHODS

=head2 I<OBJ>->handler( $MODULE_NAME, \@ARGUMENTS )

This queries the server object (passed into C<new()>) to determine
the request parameters (e.g., whether to compress the response).
It then instantiates the proper SSE module and calls its C<run()>
method.

SSE modules exist in the L<Cpanel::Server::SSE::${service}::*> namespace;
e.g., WHM’s C<Tasks> SSE module is L<Cpanel::Server::SSE::whostmgr::Tasks>.

=head3 ARGUMENTS

=over

=item MODULE_NAME - string

Name of the SSE module to load

=item ARGUMENTS - array ref

Optional list of arguments provided on the URL path.

NB: You can also pass arguments to SSE modules via URL query strings,
either in lieu of or in additional to arguments from the URL path.
These two facilities are mutually redundant.

=back

=head3 RETURNS

1 if successful

=head3 EXCEPTIONS

=over

=item When the module is not provided

=item When the module is not available on the system.

=item When the module can not be loaded.

=item When the module is not accessible due to feature limitations or demo mode.

=item When the request type is not 'text/event-stream'

=back

=cut

sub handler {
    my ( $self, $module, $args ) = @_;

    my $server_obj = $self->get_server_obj();

    my $full_mod = Cpanel::Server::Handlers::Modular::load_and_authz_module( $server_obj, _MODULE_BASE(), $module );

    my $output_buffer = q<>;

    #The spec says to check for this:
    #   https://www.w3.org/TR/eventsource/#processing-model
    if ( my $accept = $server_obj->request()->get_header('accept') ) {
        if ( -1 == index( $accept, $SSE_MIME_TYPE ) ) {
            die Cpanel::Exception::create_raw( 'cpsrvd::NotAcceptable', "“Accept” header ($accept) did not include “$SSE_MIME_TYPE”!" );
        }
    }

    my $responder_class = 'Cpanel::Server::Responders::Stream';

    my $encodings = $server_obj->request()->get_header('accept-encoding');

    my $use_gzip = $encodings && ( index( $encodings, 'gzip' ) != -1 );

    if ($use_gzip) {
        $responder_class .= '::Gzip';
    }

    Cpanel::LoadModule::load_perl_module($responder_class);
    my $responder = $responder_class->new(

        #What Cpanel::Server::Responder calls “input buffer” is actually
        #a buffer for the output stream here.
        input_buffer => \$output_buffer,

        output_coderef => sub {
            $server_obj->write_buffer(@_);
        },

        #superfluously required arguments
        headers_buffer                  => \q<>,
        input_handle_read_function_name => '_this_should_never_read_',
    );

    my $sse = $full_mod->new(
        responder     => $responder,
        last_event_id => $server_obj->request()->get_header('last-event-id'),
        args          => $args,
    );

    my $headers = $server_obj->fetchheaders( $Cpanel::Server::Constants::FETCHHEADERS_DYNAMIC_CONTENT, $sse->has_content() ? 200 : 204 );
    if ($use_gzip) {
        $headers .= "Content-Encoding: gzip\r\n";
    }

    $headers .= "Content-type: $SSE_MIME_TYPE\r\n\r\n";

    $server_obj->write_buffer($headers);

    $server_obj->response()->set_state_sent_headers_to_socket();

    if ( $sse->has_content() ) {

        #SSE doesn’t build in any mechanism for us to know that
        #the client is gone, so we have to rely on SIGPIPE. cpsrvd normally
        #logs on SIGPIPE (cf. Cpanel::Server::Connection::pipehandler()),
        #which we don’t want in this case because, for SSE, SIGPIPE just
        #means the normal end of a connection. So we set this flag, which
        #tells cpsrvd to forgo that logging.
        $server_obj->connection()->forgo_sigpipe_logging();

        # Ensure that this process is terminated on logout.
        $self->_register_process_in_session_if_needed();

        $sse->run();
    }

    return 1;
}

#----------------------------------------------------------------------

=head1 HOW TO CREATE AN SSE APPLICATION MODULE

Example: C<Cpanel::Server::SSE::cpanel::MyCoolApp> is available via
the URL C</sse/MyCoolApp> from within cPanel. (And *only* cPanel.)

Likewise, C<Cpanel::Server::SSE::whostmgr::MyCoolerApp> is available
via the URL C</sse/MyCoolerApp> from within WHM. (And *only* WHM.)

Each application module must define the methods described in
L<Cpanel::Server::SSE>. Depending on the service (cPanel vs. WHM) where
the application runs, L<Cpanel::Server::SSE::cpanel> or
L<Cpanel::Server::SSE::whostmgr> document additional logic that may need
to be added.

=cut

1;
