
# cpanel - Whostmgr/ModSecurity/Chunk/Diff.pm      Copyright 2022 cPanel, L.L.C.
#                                                           All rights reserved.
# copyright@cpanel.net                                         http://cpanel.net
# This code is subject to the cPanel license. Unauthorized copying is prohibited

package Whostmgr::ModSecurity::Chunk::Diff;

use strict;

use Algorithm::Diff ();
use Cpanel::Locale 'lh';

=head1 NAME

Whostmgr::ModSecurity::Chunk::Diff

=head2 annotate_pending()

=head3 Description

Given two arrays of chunks, annotates chunks from one with the 'staged' flag where
appropriate based on a diff performed on the two lists of chunks.

=head3 Arguments

Accepts named arguments:

'annotate': An array of chunk objects which will be updated in-place to provide the 'pending'
field where appropriate, based on the difference compared to 'reference'.

'reference': An array of chunk objects against which to compare the 'annotate' list. Any
differences in 'annotate' relative to this set of chunks will be marked as pending changes.

=head3 Returns

This function doesn't return anything. It makes its adjustments directly in the array passed
as 'annotate'.

=cut

sub annotate_pending {
    my %args = @_;
    if ( !$args{annotate} || !$args{reference} ) {
        die lh()->maketext(q{You must specify both [asis,annotate] and [asis,reference], which are arrays of chunk objects.}) . "\n";    # Not-user-facing error except in the event of a bug
    }

    my @ref_strs = map { $_->text } @{ $args{reference} };
    my @new_strs = map { $_->text } @{ $args{annotate} };

    # To better understand how to maintain this function, please see perldoc Algorithm::Diff
    # and read how traverse_balanced() works.

    Algorithm::Diff::traverse_balanced(
        \@ref_strs,
        \@new_strs,
        {
            MATCH => sub {
                my ( $off_ref, $off_ann ) = @_;

                # If the new chunk is a match to an old chunk, only mark it as having staged
                # changes if the old chunk was already marked as having staged changes.
                $args{annotate}[$off_ann]->staged(1) if $args{reference}[$off_ref]->staged;
            },
            DISCARD_A => sub {    # A is reference; B is annotate... --> DISCARD_A is a delete

                # If the old chunk was deleted, there is nothing to annotate.
            },
            DISCARD_B => sub {    # A is reference; B is annotate... --> DISCARD_B is an add
                my ( $off_ref, $off_ann ) = @_;

                # If a new chunk was added (represented as DISCARD_B in the diff), unconditionally
                # mark it as having staged changes.
                $args{annotate}[$off_ann]->staged(1);
            },
            CHANGE => sub {
                my ( $off_ref, $off_ann ) = @_;

                # If a chunk was modified, unconditionally mark it as having staged changes.
                $args{annotate}[$off_ann]->staged(1);
            },
        }
    );
    return;
}

1;
