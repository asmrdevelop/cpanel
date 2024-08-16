package Cpanel::WebCalls::Datastore::Read;

# cpanel - Cpanel/WebCalls/Datastore/Read.pm       Copyright 2022 cPanel, L.L.C.
#                                                           All rights reserved.
# copyright@cpanel.net                                         http://cpanel.net
# This code is subject to the cPanel license. Unauthorized copying is prohibited

use cPstrict;

=encoding utf-8

=head1 NAME

Cpanel::WebCalls::Datastore::Read

=head1 SYNOPSIS

    my $entry = Cpanel::WebCalls::Datastore::Read->read_if_exists($id);

    if (Cpanel::WebCalls::Datastore::Read->user_owns_id('bob', $id)) {
        # …
    }

    my $username = Cpanel::WebCalls::Datastore::Read->get_username_for_id($id);

    my $id_entry = Cpanel::WebCalls::Datastore::Read->read_for_user('bob');

=head1 DESCRIPTION

This module provides read access to the cpsrvd webcalls datastore.

=head1 SEE ALSO

L<Cpanel::WebCalls::Datastore> contains an overview of the webcalls
datastore.

=cut

#----------------------------------------------------------------------

use parent 'Cpanel::WebCalls::Datastore';

use Cpanel::Autodie    ();
use Cpanel::LoadFile   ();
use Cpanel::LoadModule ();
use Cpanel::JSON       ();

#----------------------------------------------------------------------

=head1 CLASS METHODS

=head2 promise($locked_fh) = I<CLASS>->lock_p( %OPTS )

Creates a shared lock on the webcalls datastore.

Returns a promise whose resolution is a
L<Cpanel::FileUtils::Flock> instance. That object may be given
to L<Cpanel::WebCalls::Datastore::Write>’s constructor to upgrade
the lock to an exclusive lock when/if needed.

B<NOTE:> It is I<normally> not useful to call this method. See
L<Cpanel::WebCalls::Type> for an example of when it’s useful.

%OPTS are:

=over

=item * C<timeout> - optional; see L<Cpanel::WebCalls::Datastore::Write>’s
constructor’s documentation.

=back

=cut

sub lock_p ( $class, %opts ) {
    return $class->_get_lock_p( 'flock_SH', $opts{'timeout'} );
}

=head2 $entry_obj = I<CLASS>->read_if_exists( $ID )

Returns a L<Cpanel::WebCalls::Entry> object for $ID, or
undef if no such entry exists in the datastore.

=cut

sub read_if_exists ( $class, $id ) {
    my $path = $class->_index_dir() . "/$id";

    my $entry = Cpanel::LoadFile::load_if_exists($path);

    return $entry && do {
        require Cpanel::JSON;

        my $entry_hr = Cpanel::JSON::Load($entry);

        my $type = $entry_hr->{'type'} or do {
            die "Entry $id lacks a “type”!";
        };

        my $ns = Cpanel::LoadModule::load_perl_module("Cpanel::WebCalls::Entry::$type");

        $ns->adopt($entry_hr);
    };
}

#----------------------------------------------------------------------

=head2 $yn = I<CLASS>->user_owns_id( $USERNAME, $ID )

=cut

sub user_owns_id ( $class, $username, $id ) {
    my $user_dir = $class->_user_dir() . "/$username";

    my $index_dir = $class->_index_dir();

    my $owns_yn = Cpanel::Autodie::exists("$user_dir/$id");
    $owns_yn &&= Cpanel::Autodie::exists("$index_dir/$id");

    return $owns_yn;
}

#----------------------------------------------------------------------

=head2 $username = I<CLASS>->get_username_for_id( $ID )

Returns the username associated with $ID. Throws an exception
on failure to read the filesystem (including nonexistence of $ID).

=cut

sub get_username_for_id ( $class, $id ) {
    my $index_dir = $class->_index_dir();

    my $dest = Cpanel::Autodie::readlink("$index_dir/$id");

    my $slash_at = rindex( $dest, '/' );

    my $slash_at2 = rindex( $dest, '/', $slash_at - 1 );

    return substr( $dest, 1 + $slash_at2, $slash_at - $slash_at2 - 1 );
}

#----------------------------------------------------------------------

=head2 $id_entry_hr = I<CLASS>->read_for_user_and_type( $USERNAME, $TYPE )

Returns a reference to a hash that correlates IDs with
L<Cpanel::WebCalls::Entry> objects of a given $TYPE (e.g.,
C<DynamicDNS>).

=cut

sub read_for_user_and_type ( $class, $username, $type ) {
    die 'type is required!' if !length $type;

    return $class->_read_for_user_and_type( $username, $type );
}

#----------------------------------------------------------------------

=head2 I<CLASS>->for_each_of_type( $TYPE, $CALLBACK )

For each entry of type $TYPE, this runs
$CALLBACK->($ID, $ENTRY_OBJ, $ITERATOR). $ENTRY_OBJ is a
L<Cpanel::WebCalls::Entry> instance and $ITERATOR is a special object that
implements a C<stop()> method which will stop the iteration.

This is an inefficient operation since it will open, parse, and close every
entry in the datastore. A cache in front of this may be useful.

=cut

sub for_each_of_type ( $class, $type, $cb ) {
    my $index_dir = $class->_index_dir();

    if ( Cpanel::Autodie::opendir_if_exists( my $dh, $index_dir ) ) {
        my $stopped;
        my $iterator = bless \$stopped, 'Cpanel::WebCalls::Datastore::Read::Iterator';

        local $!;
        while ( my $node = readdir $dh ) {
            next if 0 == rindex( $node, '.', 0 );

            if ( my $entry_obj = $class->read_if_exists($node) ) {
                if ( $entry_obj->type() eq $type ) {
                    local $!;
                    $cb->( $node, $entry_obj, $iterator );
                    last if $stopped;
                }
            }
        }

        if ($!) {
            warn "readdir($index_dir): $!";
        }
    }

    return;
}

#----------------------------------------------------------------------

=head2 $id_entry_hr = I<CLASS>->read_for_user( $USERNAME )

Like C<read_for_user_and_type()> but imposes no type restriction.

This is probably best avoided/replaced.

=cut

sub read_for_user ( $class, $username ) {
    return $class->_read_for_user_and_type( $username, undef );
}

#----------------------------------------------------------------------

sub _read_for_user_and_type ( $class, $username, $type = undef ) {
    my $path = $class->_user_dir() . "/$username";

    my $index_dir = $class->_index_dir();

    local ( $@, $! );
    require Cpanel::FileUtils::Dir;
    my $nodes_ar = Cpanel::FileUtils::Dir::get_directory_nodes_if_exists($path);

    my %id_entry;

    if ($nodes_ar) {
        for my $id (@$nodes_ar) {

            # Ignore leading dot (e.g., “.deleted”).
            next if 0 == rindex( $id, '.', 0 );

            # It’s important that we fetch via the ID so that if for some
            # reason the user’s data is around but the ID isn’t we can
            # treat that state correctly as nonexistence of the node.
            if ( my $entry_obj = $class->read_if_exists($id) ) {
                next if defined($type) && $entry_obj->type() ne $type;

                $id_entry{$id} = $entry_obj;
            }
        }
    }

    return \%id_entry;
}

#----------------------------------------------------------------------

package Cpanel::WebCalls::Datastore::Read::Iterator;

sub stop ($self) {
    $$self = 1;
    return;
}

1;
