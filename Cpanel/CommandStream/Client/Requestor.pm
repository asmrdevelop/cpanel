package Cpanel::CommandStream::Client::Requestor;

# cpanel - Cpanel/CommandStream/Client/Requestor.pm
#                                                  Copyright 2022 cPanel, L.L.C.
#                                                           All rights reserved.
# copyright@cpanel.net                                         http://cpanel.net
# This code is subject to the cPanel license. Unauthorized copying is prohibited

use cPstrict;

=encoding utf-8

=head1 NAME

Cpanel::CommandStream::Client::Requestor

=head1 SYNOPSIS

    my $client = Cpanel::CommandStream::Client->new();

    my $promise_tracker = Cpanel::Async::PromiseTracker->new();

    my $requestor = $client->create_requestor(
        sub (%message) {
            # Do whatever to send %message ..
        },
        $promise_tracker,
    );

    my $req = $requestor->request( 'exec', '/path/to/binary', 'arg1', .. );

=head1 DESCRIPTION

This class implements controls for making CommandStream requests.

=head1 HOW TO WRITE A REQUEST MODULE

See F<Cpanel/CommandStream/README.md> in the parent directory.

=cut

#----------------------------------------------------------------------

use parent 'Cpanel::Destruct::DestroyDetector';

use Cpanel::LoadModule::Utils ();

#----------------------------------------------------------------------

=head1 METHODS

=head2 $req = I<OBJ>->request( $MSG_CLASS, @ARGS )

Sends a request of type $MSG_CLASS with arguments @ARGS.

The returned $req will be an instance of
C<Cpanel::CommandStream::Client::Request::$MSG_CLASS>. Whatever class
that is also dictates what @ARGS should be.

=cut

sub request ( $self, $msg_class, @args ) {
    my $id = $self->{'next_id'};

    my ( $req, $cb, @args_kv ) = _get_req_creator($msg_class)->(
        $self->{'promise_tracker'},
        @args,
    );

    $self->{'to_send_cr'}->(
        class => $msg_class,
        id    => $id,
        @args_kv,
    );

    $self->{'id_callback'}{$id} = $cb;

    $self->{'next_id'}++;

    return $req;
}

=head2 $obj = I<CLASS>->new( $CLIENT_OBJ, $SENDER_CR )

Instantiates this class. Normally called from
L<Cpanel::CommandStream::Client>.

$CLIENT_OBJ is the L<Cpanel::CommandStream::Client> object that
complements the new $obj.

$SENDER_CR is what sends a message; it
receives a list of key/value pairs that represent a message.
(Its return is thrown away.)

=cut

sub new ( $class, $client_obj, $to_send_cr, $promise_tracker ) {    ## no critic qw(ManyArgs) - mis-parse
    return bless {
        next_id         => 0,
        to_send_cr      => $to_send_cr,
        promise_tracker => $promise_tracker,

        %{$client_obj}{'id_callback'},
    }, $class;
}

#----------------------------------------------------------------------

sub _get_req_creator ($msg_class) {
    my $req_class = "Cpanel::CommandStream::Client::Request::$msg_class";

    if ( !$req_class->can('_create') ) {
        my $req_class_path = Cpanel::LoadModule::Utils::module_path($req_class);

        local ( $@, $! );
        require $req_class_path;
    }

    return $req_class->can('_create') || do {
        die "$req_class can’t _create()!";
    };
}

1;
