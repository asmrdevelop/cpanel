package Cpanel::CommandStream::Server;

# cpanel - Cpanel/CommandStream/Server.pm          Copyright 2022 cPanel, L.L.C.
#                                                           All rights reserved.
# copyright@cpanel.net                                         http://cpanel.net
# This code is subject to the cPanel license. Unauthorized copying is prohibited

use cPstrict;

=encoding utf-8

=head1 NAME

Cpanel::CommandStream::Server

=head1 SYNOPSIS

    my $serializer = Cpanel::CommandStream::Serializer::JSON->new();

    my $send_blob_cr = sub ($blob) { .. };

    my $server_obj = Cpanel::CommandStream::Server->new(
        $serializer,
        $send_blob_cr,
    );

    $server_obj->handle_message( \$blob_in );

=head1 DESCRIPTION

This module implements server mechanics for CommandStream, a protocol
for multiplexing requests from a client to a server over a persistent
connection.

This module is, by design, B<transport-agnostic>.

=head1 TRANSPORT REQUIREMENTS

Whatever transport undergirds CommandStream must satisfy B<all> of
these requirements:

=over

=item * Must be reliable and ordered (like TCP)

=item * Must preserve message boundaries (like UDP or SCTP)

=back

Example transports include WebSocket, SCTP, and SOCK_SEQPACKET Unix-domain
sockets.

=cut

#----------------------------------------------------------------------

use parent (
    'Cpanel::Destruct::DestroyDetector',
);

use Cpanel::CommandStream::Courier ();
use Cpanel::Exception              ();
use Cpanel::LoadModule             ();
use Cpanel::Try                    ();

our $_HANDLER_NAMESPACE = 'Cpanel::CommandStream::Handler';

use constant {
    _DEBUG => 0,
};

#----------------------------------------------------------------------

=head1 METHODS

=head2 $obj = I<CLASS>->new( $SERIALIZER, $SEND_CR )

Instantiates this class. $SERIALIZER is an instance of
L<Cpanel::CommandStream::Serializer>. $SEND_CR is a callback
that accepts a byte string and sends it.

=cut

sub new ( $class, $serializer, $send_msg_cr ) {

    my %self = (
        serializer  => $serializer,
        send_msg_cr => $send_msg_cr,
        in_progress => {},
    );

    return bless \%self, $class;
}

=head2 I<OBJ>->handle_message( $INPUT_SR )

Receives input and processes it accordingly. $INPUT_SR is a
reference to a byte string.

Nothing is returned.

=cut

sub handle_message ( $self, $buf_sr ) {
    my ( $msg_hr, $handler_obj, $courier ) = $self->_parse_message($buf_sr);

    return if !$msg_hr;

    _DEBUG() && print STDERR "post-parse\n";

    my $handler_obj_str = "$handler_obj";

    my $in_progress_hr = $self->{'in_progress'};

    $in_progress_hr->{$handler_obj_str} = $handler_obj;

    $handler_obj->run( $msg_hr, $courier )->finally(
        sub {
            delete $in_progress_hr->{$handler_obj_str};
        },
    );

    return;
}

sub _parse_message ( $self, $buf_sr ) {
    my $msg_content;

    my $send_msg_cr = $self->_create_send_message_cb();

    local $@;
    eval {
        $msg_content = $self->{'serializer'}->parse($buf_sr);
        1;
    } or do {
        $send_msg_cr->(
            {
                class   => 'deserialization_failed',
                id      => undef,
                request => $$buf_sr,
                why     => Cpanel::Exception::get_string($@),
            },
        );

        return;
    };

    if ( 'HASH' ne ref $msg_content ) {
        $send_msg_cr->(
            {
                class   => 'malformed_structure',
                id      => undef,
                request => $msg_content,
            },
        );

        return;
    }

    if ( !length $msg_content->{'id'} ) {
        $send_msg_cr->(
            {
                class   => 'missing_id',
                id      => undef,
                request => $msg_content,
            },
        );

        return;
    }

    # XXX IMPORTANT: $courier MUST NOT refer to $self, or we’ll
    # have circular references.

    my $courier = Cpanel::CommandStream::Courier->new(
        $msg_content->{'id'},
        $send_msg_cr,
    );

    my $msg_class = $msg_content->{'class'};

    if ( !length $msg_class ) {
        $courier->send_response('missing_class');

        return;
    }

    my $handler_class = "$_HANDLER_NAMESPACE\::$msg_class";

    if ( !$handler_class->can('new') ) {
        Cpanel::Try::try(
            sub {
                Cpanel::LoadModule::load_perl_module($handler_class);
            },
            'Cpanel::Exception::ModuleLoadError' => sub {
                my $err = $@;

                if ( $err->is_not_found() ) {
                    $courier->send_response('unknown_class');
                }
                else {
                    local $@ = $err;
                    die;
                }
            },
        );
    }

    my $handler_obj = $handler_class->can('new') && $handler_class->new();

    return if !$handler_obj;

    return ( $msg_content, $handler_obj, $courier );
}

sub _create_send_message_cb ($self) {
    my $send_cr    = $self->{'send_msg_cr'};
    my $serializer = $self->{'serializer'};

    return sub ($msg_hr) {
        $send_cr->( $serializer->stringify($msg_hr) );
    };
}

1;
