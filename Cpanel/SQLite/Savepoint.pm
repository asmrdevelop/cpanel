package Cpanel::SQLite::Savepoint;

# cpanel - Cpanel/SQLite/Savepoint.pm              Copyright 2022 cPanel, L.L.C.
#                                                           All rights reserved.
# copyright@cpanel.net                                         http://cpanel.net
# This code is subject to the cPanel license. Unauthorized copying is prohibited

use cPstrict;

=encoding utf-8

=head1 NAME

Cpanel::SQLite::Savepoint

=head1 SYNOPSIS

    {
        my $save = Cpanel::SQLite::Savepoint->new( $dbh );

        # Alter the DB …
        $dbh->do( .. );

        # Necessary for the do() not to be rolled back:
        $save->release();
    }

=head1 DESCRIPTION

This class is a nicety around SQLite savepoints. The object represents
a savepoint from the time of its creation until it either is C<release()>d
or is DESTROYed. If the DESTROY happens first, then the savepoint is
rolled back (and a warning is given about that).

Note that the savepoint’s name is randomly chosen. This class, by design,
does not expose that name since such would break this class’s abstraction.

=head1 IMPORTANT DIFFERENCE FROM C<AutoCommit>

L<DBI>’s C<AutoCommit> works well enough, but consider the following:

    $dbh->{'AutoCommit'} = 1;

    {
        local $dbh->{'AutoCommit'} = 0;

        $dbh->do('REPLACE …');

        die 'oh no';
    }

In this instance, $dbh will I<commit> its pending changes rather than rolling
back after the indented block.
This “optimistic” approach may be appropriate in some contexts, but
in others it’s more useful that only an I<explicit> C<commit()> save the
pending changes.

This class implements that “pessimistic” approach: only an explicit
C<release()> will commit pending changes.

=head1 METHODS

=head2 I<CLASS>->new( $DBH )

Instantiates the class. $DBH is an ordinary SQLite DBI handle,
e.g., from L<Cpanel::DBI::SQLite>.

=cut

sub new ( $class, $dbh ) {

    # Please see above about not exposing this name publicly.
    my $name = "save_" . sprintf( '%x', substr( rand, 2 ) );

    $dbh->do("SAVEPOINT $name");

    return bless { _dbh => $dbh, _name => $name }, $class;
}

=head2 I<OBJ>->release()

Releases the object’s savepoint.

Nothing is returned.

=cut

sub release ($self) {
    $self->_ensure_not_released();

    $self->{'_dbh'}->do("RELEASE SAVEPOINT $self->{'_name'}");

    $self->{'_released'} = 1;

    return;
}

=head2 I<OBJ>->rollback()

Rolls back the savepoint. You can call this to avoid the warning
on failure when this object goes out of scope.

Nothing is returned.

=cut

sub rollback ($self) {
    $self->_ensure_not_released();

    $self->{'_dbh'}->do("ROLLBACK TO SAVEPOINT $self->{'_name'}");
    $self->release();

    return;
}

sub _ensure_not_released ($self) {
    die "$self: Already released!" if $self->{'_released'};

    return;
}

# For now don’t bother exposing a direct rollback() function.
# There’s no reason to create 2 ways of doing the same thing
# if a single method covers all use cases.
sub DESTROY ($self) {

    # NB: We do not check for a PID match here because SQLite
    # expects not to be used across a fork in the first place.

    if ( !$self->{'_released'} ) {
        warn "Rolling back unreleased SQLite savepoint!\n";

        $self->rollback();
    }

    return;
}

1;
