package Cpanel::CommandStream::Handler;

# cpanel - Cpanel/CommandStream/Handler.pm         Copyright 2022 cPanel, L.L.C.
#                                                           All rights reserved.
# copyright@cpanel.net                                         http://cpanel.net
# This code is subject to the cPanel license. Unauthorized copying is prohibited

use cPstrict;

=encoding utf-8

=head1 NAME

Cpanel::CommandStream::Handler - Base class for CommandStream request handlers

=head1 DESCRIPTION

All classes that implement handler logic for CommandStream requests should
subclass this one.

=head1 SUBCLASS INTERFACE

All subclasses must implement:

=over

=item * C<_run( \%REQUEST, $COURIER, $COMPLETION_DEFERRED )>

The “core” of a CommandStream handler.

Arguments are:

=over

=item * %REQUEST is the parsed request from the client.

=item * $COURIER is an instance of L<Cpanel::CommandStream::Courier>
to use while handling this request.

=item * $COMPLETION_DEFERRED is a L<Promise::XS::Deferred> instance.
Your method should C<resolve()> this object once it’s done.

=back

=back

=cut

#----------------------------------------------------------------------

use parent (
    'Cpanel::Destruct::DestroyDetector',
);

use Promise::XS ();

use Cpanel::Exception ();

#----------------------------------------------------------------------

=head1 METHODS

=head2 $obj = I<CLASS>->new()

Instantiates this class.

=cut

sub new ($class) {
    return bless {}, $class;
}

=head2 $promise = I<CLASS>->run( \%REQUEST, $COURIER )

Runs the object.

%REQUEST and $COURIER are as described in the description
of C<_run()> in the L</SUBCLASS INTERFACE> section above.

The return is a promise that resolves once the request is completed.

=cut

sub run ( $self, $req_hr, $courier ) {
    my $completion_d = Promise::XS::deferred();

    local $@;
    my $ok = eval {
        $self->_run( $req_hr, $courier, $completion_d );
        1;
    };

    if ( !$ok ) {
        my $err = $@;
        if ( !eval { $err->isa('Cpanel::Exception') } ) {
            $err = Cpanel::Exception->create_raw($err);
        }

        warn $err;

        $courier->send_response( 'internal_failure', { xid => $err->id() } );

        $completion_d->resolve();
    }

    return $completion_d->promise();
}

1;
