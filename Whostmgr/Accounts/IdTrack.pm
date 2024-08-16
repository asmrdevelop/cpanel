package Whostmgr::Accounts::IdTrack;

# cpanel - Whostmgr/Accounts/IdTrack.pm            Copyright 2022 cPanel, L.L.C.
#                                                           All rights reserved.
# copyright@cpanel.net                                         http://cpanel.net
# This code is subject to the cPanel license. Unauthorized copying is prohibited

use strict;
use warnings;

use AcctLock;

use Cpanel::AdminBin::Serializer         ();
use Cpanel::AdminBin::Serializer::FailOK ();
use Cpanel::FileUtils::Write             ();
use Cpanel::LoginDefs                    ();
use Cpanel::PwCache::Map                 ();

our $DB_FILE = '/var/cpanel/usedids.db';

sub _load_uids_gids_from_passwd {
    my $used_ref = shift;

    foreach my $ref (
        [ 'passwd', 'uids' ],
        [ 'group',  'gids' ],
    ) {
        my ( $file, $used_key ) = @{$ref};
        my $user_uid_map_ref = Cpanel::PwCache::Map::get_name_id_map($file);
        @{ $used_ref->{$used_key} }{ values %$user_uid_map_ref } = (1) x scalar values %$user_uid_map_ref;
    }

    return;
}

# See POD for warning.
sub build_db {
    my %USED;
    _load_uids_gids_from_passwd( \%USED );
    _save( \%USED );

    # Usage is safe as we own /var/cpanel and the dir
    return \%USED;
}

sub _save {

    # We don’t lock here because we assume there is already an
    # AcctLock in place. If that assumption is wrong we want to
    # complain loudly.
    if ( !AcctLock::is_locked() ) {
        require Carp;
        Carp::confess('Tried to save without AcctLock!');
    }

    return Cpanel::FileUtils::Write::overwrite( $DB_FILE, Cpanel::AdminBin::Serializer::Dump( $_[0] ), 0644 );
}

sub _load_datastore {
    return ( Cpanel::AdminBin::Serializer::FailOK::LoadFile($DB_FILE) || Cpanel::AdminBin::Serializer::FailOK::LoadFile("$DB_FILE.cache") || build_db() );
}

sub allocate {    ## no critic qw(Subroutines::ProhibitExcessComplexity)
    my ($opts) = @_;

    my $used_ref = _load_datastore();

    _load_uids_gids_from_passwd($used_ref);

    my $minuid = $opts->{'minuid'};
    my $mingid = $opts->{'mingid'};

    my ( $logindefs_uid_min, $logindefs_sys_uid_min, $logindefs_gid_min, $logindefs_sys_gid_min ) = Cpanel::LoginDefs::get_uid_gid_sys_min();

    if ( !$minuid || $minuid !~ m/\A\d+\z/ ) {
        $minuid = $logindefs_uid_min;
    }
    if ( $minuid < $logindefs_sys_uid_min ) {
        $minuid = $logindefs_sys_uid_min;
    }
    if ( !$mingid || $mingid !~ m/\A\d+\z/ ) {
        $mingid = $logindefs_uid_min;
    }
    if ( $mingid < $logindefs_sys_gid_min ) {
        $mingid = $logindefs_sys_gid_min;
    }

    my $updated_used_ids;
    my $uid = $opts->{'uid'};
    my $gid = $opts->{'gid'};
    if ($uid) {
        return ( 0, "Invalid uid supplied" ) if $uid !~ m/^[0-9]+$/;
        my $uid_has_disk_usage;
        local $@;
        eval { $uid_has_disk_usage = uid_has_disk_usage($uid) };
        if ($@) {
            return ( 0, "The system failed to determine if the requested uid ($uid) is already in use because of an error: $@", -1, -1 );
        }
        if ( $uid_has_disk_usage || ( getpwuid($uid) )[0] ) {
            return ( 0, "The requested uid ($uid) is already in use", -1, -1 );
        }
    }
    if ($gid) {
        return ( 0, "Invalid gid supplied" ) if $gid !~ m/^[0-9]+$/;
        if ( ( getgrgid($gid) )[0] ) {
            return ( 0, "The requested gid ($gid) is already in use", -1, -1 );
        }
    }

    if ( !$uid || !$gid ) {
        my $maxuid       = Cpanel::LoginDefs::get_uid_max();
        my $used_uids_hr = $used_ref->{'uids'};
        my $used_gids_hr = $used_ref->{'gids'};

        local $@;

        # NB: This is a heavily-optimized loop where even tiny
        # optimizations can make an appreciable difference.
        foreach my $test_uid ( $minuid .. $maxuid ) {
            if ( !$uid && !exists $used_uids_hr->{$test_uid} ) {
                my $uid_has_disk_usage;
                eval { $uid_has_disk_usage = uid_has_disk_usage($test_uid) };
                if ($@) {
                    return ( 0, "The system failed to allocate a user id because of an error: $@" );
                }
                if ($uid_has_disk_usage) {
                    $used_uids_hr->{$test_uid} = 1;
                    $updated_used_ids++;
                }
                else {
                    $uid = $test_uid;
                    last if $gid;    # We just got a valid uid and if we already have a gid we are done
                }
            }
            if ( !$gid && !exists $used_gids_hr->{$test_uid} && $test_uid >= $mingid ) {
                $gid = $test_uid;
                last if $uid;        # We just got a valid gid and if we already have a uid we are done
            }
        }
    }

    if ( !$uid ) {

        # Usage is safe as we own /var/cpanel and the dir
        _save($used_ref) if $updated_used_ids;
        return ( 0, 'Could not allocate a user id.  Please remove /var/cpanel/usedids.* if you are sure it is safe to reallocate uids.' );
    }
    if ( !$gid ) {

        # Usage is safe as we own /var/cpanel and the dir
        _save($used_ref) if $updated_used_ids;
        return ( 0, 'Could not allocate a group id.  Please remove /var/cpanel/usedids.* if you are sure it is safe to reallocate gids.' );
    }

    # Store results
    $used_ref->{'uids'}{$uid} = 1;
    $used_ref->{'gids'}{$gid} = 1;

    # Usage is safe as we own /var/cpanel and the dir
    _save($used_ref);

    return ( 1, 'Allocated uid & gid', $uid, $gid );
}

sub uid_has_disk_usage {
    my ($uid) = @_;

    require Cpanel::Quota::Common;
    my $blocks_module = Cpanel::Quota::Common->new( { user => $uid } );

    # We have no way of telling if the uid has disk usage
    # if quotas are not enabled
    return 0 if !$blocks_module->quotas_are_enabled();

    my $limits = $blocks_module->get_limits();

    require Cpanel::Quota::Utils;
    return Cpanel::Quota::Utils::has_usage($limits);

}

# See POD for warning.
sub remove_id {
    my %opts = @_;

    return ( 0, 'No uid or gid supplied' ) if !defined $opts{uid} && !defined $opts{gid};

    # If undefined, we default to enabled (true).
    my $protect_system = $opts{protect_system} // 1;
    my $check_exists   = $opts{check_exists}   // 1;
    my $check_quota    = $opts{check_quota}    // 1;

    my $used_ref = _load_datastore();

    my $removed_uid;
    if ( defined( my $uid = $opts{uid} ) ) {
        return ( 0, 'Invalid uid supplied' )                    if !length $uid || $uid =~ tr{0-9}{}c;
        return ( 0, 'System uid supplied' )                     if $protect_system && $uid < Cpanel::LoginDefs::get_uid_min();
        return ( 0, "The supplied uid ($uid) is still in use" ) if $check_exists   && ( getpwuid($uid) )[0];
        if ($check_quota) {
            local $@;
            my $uid_has_disk_usage;
            eval { $uid_has_disk_usage = uid_has_disk_usage($uid) };
            if ($@) {
                return ( 0, "The system failed to determine if the supplied uid ($uid) still has files because of an error: $@" );
            }
            return ( 0, "The supplied uid ($uid) still has files" ) if $uid_has_disk_usage;
        }

        $removed_uid = $uid if exists $used_ref->{uids}{$uid};
        delete $used_ref->{uids}{$uid};
    }

    my $removed_gid;
    if ( defined( my $gid = $opts{gid} ) ) {
        return ( 0, 'Invalid gid supplied' )             if !length $gid || $gid =~ tr{0-9}{}c;
        return ( 0, 'System gid supplied' )              if $protect_system && $gid < Cpanel::LoginDefs::get_gid_min();
        return ( 0, 'The supplied gid is still in use' ) if $check_exists   && ( getgrgid($gid) )[0];

        $removed_gid = $gid if exists $used_ref->{gids}{$gid};
        delete $used_ref->{gids}{$gid};
    }

    _save($used_ref) if defined $removed_uid or defined $removed_gid;
    return ( 1, 'OK', $removed_uid, $removed_gid );
}

1;

__END__

=encoding utf8

=head1 NAME

Whostmgr::Accounts::IdTrack - Tracks used UIDs and GIDs

=head1 DESCRIPTION

This module lets S<cPanel & WHM®> keep track of all the currently and
previously used UIDs and GIDs on the system.  By keeping track of already used
IDs, S<cPanel & WHM®> can avoid reusing them as that poses a security issue.
Specifically, if a new user is created with the same UID or GID as a previous
user and that previous user still owns files somewhere on the system, the new
user will gain the same level of access as the previous user.  This compromises
the confidentiality of the previous user, who may have had access to WHM.

=head1 SYNOPSIS

    use Whostmgr::Accounts::IdTrack ();

    my ($status, $reason, $uid, $gid) = Whostmgr::Accounts::IdTrack::allocate();
    die "Error allocating IDs: $reason" if !$status;

    # This has security implications!
    ($status, $reason) = Whostmgr::Accounts::IdTrack::remove_id( uid => 1001 );
    die "Error removing ID: $reason" if !$status;

=head1 FUNCTIONS

=head2 C<allocate([$opts])>

Allocates an unused UID and GID for a new user and adds it to the tracked ID
list.

Dynamically selected UIDs will always be between C<UID_MIN> and C<UID_MAX>,
inclusive.  GIDs are also between C<UID_MIN> and C<UID_MAX>; the allocator
ignores the system C<GID_MIN> and C<GID_MAX> values.

=over 4

=item C<$opts> [in, optional]

A hashref of extra options to pass.

The options include C<uid> and C<gid>, which are used to manually specify the
UID and GID to use instead of dynamically selecting one.  Manually specified
UIDs can less than C<UID_MIN> or greater than C<UID_MAX>.

The options also include C<minuid> and C<minuid>
If the parameter if not specified, or the value specified is below the system’s
C<UID_MIN>, the value of C<UID_MIN> will be used.  See C<Cpanel::LoginDefs> for
details on C<UID_MIN>.

=back

B<Returns:> A list of values: C<($status, $reason, $uid, $gid)>.  Like many
functions, the $status is C<1> if it succeeds and C<0> if it fails (with
$reason documenting the error).  The $uid and $gid are the UID and GID that
have been added into the list of tracked IDs; however, the user is I<not>
created.

=head2 C<< remove_id(%opts) >>

Removes the historically used UID or GID from the tracked ID list.

By removing a UID or GID, it can be reused on a subsequent C<allocate()> call.

B<Important:> This has security implications; see the L</DESCRIPTION>.

The %opts can be any of the following:

=over 4

=item C<< uid => $uid >> [in, optional]

The UID to remove from the list.  Only one UID is handled at a time.

At least one of C<uid> and C<gid> must be supplied; both may be supplied.

=item C<< gid => $gid >> [in, optional]

The GID to remove from the list.  Only one GID is handled at a time.

At least one of C<uid> and C<gid> must be supplied; both may be supplied.

=item C<< protect_system => 0 | 1 >> [in, optional]

Prevent the removal of a system UID or GID.

Iff true, prevent any changes if either the UID or GID are considered system
UIDs or GIDs.  This prevents accidental removal of users like root or cpanel
from the list.

Defaults to C<1>.

=item C<< check_exists => 0 | 1 >> [in, optional]

Prevent the removal of UIDs or GIDs in use.

Iff true, prevent any changes if the UID or GID to remove is currently being
used by the system.

Defaults to C<1>.

=item C<< check_quota => 0 | 1 >> [in, optional]

Prevent the removal of UIDs that currently have files on the system.

Iff true, prevent any changes if the quota system knows of any files associated
with the supplied UID.  It should be noted that the quota system may not track
all the files on the system.  And, of course, this only works if the quota
system is enabled.

Unlike other checks, this only applies to UIDs.  GIDs are not checked.

Defaults to C<1>.

=back

B<Returns:> A list of values: C<($status, $reason, $uid, $gid)>.  Like many
functions, the $status is C<1> if it succeeds and C<0> if it fails (with
$reason documenting the error).  The $uid and $gid are the UID and GID that
were removed.  This will be the UID/GID specified in the parameters if the call
succeeds B<and> ID existed in the tracking database; otherwise, it will be
C<undef>.

=head2 C<build_db()>

Rebuilds the database of used UIDs and GIDs.

Only users and groups that currently exist in F</etc/passwd> and F</etc/groups>
are included in the new databases.  Historically used, but currently
unallocated, UIDs and GIDs will be lost.

B<Important:> This has security implications; see the L</DESCRIPTION>.
