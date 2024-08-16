package Cpanel::CommandQueue;

# cpanel - Cpanel/CommandQueue.pm                  Copyright 2022 cPanel, L.L.C.
#                                                           All rights reserved.
# copyright@cpanel.net                                         http://cpanel.net
# This code is subject to the cPanel license. Unauthorized copying is prohibited

use strict;
use warnings;

=encoding utf-8

=head1 NAME

Cpanel::CommandQueue - Transactional(-ish) task queues

=head1 SYNOPSIS

    my $cq = Cpanel::CommandQueue->new();

    $cq->add(
        \&_to_do,
        \&_to_undo,
        'description of the undo process',
    );

    $cq->add( .. );

    $cq->run();

=head1 DESCRIPTION

This module provides a means of organizing task queues with rollback to help
ensure that, if one task fails, previously-executed tasks roll back.

For example, consider a queue of tasks A, B, and C. Suppose C fails.
You now need to roll back B and A (in that order).
Each task can thus optionally be stored with an “undo” task and
a label for the “undo”. The undo label’s purpose is to identify the
undo phase if the undo itself also produces an exception.

If any item on the queue C<die()>s (i.e., upon C<run()>), this executes the
undo tasks in reverse order, starting with the undo for the most recent
successful task. C<run()> will then rethrow the fatal task’s error,
“upgraded” to a L<Cpanel::Exception> if necessary. (See L<Cpanel::Rollback>’s
C<rollback()> method for more details.)

If any undo C<die()>s, this is handled as L<Cpanel::Rollback> describes.

NB: This module executes I<synchronously>; i.e., C<run()> does not finish
until all tasks/rollbacks have finishes.

=head1 EXAMPLE

Let’s say you want an “atomic” write of a file, but not overwrite
the file if it already exists. To do that you:

=over

=item * A. Open a temp file

=item * B. Write and close the temp file

=item * C. C<link()> the temp file into place (NB: Unlike C<rename()>,
C<link()> fails if the destination path already exists.)

=item * D. C<unlink()> the temp file

=back

If anything after A fails, of course, you’ll want to roll back.

You can use this module as such:

    my $cq = Cpanel::CommandQueue->new();

    # Step A
    $cq->add(
        \&_open_temp_file,
        \&_unlink_temp_file,
        'unlink temp file',
    );

    # Step B
    $cq->add(
        \&_write_temp_file,
    );

    # Step C
    $cq->add(
        \&_link_temp_file_into_place
    );

    $cq->run();

    # Step D
    warn if !eval { _unlink_temp_file(); 1 };

A few notes:

=over

=item * Note that step B lacks an undo. Step B changes the system state,
but since unlinking the temp file (step A’s undo)
also undoes step B, there’s no need for an explicit undo of step B.

=item * Step C also lacks an undo; however, this is because once step C
succeeds, the whole queue has succeeded, and nothing will need to be rolled
back. B<The> B<final> B<task> B<never> B<needs> B<a> B<rollback.> (Of course,
there’s no harm in I<providing> one.)

=item * Step D happens after the queue runs. This is because it’s an “extra”
step that just cleans up the cruft from the earlier steps. If it fails,
nothing is actually I<broken>.

=back

=head1 CAVEATS

It’s possible for a power loss to occur at any point during either
successful execution of the tasks or rollback. As much as possible,
design your task queues such that the system is B<ALWAYS> in a valid
state.

=head1 SUBCLASSING

This class only supports coderefs as tasks, but there are
overridable methods that subclasses can use to support anything else,
e.g., database commands.

=cut

#----------------------------------------------------------------------

use Try::Tiny;

use Cpanel::Rollback ();

#----------------------------------------------------------------------

=head1 METHODS

=head2 $obj = I<CLASS>->new()

Instantiates this class.

=cut

sub new {
    my ($class) = @_;

    return bless { _queue => [] }, $class;
}

=head2 I<CLASS>->add( \&TODO, \&UNDO, $UNDO_LABEL )

Adds a task—and, optionally, its undo operation—to the queue.

=cut

sub add {
    my ( $self, $work_todo, $undo_todo, $undo_label ) = @_;

    push @{ $self->{'_queue'} },
      {
        work       => $work_todo,
        undo       => $undo_todo,
        undo_label => $undo_label,
      };

    return;
}

=head2 I<OBJ>->run()

Runs the queue, as described in L</DESCRIPTION> above.

=cut

sub run {
    my ($self) = @_;

    my $rollback = Cpanel::Rollback->new();

    my $stmt;
    try {
        while ( $stmt = shift @{ $self->{'_queue'} } ) {
            $self->_convert_cmd_to_coderef( $stmt->{'work'} )->();

            if ( $stmt->{'undo'} ) {
                $rollback->add(
                    $self->_convert_cmd_to_coderef( $stmt->{'undo'} ),
                    $stmt->{'undo_label'},
                );
            }
        }
    }
    catch {
        my $err = $_;
        die $rollback->rollback($err);
    };

    return;
}

#----------------------------------------------------------------------
# Overridable method for subclasses to allow a command to be something
# other than a coderef.
#----------------------------------------------------------------------

sub _convert_cmd_to_coderef {
    my ( $self, $todo_cr ) = @_;

    return $todo_cr;
}

1;
