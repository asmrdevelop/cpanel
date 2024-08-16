package Cpanel::Event::Emitter;

# cpanel - Cpanel/Event/Emitter.pm                 Copyright 2022 cPanel, L.L.C.
#                                                           All rights reserved.
# copyright@cpanel.net                                         http://cpanel.net
# This code is subject to the cPanel license. Unauthorized copying is prohibited

use cPstrict;

=encoding utf-8

=head1 NAME

Cpanel::Event::Emitter

=head1 SYNOPSIS

    package MyEmitter;

    use parent 'Cpanel::Event::Emitter';

    #----------------------------------------------------------------------

    # Something that instantiates this class.
    my $emitter = _create_emitter();

    $emitter->on(
        lights_on => sub (@payload) { print @payload },
    );

    $emitter->emit( lights_on => 'hello!' );

=head1 DESCRIPTION

This little module mimics CPAN L<AnyEvent::Emitter> (which itself mimics
L<Mojo::EventEmitter>) but with a bit different—hopefully nicer—interface.

=head1 TO SUBCLASS, OR NOT TO SUBCLASS …

The examples here assume that you’re going to subclass this class,
but the class is also usable as an end class.

=cut

#----------------------------------------------------------------------

use Cpanel::Event::Emitter::Subscription ();

use parent 'Cpanel::Destruct::DestroyDetector';

use constant {
    _KEY => __PACKAGE__ . '_handlers',
};

#----------------------------------------------------------------------

=head1 METHODS

=head2 $obj = I<CLASS>->new()

Instantiates this class by just blessing a hashref. Unneeded if your
subclass does that already.

=cut

sub new ($class) {
    return bless {}, $class;
}

=head2 $obj = I<OBJ>->emit( $NAME, @PAYLOAD )

Emits an event $NAME with payload @PAYLOAD; i.e., all of $NAME’s registered
callbacks will be invoked with @PAYLOAD given as arguments.

Returns I<OBJ>.

=cut

sub emit ( $self, $name, @payload ) {
    if ( my $handlers_ar = $self->{ _KEY() }{$name} ) {
        $_->(@payload) for @$handlers_ar;
    }

    return $self;
}

=head2 $obj = I<OBJ>->emit_or_warn( $NAME, @PAYLOAD )

Like C<emit()>, but if there are no handlers registered,
then this C<warn()>s the @PAYLOAD.

=cut

sub emit_or_warn ( $self, $name, @payload ) {
    my $handlers_ar = $self->{ _KEY() }{$name};

    if ( $handlers_ar && @$handlers_ar ) {
        $_->(@payload) for @$handlers_ar;
    }
    else {
        warn "$name: @payload";
    }

    return $self;
}

#----------------------------------------------------------------------

=head2 $subscription = I<OBJ>->create_subscription( $NAME, $CALLBACK )

Like C<on()> but returns a L<Cpanel::Event::Emitter::Subscription>.
Recommended over C<on()>/C<once()>/C<off()> in order to avoid
action-at-a-distance bugs.

See L<Cpanel::Event::Emitter::Subscription> for more details.

=cut

sub create_subscription ( $self, $name, $cb ) {
    return Cpanel::Event::Emitter::Subscription->new( $self, $name, $cb );
}

#----------------------------------------------------------------------

=head2 $obj = I<OBJ>->on( $NAME, $CALLBACK )

Registers $CALLBACK to be called whenever the event $NAME is emitted.

Returns I<OBJ>.

=cut

sub on ( $self, $name, $cb ) {
    die "Falsy callback!" if !$cb;    # proactive

    push @{ $self->{ _KEY() }{$name} }, $cb;

    return $self;
}

=head2 $obj = I<OBJ>->once( $NAME, $CALLBACK )

Like C<on()> but unregisters $CALLBACK after the first time it’s fired.

Returns I<OBJ>.

=cut

sub once ( $self, $name, $cb ) {
    die "Falsy callback!" if !$cb;    # proactive

    my $handlers_ar;

    my $wrap_cb = sub {
        $cb->(@_);
        _remove_handler( $handlers_ar, $name, __SUB__ );
    };

    my $ret = $self->on( $name, $wrap_cb );

    $handlers_ar = $self->{ _KEY() };

    return $ret;
}

=head2 $obj = I<OBJ>->off( $NAME, $CALLBACK )

Unregisters $CALLBACK from $NAME’s list of handlers.

Returns I<OBJ>.

=cut

sub off ( $self, $name, $cb ) {
    die "Falsy callback!" if !$cb;    # proactive

    _remove_handler( $self->{ _KEY() }, $name, $cb );

    return $self;
}

sub _remove_handler ( $all_hr, $name, $cb ) {
    if ($all_hr) {
        if ( my $handlers_ar = $all_hr->{$name} ) {
            @$handlers_ar = grep { $_ ne $cb } @$handlers_ar;
        }
    }

    return;
}

1;
