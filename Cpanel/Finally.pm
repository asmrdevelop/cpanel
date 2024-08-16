package Cpanel::Finally;

# cpanel - Cpanel/Finally.pm                       Copyright 2022 cPanel, L.L.C.
#                                                           All rights reserved.
# copyright@cpanel.net                                         http://cpanel.net
# This code is subject to the cPanel license. Unauthorized copying is prohibited

=encoding utf8

=head1 NAME

C<Cpanel::Finally>

=head1 DESCRIPTION

Use this module to schedule actions for the end of a scope, whether the
scope ends "naturally", die()s, or exit()s.

=head1 SYNOPSIS

    use Cpanel::Finally ();

    {
        my $finally = Cpanel::Finally->new( sub { kill 'TERM', $some_pid } );
    }

    # will kill off that child process once the $finally object is DESTROYed.


You can also have multiple coderefs in queue:

    {
        my $finally = Cpanel::Finally->new( @action_crs );  # the array can be empty
        $finally->add( $one_more_cr, $and_another_cr, .. );
    }

and the coderefs will execute in the order in which they were added
to the queue.

If there are no coderefs in the queue when the object is destroyed, then
nothing executes (besides the normal object destruction).

Do not assign Finally objects to variables in the stash without ALSO assuring an END block
will trigger DESTROY prior to global destruction.
Items on the stash are variables that live outside a subroutine.

=head1 FUNCTIONS

=cut

use cPstrict;

use Cpanel::Destruct ();
use Cpanel::Debug    ();

=head2 new( $class, @todo_crs )

Create the Cpanel::Finally object.

=cut

sub new ( $class, @todo_crs ) {

    return bless { 'pid' => $$, 'todo' => [@todo_crs] }, $class;
}

=head2 $self->add( @todo_crs )

Add some extra actions (CodeRef) triggered during global destruction.

=cut

sub add ( $self, @new_crs ) {

    $self->{'todo'} //= [];
    push @{ $self->{'todo'} }, @new_crs;

    return;
}

=head2 $self->skip()

Disable the Finally action by clearing the todo.

=cut

sub skip ($self) {
    return delete $self->{'todo'};
}

sub DESTROY ($self) {

    if ( Cpanel::Destruct::in_dangerous_global_destruction() ) {
        Cpanel::Debug::log_die(q[Cpanel::Finally should never be triggered during global destruction\n]);
    }

    return if $$ != $self->{'pid'} || !$self->{'todo'};

    local $@;    #prevent insidious clobber of error messages

    while ( @{ $self->{'todo'} } ) {
        my $ok = eval {
            while ( my $item = shift @{ $self->{'todo'} } ) {
                $item->();
            }

            1;
        };

        warn $@ if !$ok;
    }

    return;
}

1;
