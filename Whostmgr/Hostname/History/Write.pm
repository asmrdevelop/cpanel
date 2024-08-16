package Whostmgr::Hostname::History::Write;

# cpanel - Whostmgr/Hostname/History/Write.pm     Copyright 2022 cPanel, L.L.C.
#                                                           All rights Reserved.
# copyright@cpanel.net                                         http://cpanel.net
# This code is subject to the cPanel license. Unauthorized copying is prohibited

use cPstrict;

=encoding utf-8

=head1 NAME

Whostmgr::Hostname::History::Write

=head1 SYNOPSIS

    use Whostmgr::Hostname::History::Write ();

    my $writer = Whostmgr::Hostname::History::Write->new();
    $writer->append("hostname.tld");
    $writer->save_or_die();
    $writer->close_or_die();

=head1 DESCRIPTION

This module implements read-write logic for interacting with
the hostname history.

=cut

use Cpanel::Hostname                ();
use Cpanel::Time::ISO               ();
use Cpanel::Transaction::File::JSON ();
use Cpanel::Validate::Hostname      ();
use Whostmgr::Hostname::History     ();

use Cpanel::Imports;

use constant {
    _FILE_PERMS  => 0600,
    _MAX_ENTRIES => 10,
};

=head1 METHODS

=head2 $obj = I<CLASS>->new()

Instantiates this class

=cut

sub new ($class) {
    return bless [ _get_rw_transaction() ], $class;
}

=head2 $ar = I<OBJ>->get_data()

Similar to L<Whostmgr::Hostname::History::Read>’s C<get()> function,
except this returns the current in-memory state of the datastore
rather than re-reading the data from disk.

=cut

sub get_data ($self) {
    my $data_ar = $self->[0]->get_data();
    return 'ARRAY' eq ref $data_ar ? $data_ar : [];
}

=head2 $obj = I<OBJ>->append($old_hostname)

Appends a hostname to the datastore. This does I<not> save
the data to diskl you’ll need to C<save_or_die()> for the data to
be persisted to disk.

In the event that the old hostname already exists in the datastore,
the timestamp is updated and is sorted to the end of the list.

=cut

sub append ( $self, $old_hostname ) {

    if ( $old_hostname eq Cpanel::Hostname::gethostname() ) {
        die "$self: Refuse to append() current hostname ($old_hostname)!";
    }

    # Sanity check the hostname just in case. This is mostly just for testing cases
    # where VMs are created with the VM name as the initial hostname but also protects
    # against cases where users may have altered their hostname outside of our
    # sethostname logic.
    if ( !Cpanel::Validate::Hostname::is_valid($old_hostname) ) {
        die locale()->maketext( "“[_1]” is not a valid hostname.", $old_hostname );
    }

    my $data_ar = $self->get_data();

    my $is_new = 1;

    for my $entry (@$data_ar) {
        if ( $entry->{old_hostname} eq $old_hostname ) {
            undef $is_new;
            $entry->{timestamp} = Cpanel::Time::ISO::unix2iso();
        }
    }

    if ($is_new) {
        push @$data_ar, { old_hostname => $old_hostname, timestamp => Cpanel::Time::ISO::unix2iso() };
    }
    else {
        $data_ar = [ sort { $a->{timestamp} cmp $b->{timestamp} } @$data_ar ];
    }

    if ( @$data_ar > _MAX_ENTRIES ) {
        $data_ar = [ @{$data_ar}[ 1 .. _MAX_ENTRIES ] ];
    }

    $self->[0]->set_data($data_ar);

    return $self;
}

=head2 $obj = I<OBJ>->save_or_die()

Writes I<OBJ>’s contents to disk. This does I<not> release the lock
on the datastore, so this can be called multiple times over I<OBJ>’s
lifetime.

=cut

sub save_or_die ($self) {
    $self->[0]->save_or_die();
    return $self;
}

=head2 $obj = I<OBJ>->close_or_die()

Closes the datastore. This releases the lock
on the datastore, so this can only be called once during I<OBJ>’s
lifetime.

=cut

sub close_or_die ($self) {
    $self->[0]->close_or_die();
    return;
}

sub _get_rw_transaction() {
    return Cpanel::Transaction::File::JSON->new(
        path        => Whostmgr::Hostname::History::file(),
        permissions => _FILE_PERMS,
    );
}

1;
