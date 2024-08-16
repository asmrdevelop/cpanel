package Cpanel::WebCalls::Datastore::Write;

# cpanel - Cpanel/WebCalls/Datastore/Write.pm      Copyright 2022 cPanel, L.L.C.
#                                                           All rights reserved.
# copyright@cpanel.net                                         http://cpanel.net
# This code is subject to the cPanel license. Unauthorized copying is prohibited

use cPstrict;

=encoding utf-8

=head1 NAME

Cpanel::WebCalls::Datastore::Write

=head1 SYNOPSIS

    use Cpanel::PromiseUtils               ();
    use Cpanel::WebCalls::Datastore::Write ();

    # Wait up to 30 seconds for the lock.
    my $calls_p = Cpanel::WebCalls::Datastore::Write->new_p(
        timeout => 30,
    );

    my $promise = $calls_p->then( sub ($calls_obj) {
        $calls_obj->create_for_user(
            'bob',
            'DynamicDNS',
            { domain: "home.bobs-stuff.com" },
        );

        $calls_obj->delete( 'abds8843hjkwer01bxsd23lhj678xaqwzzp32' );
    } );

    Cpanel::PromiseUtils::wait_anyevent($promise)->get();

=head1 DESCRIPTION

This module provides write access to the cpsrvd webcalls datastore.

=head1 SEE ALSO

L<Cpanel::WebCalls::Datastore> contains an overview of the webcalls
datastore.

=cut

# handy one-liner:
# perl -Mstrict -w -MCpanel::PromiseUtils -MCpanel::WebCalls::Datastore::Write -e'my $obj = Cpanel::PromiseUtils::wait_anyevent( Cpanel::WebCalls::Datastore::Write->new_p( timeout => 30) )->get();'

#----------------------------------------------------------------------

use parent (
    'Cpanel::WebCalls::Datastore',
    'Cpanel::Destruct::DestroyDetector',
);

use Promise::XS ();

use Cpanel::Autodie ( 'rename_if_exists', 'rename' );

use Cpanel::Autowarn                     ();
use Cpanel::Context                      ();
use Cpanel::Exception                    ();
use Cpanel::JSON                         ();
use Cpanel::FileUtils::Write             ();
use Cpanel::LoadModule                   ();
use Cpanel::CommandQueue                 ();
use Cpanel::Time::ISO                    ();
use Cpanel::Validate::FilesystemNodeName ();

use Cpanel::WebCalls::Constants ();    # PPI NO PARSE - mis-parse
use Cpanel::WebCalls::ID        ();

my $_DIR_PERMS = 0700;

#----------------------------------------------------------------------

=head1 METHODS

=head2 promise($obj) = I<CLASS>->new_p(%OPTS)

Instantiates the class. This locks the datastore so that no other
process can update it.

%OPTS are:

=over

=item * C<timeout> - optional; a number of seconds to wait to lock the
datastore. If not given, no waiting is done, and timeout happens if the
initial lock attempt indicates EAGAIN.

=item * C<fh> - optional; an existing L<Cpanel::FileUtils::Flock>
object to convert. Useful for upgrading a shared lock to an exclusive
lock.

=back

The return is a promise whose resolution is an instance of this class.
On timeout, the promise rejects with a L<Cpanel::Exception::Timeout>
instance.

=cut

sub new_p ( $class, %opts ) {
    return $class->_get_lock_p( 'flock_EX', @opts{ 'timeout', 'fh' } )->then(
        sub ($fh) {
            return bless { _lock => $fh }, $class;
        }
    );
}

=head2 I<OBJ>->purge_user( $USERNAME )

Removes $USERNAME from the datastore completely.

Deleting the user’s individual entries isn’t necessarily the same
thing insofar as the storage details; use this method when all
traces of the user should be removed from the datastore (e.g.,
deleting the user’s account).

=cut

sub purge_user ( $self, $username ) {
    my $user_dir  = $self->_user_dir() . "/$username";
    my $index_dir = $self->_index_dir();

    my $id_entry_hr = _reader_ns()->read_for_user($username);

    my %type_id_entries;

    for my $id ( keys %$id_entry_hr ) {
        my $entry = $id_entry_hr->{$id};

        push @{ $type_id_entries{ $entry->type() } }, $id => $entry;
    }

    my %type_updater;

    for my $type ( keys %type_id_entries ) {
        if ( $type_updater{$type} = _get_updater($type) ) {
            my $ids_entries_ar = $type_id_entries{$type};

            $type_updater{$type}->remove($ids_entries_ar);
        }
    }

    for my $id ( keys %$id_entry_hr ) {
        Cpanel::Autowarn::unlink("$user_dir/$id");
        Cpanel::Autowarn::unlink("$index_dir/$id");

        # NB: We do *NOT* fire on_post_delete() here because we assume that
        # the user is being deleted anyway. If we need a cleanup action it
        # should probably happen via a separate hook.
    }

    warn "rmdir($user_dir): $!" if !eval {
        Cpanel::Autodie::rmdir_if_exists($user_dir);
        1;
    };

    $_ && $_->finish() for values %type_updater;

    return;
}

sub _get_type_ns ($type) {
    return Cpanel::LoadModule::load_perl_module("Cpanel::WebCalls::Type::$type");
}

sub _get_entry_ns ($type) {
    return Cpanel::LoadModule::load_perl_module("Cpanel::WebCalls::Entry::$type");
}

sub _get_updater ($type) {
    my $ns = _get_type_ns($type);
    return $ns->create_updater();
}

=head2 I<OBJ>->delete_for_user( $USERNAME, $ID )

Deletes a single entry for $USERNAME, referenced by $ID.

Returns a L<Cpanel::WebCalls::Entry> object for the deleted entry
if an entry was deleted, or undef if there was no such entry
to delete.

See C<purge_user()> if you want to delete the user entirely from
the datastore.

B<IMPORTANT!!> This does B<not> validate that $USERNAME owns $ID.

=cut

sub delete_for_user ( $self, $username, $id ) {

    my $entry_obj = $self->_delete_for_user_without_post_delete_hook( $username, $id );

    if ($entry_obj) {
        _get_type_ns( $entry_obj->type() )->on_post_delete($entry_obj);
    }

    return $entry_obj;
}

sub _delete_for_user_without_post_delete_hook ( $self, $username, $id ) {
    my $user_dir  = $self->_user_dir() . "/$username";
    my $index_dir = $self->_index_dir();

    my $entry_obj = _reader_ns()->read_if_exists($id);

    if ($entry_obj) {
        my $updater = _get_updater( $entry_obj->type() );

        $updater && $updater->remove( [ $id => $entry_obj ] );

        # We delete the symlink first; once that happens we can
        # directly remove the user-directory file.
        # It’s safe to use unlink() here in lieu of unlink_if_exists()
        # because read_if_exists() confirmed that the entry exists.
        Cpanel::Autodie::unlink("$index_dir/$id");

        # We might as well remove the file, even if !$exists.
        Cpanel::Autowarn::unlink("$user_dir/$id");

        $updater && $updater->finish();
    }

    return $entry_obj;
}

#----------------------------------------------------------------------

=head2 I<OBJ>->save_run_time( $ID )

Records the current time as a run time (but not an update time).

=cut

sub save_run_time ( $self, $id ) {
    return $self->_save_run_time($id);
}

sub _save_run_time ( $self, $id, $also_cr = undef ) {
    my $path = $self->_index_dir();

    my $data_hr = Cpanel::JSON::LoadFile("$path/$id");

    my $mod_times_ar = $data_hr->{'last_run_times'};

    my $new_time = Cpanel::Time::ISO::unix2iso();

    push @{$mod_times_ar}, $new_time;

    my $extras = @{$mod_times_ar} - Cpanel::WebCalls::Constants::RATE_LIMIT_ALLOWANCE;

    if ( $extras > 0 ) {
        splice @{$mod_times_ar}, 0, $extras;
    }

    $also_cr->( $data_hr, $new_time ) if $also_cr;

    $self->_write_entry( $id, $data_hr );

    return;
}

=head2 I<OBJ>->save_update_time( $ID )

Like C<save_run_time()> but records the current time as a run time
B<AND> the last-update time.

=cut

sub save_update_time ( $self, $id ) {
    return $self->_save_run_time(
        $id,
        sub ( $data_hr, $new_time ) {
            $data_hr->{'last_update_time'} = $new_time;
        },
    );
}

#----------------------------------------------------------------------

=head2 ($id, $create_time) = I<OBJ>->create_for_user( $USERNAME, $TYPE, $DATA )

Creates a new entry of type $TYPE in the datastore for $USERNAME.

$DATA is whatever $TYPE needs it to be. For example, the C<DynamicDNS> type’s
requirements are defined in L<Cpanel::WebCalls::Type::DynamicDNS>.

Returns the ID of the new entry and its creation time, as an RFC 3339
“Zulu time” date.

=cut

sub create_for_user ( $self, $username, $type, $data ) {
    Cpanel::Context::must_be_list();

    my $ns = $self->_type_namespace($type);

    $ns->normalize_entry_data( $username, $data );

    if ( my $why = $ns->why_entry_data_invalid( $username, $data ) ) {
        die Cpanel::Exception::create_raw( 'InvalidParameter', $why );
    }

    my $created_time = Cpanel::Time::ISO::unix2iso();

    my $data_hr = {
        type             => $type,
        data             => $data,
        created_time     => $created_time,
        last_run_times   => [],
        last_update_time => undef,
    };

    my $id = _create_id();

    my $updater = _get_updater($type);

    $self->_write_new_entry( $username, $id, $data_hr );

    my $entry_obj = _get_entry_ns($type)->adopt($data_hr);

    if ($updater) {
        $updater->add( [ $id => $entry_obj ] );
        $updater->finish();
    }

    return ( $id, $created_time );
}

sub _write_new_entry ( $self, $username, $id, $data_hr ) {
    my $data_json = Cpanel::JSON::Dump($data_hr);

    my $per_user_dir = $self->_user_dir();
    my $index_dir    = $self->_index_dir();

    for my $dir ( $index_dir, $per_user_dir, "$per_user_dir/$username" ) {
        Cpanel::Autodie::mkdir_if_not_exists( $dir, $_DIR_PERMS );
    }

    my $cq = Cpanel::CommandQueue->new();

    my $user_data_file = "$per_user_dir/$username/$id";

    $cq->add(
        sub {
            Cpanel::FileUtils::Write::write( $user_data_file, $data_json );
        },
        sub {
            Cpanel::Autowarn::unlink($user_data_file);
        },
        'unlink full data',
    );

    $cq->add(
        sub {
            Cpanel::Autodie::symlink(
                "../user/$username/$id",
                "$index_dir/$id",
            );
        },
    );

    $cq->run();

    return;
}

#----------------------------------------------------------------------

=head2 I<OBJ>->import_for_user( $USERNAME, \@IMPORTS )

Like C<create_for_user()> but used for restoring an entry.

B<IMPORTANT:> You B<MUST> validate I<before> calling this method.

Each member of @IMPORTS is:

    [ $TYPE, $ID, \%DATA ]

… where %DATA B<MUST> be:

=over

=item * C<created_time>

=item * C<last_run_times> - array ref

=item * C<last_update_time> - optional

=item * C<data> - hashref, as per the $TYPE

=back

All times are in the same format that C<create_for_user()> returns.

=cut

sub import_for_user ( $self, $username, $imports_ar ) {
    my %type_updater;

    for my $import_ar (@$imports_ar) {
        my ( $type, $id, $item ) = @$import_ar;

        # We need to create this *before* the on-disk update happens:
        $type_updater{$type} ||= _get_updater($type);

        my %data = (
            type => $type,
            %{$item}{ 'data', 'created_time', 'last_run_times', 'last_update_time' },
        );

        $self->_write_new_entry( $username, $id, \%data );

        if ( my $updater = $type_updater{$type} ) {
            my $entry_obj = _get_entry_ns($type)->adopt( \%data );
            $updater->add( [ $id => $entry_obj ] );
        }
    }

    $_ && $_->finish() for values %type_updater;

    return;
}

#----------------------------------------------------------------------

=head2 $new_id = I<OBJ>->recreate_for_user( $USERNAME, $OLD_ID )

Recreates an entry with a different ID. Everything else about the entry
stays the same.

=cut

sub recreate_for_user ( $self, $username, $id ) {
    my $per_user_dir = $self->_user_dir();
    my $index_dir    = $self->_index_dir();

    my $new_id = _create_id();

    my $data_file     = "$per_user_dir/$username/$id";
    my $new_data_file = "$per_user_dir/$username/$new_id";

    my $entry_obj = _reader_ns()->read_if_exists($id);

    my $updater = $entry_obj && _get_updater( $entry_obj->type() );

    my $cq = Cpanel::CommandQueue->new();

    $cq->add(
        sub {
            Cpanel::Autodie::link( $data_file => $new_data_file );
        },
        sub {
            Cpanel::Autowarn::unlink($new_data_file);
        },
        'unlink new user link',
    );

    $cq->add(
        sub {
            Cpanel::Autodie::symlink(
                "../user/$username/$new_id",
                "$index_dir/$new_id",
            );
        },
        sub {
            Cpanel::Autowarn::unlink("$index_dir/$new_id");
        },
        'unlink new symlink',
    );

    $cq->add(
        sub { $self->_delete_for_user_without_post_delete_hook( $username, $id ) },
    );

    $cq->run();

    if ($updater) {
        $updater->update(
            $id     => $entry_obj,
            $new_id => $entry_obj,
        );

        $updater->finish();
    }

    return $new_id;
}

=head2 I<OBJ>->update_data( $USERNAME, $ID, $ORIGINAL_DATA_REF, $NEW_DATA_REF )

Updates a given entry’s data. To protect against TOCTTOU errors,
the $ORIGINAL_DATA_REF must be given along with $NEW_DATA_REF; an exception
is thrown if the existing data mismatches $ORIGINAL_DATA_REF.

=cut

sub update_data ( $self, $username, $id, $original_data_ref, $new_data_ref ) {    ## no critic qw(Subroutines::ProhibitManyArgs) adding prohibit due to bug with signatures

    my $path = $self->_index_dir();

    my $entry_hr = Cpanel::JSON::LoadFile("$path/$id");
    my $type     = $entry_hr->{type};

    my $ns = $self->_type_namespace($type);

    if ( my $why = $ns->why_update_data_invalid( $username, $new_data_ref ) ) {
        die Cpanel::Exception::create_raw( 'InvalidParameter', $why );
    }

    # Prevent race conditions where the data may have changed between the time
    # a caller retrieved it for updating and the time that we acquired the lock
    # to update the data.
    if ( !$ns->is_data_equal( $entry_hr->{'data'}, $original_data_ref ) ) {
        die Cpanel::Exception::create( 'InvalidParameter', "Entry “[_1]” mismatches the given original state. Please recheck your submission, and try again.", [$id] );
    }

    $entry_hr->{'data'} = $ns->merge_data( $original_data_ref, $new_data_ref );

    $self->_write_entry( $id, $entry_hr );

    return;
}

sub _write_entry ( $self, $id, $entry_hr ) {

    my $path = $self->_index_dir();

    require Cwd;
    my $abs_path = Cwd::abs_path("$path/$id");

    Cpanel::FileUtils::Write::overwrite(
        $abs_path,
        Cpanel::JSON::Dump($entry_hr),
    );

    return;
}

#----------------------------------------------------------------------

=head2 I<OBJ>->rename_user( $OLDNAME, $NEWNAME )

Renames a user in the datastore. Returns nothing.

=cut

sub rename_user ( $self, $oldname, $newname ) {

    my $per_user_dir = $self->_user_dir();
    my $index_dir    = $self->_index_dir();

    my $cq = Cpanel::CommandQueue->new();

    my $olddir = "$per_user_dir/$oldname";
    my $newdir = "$per_user_dir/$newname";

    #----------------------------------------------------------------------
    # Ensure (as best as possible) that no entries are broken at any time.
    #----------------------------------------------------------------------

    if ( Cpanel::Autodie::opendir_if_exists( my $dh, $olddir ) ) {
        local ( $@, $! );
        require File::Path;
        require Cpanel::FileUtils::WriteLink;

        # 1. Create the directory.

        $cq->add(
            sub {
                Cpanel::Autodie::mkdir( $newdir, $_DIR_PERMS );
            },
            sub {
                File::Path::remove_tree($newdir);
            },
            'remove new user dir',
        );

        while ( my $node = readdir $dh ) {
            local $!;

            # Skip anything invalid; assume it’s just cruft.
            next if !Cpanel::WebCalls::ID::is_valid($node);

            # 2. For each entry, hard-link the file to the new username’s
            # directory. Then, create a symlink to install into the index
            # directory.

            $cq->add(
                sub {
                    Cpanel::Autodie::link( "$olddir/$node", "$newdir/$node" );
                  },

                # Let File::Path clean this up for us.
            );

            # 3. Now install that entry’s index directory symlink.

            $cq->add(
                sub {
                    Cpanel::FileUtils::WriteLink::overwrite(
                        "../user/$newname/$node",
                        "$index_dir/$node",
                    );
                },

                sub {

                    # Undo means reversion of the symlink destination change:
                    Cpanel::FileUtils::WriteLink::overwrite(
                        "../user/$oldname/$node",
                        "$index_dir/$node",
                    );
                },

                "$node: reactivate old link",
            );
        }

        die "readdir($olddir): $!" if $!;

        $cq->run();

        eval { File::Path::remove_tree($olddir); 1 } or do {
            warn "removing $olddir: $@";
        };
    }

    return;
}

#----------------------------------------------------------------------

=head2 I<OBJ>->update_user_entries_data( $USERNAME, $FOREACH_CR )

Iterates through each of $USERNAME’s entries, calling $FOREACH_CR
for each entry. Each such invocation receives two parameters:
a L<Cpanel::WebCalls::Entry> instance for the entry, and a
callback that sets a new C<data> reference for the entry.

Returns nothing.

=cut

sub update_user_entries_data ( $self, $username, $foreach_cr ) {

    # A sanity-check:
    Cpanel::Validate::FilesystemNodeName::validate_or_die($username);

    my $id_entry_hr = _reader_ns()->read_for_user($username);

    # Enqueue the updates to minimize the chance of partial successes.
    my %updates;

    my $per_user_dir = $self->_user_dir();

    my %type_updater;

    for my $id ( keys %$id_entry_hr ) {
        my $entry_obj = $id_entry_hr->{$id};

        my $entry_type = $entry_obj->type();

        my $entry_ns  = _get_entry_ns($entry_type);
        my $old_clone = $entry_ns->adopt(
            Cpanel::JSON::Load( Cpanel::JSON::Dump($entry_obj) ),
        );

        my $new_sr;
        $foreach_cr->(
            $entry_obj,

            sub ($newdata) { $new_sr = \$newdata; () },
        );

        if ($new_sr) {
            my %data = (
                %$entry_obj,
                data => $$new_sr,
            );

            # Serialize up-front to ensure that all new data
            # is serializable before we change system state.
            $updates{$id} = Cpanel::JSON::Dump( \%data );

            my $new_entry_obj = $entry_ns->adopt( \%data );

            # We need to create this *before* the on-disk update happens:
            $type_updater{$entry_type} ||= _get_updater($entry_type);

            if ( my $this_type_updater = $type_updater{$entry_type} ) {
                $this_type_updater->update(
                    $id => $old_clone,
                    $id => $new_entry_obj,
                );
            }
        }
    }

    for my $id ( keys %updates ) {
        my $data_file = "$per_user_dir/$username/$id";
        Cpanel::FileUtils::Write::overwrite( $data_file, $updates{$id} );
    }

    $_ && $_->finish() for values %type_updater;

    return;
}

#----------------------------------------------------------------------

sub _reader_ns {
    local ( $@, $! );
    require Cpanel::WebCalls::Datastore::Read;    ## PPI NO PARSE - used dynamically
    return 'Cpanel::WebCalls::Datastore::Read';
}

sub _create_id {
    return Cpanel::WebCalls::ID::create();
}

1;
