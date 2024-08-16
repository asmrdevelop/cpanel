package Cpanel::NFS;

# cpanel - Cpanel/NFS.pm                           Copyright 2022 cPanel, L.L.C.
#                                                           All rights reserved.
# copyright@cpanel.net                                         http://cpanel.net
# This code is subject to the cPanel license. Unauthorized copying is prohibited

use cPstrict;

=encoding utf-8

=head1 NAME

Cpanel::NFS

=head1 SYNOPSIS

    if (@problems = Cpanel::NFS::get_new_mount_problems($host, $path, @opts)) {
        die "That NFS has problems: @problems\n";
    }

=head1 DESCRIPTION

This module implements logic that’s useful for interacting with NFS
servers.

=cut

#----------------------------------------------------------------------

use Cpanel::Autodie         ();
use Cpanel::Homedir::Search ();
use Cpanel::NFS::Check      ();

use Cpanel::Context ();

my %_named_consts;

BEGIN {
    %_named_consts = map { $_ => $_ } qw(
      UNPRIV_GROUP_CHOWN
    );
}
use constant \%_named_consts;

#----------------------------------------------------------------------

=head1 CONSTANTS

See C<get_new_mount_problems()> below.

=head1 FUNCTIONS

=head2 @problems = get_new_mount_problems( $HOSTNAME_OR_IP, $REMOTE_PATH, @OPTS )

Mounts an NFS share to a temporary directory, tests it,
then unmounts. @OPTS are the options (besides C<-t>/C<--types>, of course!)
to give to L<mount(8)>.

Returns a list of strings that indicate reasons to reject the mount.
That list will include 0 or more of:

=over

=item * C<UNPRIV_GROUP_CHOWN> - This indicates that the NFS server
prevents an unprivileged user from changing the group of a file that
the user owns, even if the running process is a member of the target group.

This can happen if rpc.mountd’s C<--manage-gids> option is on, which
is Ubuntu 20’s default state. (That option doesn’t I<directly> prevent
unprivileged group chown; see L<rpc.mountd(8)> for more details.)

When this happens the NFS share B<MUST> B<NOT> be used as remote storage,
as cPanel & WHM needs NFS to work identically to a local filesystem in this
area.

=back

The above are exposed as bareword constants from this namespace.
Please refer to them thus (e.g., C<Cpanel::NFS::UNPRIV_GROUP_CHOWN>)
rather than as simple strings.

=cut

sub get_new_mount_problems ( $host, $path, @mount_opts ) {
    Cpanel::Context::must_be_list();

    my ( undef, @probs ) = _get_new_problems_save_nfs( $host, $path, @mount_opts );

    return @probs;
}

=head2 $problems_hr = get_update_mount_problems( $LOCAL_DIR, $HOSTNAME_OR_IP, $REMOTE_PATH, @OPTS )

Like C<get_new_mount_problems()> above but adds an additional check that
the updated NFS remote has all of the user home directories that exist
under $LOCAL_DIR.

The return is also a hash reference rather than a list. Every problem
that C<get_new_mount_problems()> can return can happen here; it’ll just be
a key in the returned hashref. (The value is irrelevant.) Additionally,
the following can be in the referent hash:

=over

=item * C<MISSING_HOMEDIR> - Its value is a reference to a hash such as
L<Cpanel::Homedir::Search>’s C<get_users()> returns.

=back

=cut

sub get_update_mount_problems ( $local_dir, $host, $path, @mount_opts ) {    ## no critic qw(ManyArgs) - superfluous
    my ( $nfs, @probs_arr ) = _get_new_problems_save_nfs( $host, $path, @mount_opts );

    my %problems = map { $_ => 1 } @probs_arr;

    my $user_dir_hr = Cpanel::Homedir::Search::get_users($local_dir);

    my $nfsdir = $nfs->get_local_dir();

    # NB: stat() on each homedir may perform suboptimally; if we need
    # we can optimize by reading the directories and comparing contents.
    #
    for my $username ( sort keys %$user_dir_hr ) {
        my $reldir = $user_dir_hr->{$username};

        if ( !Cpanel::Autodie::exists_nofollow("$nfsdir/$reldir") ) {
            $problems{'MISSING_HOMEDIR'}{$username} = $reldir;
        }
    }

    return \%problems;
}

sub _get_new_problems_save_nfs ( $host, $path, @mount_opts ) {
    my $nfs = Cpanel::NFS::Check->new( $host, $path, @mount_opts );

    my @probs;

    if ( !$nfs->unprivileged_group_chown_works() ) {
        push @probs, UNPRIV_GROUP_CHOWN;
    }

    return $nfs, @probs;
}

1;
