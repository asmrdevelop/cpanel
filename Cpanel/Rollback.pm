package Cpanel::Rollback;

# cpanel - Cpanel/Rollback.pm                      Copyright 2022 cPanel, L.L.C.
#                                                           All rights reserved.
# copyright@cpanel.net                                         http://cpanel.net
# This code is subject to the cPanel license. Unauthorized copying is prohibited

use strict;
use warnings;

=encoding utf-8

=head1 NAME

Cpanel::Rollback - roll back a set of operations

=head1 SYNOPSIS

    my $rb = Cpanel::Rollback->new();

    # Do a thing …
    $rb->add( sub { undo_that_thing() } );

    # Do another thing …
    $rb->add( sub { undo_that_other_thing() } );

    # Oops! Something went wrong. Better undo …
    my $cp_err = $rb->rollback($orig_err);

=head1 DESCRIPTION

B<IMPORTANT:> You probably don’t want this module in isolation; look at
L<Cpanel::CommandQueue> instead.

This module holds the queue for doing a set of operations in the opposite
order from that in which they are added (i.e., first-in-last-out).
This behavior is ideally suited to rolling back in the event of failure
when one of a group of operations fails.

e.g.:
Steps A, B, and C. If B fails, then A must be rolled back. If C fails,
then B and A must be rolled back, in that order.

So, normally:

=over

=item * Create a $rollback object.

=item * Do step A.

=item * ^ If successful, add A’s rollback to the $rollback object.

=item * Do step B. If successful, add B’s rollback; otherwise, $rollback->rollback().

=item * Do step C; if failure, $rollback->rollback().

=back

(C needs no rollback since this completes the “transaction”.)

NOTE: If a rollback fails, then each error produces a
L<Cpanel::Exception::RollbackError> object
whose C<error> attribute is the command’s error. The RollbackError is added
as an auxiliary to the exception passed into C<rollback()>. See below.

=cut

#----------------------------------------------------------------------

use Try::Tiny;

use Cpanel::Exception ();

#----------------------------------------------------------------------

=head1 METHODS

=head2 $obj = I<CLASS>->new()

Instantiates this class.

=cut

sub new {
    my ($class) = @_;

    return bless [], $class;
}

=head2 I<CLASS>->add( \&CALLBACK, $LABEL )

Adds a rollback step. $LABEL is a string that describes what &CALLBACK
does; if &CALLBACK throws, then $LABEL is part of the auxiliary exception
added to the error given to C<rollback()>.

=cut

sub add {
    my ( $self, $cmd, $label ) = @_;

    die 'Command must be coderef!' if !UNIVERSAL::isa( $cmd, 'CODE' );

    return push @$self, { code => $cmd, label => $label };
}

#This catches exceptions around each function and returns
#an array that contains a hash for each failed rollback:
#{
#   code => the coderef that failed,
#   error => the exception,
#   label => the coderef's label from add(),
#}
#
#TODO: Would it be worthwhile to fork() for each one, to guarantee
#that no rollback would prevent the others from running?
sub _iterate_commands {
    my ( $self, $catch_cr ) = @_;

    while (@$self) {
        my $cmd = pop @$self;

        my ( $code, $label ) = @{$cmd}{qw(code label)};

        try { $code->() }
        catch {
            $catch_cr->( $code, $label, $_ );
        };
    }

    return;
}

=head2 $cp_error = I<OBJ>->rollback( $ERROR )

Executes I<OBJ>’s previously C<add()>ed callbacks in reverse order.

$ERROR is whatever error caused us to want to call C<rollback()>.

The return is a L<Cpanel::Exception>. If the given $ERROR is itself an
instance of that class (i.e., or a subclass thereof), then the return
is just $ERROR. Otherwise, the return is a wrapper around $ERROR.

If any callback throws an error, that error will be trapped and added
as an auxiliary exception to the returned L<Cpanel::Exception>.
(See that module’s documentation for more information about auxiliary
exceptions.)

=cut

sub rollback {
    my ( $self, $base_exception ) = @_;

    if ( !try { $base_exception->isa('Cpanel::Exception') } ) {
        $base_exception = Cpanel::Exception->create_raw($base_exception);
    }

    $self->_iterate_commands(
        sub {
            my ( $code, $label, $err ) = @_;

            my $exception = Cpanel::Exception::create(
                'RollbackError',
                {
                    error => $err,
                    label => $label,
                }
            );

            $base_exception->add_auxiliary_exception($exception);
        }
    );

    return $base_exception;
}

1;
