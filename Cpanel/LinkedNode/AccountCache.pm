package Cpanel::LinkedNode::AccountCache;

# cpanel - Cpanel/LinkedNode/AccountCache.pm       Copyright 2022 cPanel, L.L.C.
#                                                           All rights reserved.
# copyright@cpanel.net                                         http://cpanel.net
# This code is subject to the cPanel license. Unauthorized copying is prohibited

use cPstrict;

=encoding utf-8

=head1 NAME

Cpanel::LinkedNode::AccountCache

=head1 SYNOPSIS

Reading the cache:

    my $p = Cpanel::LinkedNode::AccountCache->new_p()->then( sub ($self) {

        # How many distributed accounts are there?
        my $count = $self->get_usernames_ar()->@*;

        # Is “bobby” a Mail child account?
        my $child_workloads_ar = $self->get_all_child_workloads()->{'bobby'};
        if ( grep { $_ eq 'Mail' } @$child_workloads_ar ) {
            # ...
        }

        # Does “bob” distribute Mail?
        my $type_alias_hr = $self->get_all_parent_data()->{'bobby'};
        if ( my $alias = $type_alias_hr && $type_alias_hr->{'Mail'} ) {
            # ...
        }
    } );

    Cpanel::PromiseUtils::wait_anyevent($p);

Updating the cache:

    my $p = Cpanel::LinkedNode::AccountCache->new_p()->then( sub ($self) {
        # Updating a user in the cache:
        $self->sync_cpuser();

        # See below for how to reset/empty the entire cache.

        return $self->save_p();
    } );

    Cpanel::PromiseUtils::wait_anyevent($p);

=head1 DESCRIPTION

This class implements an interface to an on-disk cache of distributed-account
data. This cache is accessible to root only.

=head1 WHAT’S IN HERE, AND WHAT’S NOT

This interface includes lookups for all users. It omits per-user lookups
because it’s better to do those in the cpuser file.

=head1 RACE SAFETY

Instances of this class start out holding a shared lock on the datastore.
That lock is upgraded to an exclusive lock prior to writing to the disk
then downgraded back to shared. This preserves race safety while
allowing concurrent reads.

=cut

#----------------------------------------------------------------------

use parent 'Cpanel::Destruct::DestroyDetector';

use Try::Tiny;

use Cpanel::Context         ();
use Cpanel::JSON            ();
use Cpanel::LoadFile        ();
use Cpanel::Async::EasyLock ();

my $_ENOENT = 2;

our $_PATH = '/var/cpanel/distributed_accounts_cache.json';

use constant _LOCK_NAME => __PACKAGE__;

#----------------------------------------------------------------------

=head1 GENERAL AND READ METHODS

The following don’t alter the datastore:

=head2 promise($obj) = I<CLASS>->new_p()

Returns a promise that resolves to an instance of I<CLASS>.

=cut

sub new_p ($class) {
    return Cpanel::Async::EasyLock::lock_shared_p(_LOCK_NAME)->then(
        sub ($handle) {
            my $self = bless { _lock => $handle }, $class;

            return $self->_open_db();
        }
    );
}

sub _rebuild_p ($self) {
    require Cpanel::LinkedNode::AccountCache::Rebuild;

    return Cpanel::LinkedNode::AccountCache::Rebuild::rebuild_p($self)->then(
        sub {
            $self->_open_db();
        },
    );
}

sub _open_db ($self) {
    my $data = Cpanel::LoadFile::load_if_exists($_PATH);

    if ( length $data ) {
        try {
            $data = Cpanel::JSON::Load($data);
        }
        catch {
            warn "Failed to parse $_PATH ($_); will rebuild …\n";

            $data = undef;
        };
    }

    if ($data) {
        $self->{'_data'} = $data;
        return $self;
    }

    # Rebuilding the cache when it’s missing isn’t something
    # we’ll consider an error state.
    return $self->_rebuild_p();
}

=head2 $user_$type_alias_hr = I<OBJ>->get_all_parent_data()

This returns all parent accounts’ cached data, in a reference to a deep
hash.

Return CDDL:

    {* username => {* workload => alias } }

=cut

sub get_all_parent_data ($self) {
    return $self->{'_data'}{'parent'} ||= {};
}

=head2 $child_workloads_ar = I<OBJ>->get_all_child_workloads()

This returns all child accounts’ workloads, in a reference to a deep
hash.

Return CDDL:

    {* username => [* workload ] } }

=cut

sub get_all_child_workloads ($self) {
    return $self->{'_data'}{'child'} ||= {};
}

#----------------------------------------------------------------------

=head1 WRITE METHODS

The following alter the datastore:

=head2 I<OBJ>->set_user_parent_data( $USERNAME, @WORKLOAD_ALIAS_PAIRS )

This method sets an individual user’s parent data. @WORKLOAD_ALIAS_PAIRS
are, e.g., (C<Mail> => C<thealias>, …).

=cut

sub set_user_parent_data ( $self, $username, @workload_alias_pairs ) {
    die 'Give at least 1 pair!' if !@workload_alias_pairs;
    die 'Must give pairs!'      if ( @workload_alias_pairs % 2 );

    $self->{'_data'}{'parent'}{$username} = {@workload_alias_pairs};

    $self->{'_has_pending_changes'} = 1;

    return;
}

=head2 I<OBJ>->set_user_child_workloads( $USERNAME, @WORKLOADS )

This method sets an individual user’s child workloads (e.g., C<Mail>, …).

=cut

sub set_user_child_workloads ( $self, $username, @workloads ) {
    die 'Give at least 1 workload!' if !@workloads;

    $self->{'_data'}{'child'}{$username} = \@workloads;

    $self->{'_has_pending_changes'} = 1;

    return;
}

=head2 I<OBJ>->unset_user_child_workloads( $USERNAME )

This method sets an individual user to have no child workloads.

=cut

sub unset_user_child_workloads ( $self, $username ) {
    delete $self->{'_data'}{'child'}{$username};

    $self->{'_has_pending_changes'} = 1;

    return;
}

=head2 $needs_save_yn = I<OBJ>->remove_cpuser( $USERNAME )

Removes a user from the cache. Returns a boolean that indicates whether
the datastore needs to be saved.

=cut

sub remove_cpuser ( $self, $username ) {
    Cpanel::Context::must_not_be_void();

    my $need_save;

    $need_save = 1 if delete $self->{'_data'}{'child'}{$username};
    $need_save = 1 if delete $self->{'_data'}{'parent'}{$username};

    $self->{'_has_pending_changes'} ||= $need_save;

    return $need_save || 0;
}

=head2 I<OBJ>->rename_cpuser( $OLDNAME => $NEWNAME )

Removes a user from the cache. Warns if $OLDNAME does not exist in the
datastore.

Returns nothing. C<save_p()> B<MUST> be called after this method to
save the changes.

=cut

sub rename_cpuser ( $self, $oldname, $newname ) {
    my $need_save;

    for my $type (qw( child parent )) {
        if ( my $data = delete $self->{'_data'}{$type}{$oldname} ) {
            $self->{'_data'}{$type}{$newname} = $data;

            $need_save = 1;
        }
    }

    if ( !$need_save ) {
        warn "$self: Tried to rename nonexistent user “$oldname”!\n";
    }

    $self->{'_has_pending_changes'} = 1;

    return;
}

=head2 $needs_save_yn = I<OBJ>->reset()

Empties I<OBJ>’s contents. Returns a boolean that indicates whether
the datastore needs to be saved.

=cut

sub reset ($self) {
    Cpanel::Context::must_not_be_void();

    $self->{'_has_pending_changes'} = !$self->{'_data'} || %{ $self->{'_data'} };

    $self->{'_data'} = {};

    return $self->{'_has_pending_changes'} ? 1 : 0;
}

=head2 promise() = I<OBJ>->save_p()

Writes the datastore contents to disk.

Returns a promise that resolves (to nothing) when the write is
complete.

=cut

sub save_p ($self) {
    Cpanel::Context::must_not_be_void();

    my $p;

    if ( $self->{'_has_pending_changes'} ) {
        my $handle = $self->{'_lock'};

        local ( $@, $! );
        require Cpanel::Data::Result;
        require Cpanel::FileUtils::Write;

        # The only critical failures below are:
        #   a) failure to upgrade to an exclusive lock
        #   b) failure to write the new file

        return $handle->relock_exclusive_p()->then(
            sub {
                my $result = Cpanel::Data::Result::try(
                    sub {
                        my $json = Cpanel::JSON::Dump( $self->{'_data'} );

                        Cpanel::FileUtils::Write::overwrite( $_PATH, $json, 0600 );

                        $self->{'_has_pending_changes'} = 0;
                    }
                );

                # We do have to wait for the lock to be downgraded to
                # a shared lock, but if that downgrade somehow fails—can
                # that even happen?—then just warn about it.

                return $handle->relock_shared_p()->catch(
                    sub ($why) {
                        warn $why;
                    }
                )->then(
                    sub {
                        $result->get();
                    }
                );
            },
        );
    }
    else {
        $p = Promise::XS::resolved();
    }

    return $p;
}

sub DESTROY ($self) {
    if ( $self->{'_has_pending_changes'} ) {
        warn "$self: DESTROYed with unsaved changes!\n";
    }

    return;
}

1;
