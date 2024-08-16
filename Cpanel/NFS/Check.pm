package Cpanel::NFS::Check;

# cpanel - Cpanel/NFS/Check.pm                     Copyright 2022 cPanel, L.L.C.
#                                                           All rights reserved.
# copyright@cpanel.net                                         http://cpanel.net
# This code is subject to the cPanel license. Unauthorized copying is prohibited

use cPstrict;

=encoding utf-8

=head1 NAME

Cpanel::NFS::Check

=head1 SYNOPSIS

    my $nfs = Cpanel::NFS::Check->new( $host, $path, @mount_opts );

    if (!$nfs->unprivileged_group_chown_works()) {
        Carp::croak "Unpriv group chown must work!";
    }

=head1 DESCRIPTION

This class implements logic to mount an NFS share in a temporary
directory and perform various checks on it.

=cut

#----------------------------------------------------------------------

use Try::Tiny;

use File::Temp ();

use Cpanel::AccessIds::ReducedPrivileges ();
use Cpanel::Binaries                     ();
use Cpanel::Mount                        ();
use Cpanel::OS                           ();
use Cpanel::SafeRun::Object              ();
use Cpanel::Exception                    ();

#----------------------------------------------------------------------

=head1 METHODS

=head2 $obj = I<CLASS>->new( $HOSTNAME_OR_IP, $EXPORT_PATH, @MOUNT_OPTS )

Instantiates I<CLASS>. This will mount the indicated NFS share
in a temporary directory.

Once $obj is garbage-collected the system will unmount the filesystem.

=cut

sub new ( $class, $host, $path, @mount_opts ) {

    my $mount_dir = File::Temp::tempdir( CLEANUP => 1 );

    # ------------------------------------------------------------
    # Ideally we could use Net::LibNFS for this; that way we wouldn’t
    # have to change system state. Only Linux’s native NFS client, though,
    # can reliably interpret @$opts_ar, so unless we’re going to try parsing
    # @$opts_ar (ick!), we have to do a full mount/unmount.
    # ------------------------------------------------------------

    my $mount_bin = Cpanel::Binaries::path("mount");

    # In the mount_opts we are allowing the user to pass whmtimeoutsec=XX as a
    # way to allow them to set a mount timeout, for both the check and later for
    # systemd.

    my $timeout = 15;

    my @mount_opts_clean;
    foreach my $opt (@mount_opts) {
        if ( index( $opt, ',' ) >= 0 || scalar( $opt =~ tr/=// ) > 1 ) {
            die Cpanel::Exception::create( 'InvalidParameter', "Invalid value “[_1]” for the “[_2]” setting.", [ $opt, "option" ] );
        }
        if ( index( $opt, 'whmtimeoutsec=' ) == 0 ) {
            my ( $whm, $secs ) = split( '=', $opt, 2 );
            $timeout = $secs;
        }
        else {
            push( @mount_opts_clean, $opt );
        }
    }

    Cpanel::SafeRun::Object->new_or_die(
        program => $mount_bin,
        args    => [
            '--no-mtab',
            '--types',  'nfs',
            '--source', "$host:$path",
            '--target', $mount_dir,
            ( @mount_opts_clean ? ( '--options', join( ',', @mount_opts_clean ) ) : () ),
        ],
        (
            timeout => $timeout,
        )
    );

    return bless [ $mount_dir, $$ ], $class;
}

=head2 $path = I<OBJ>->get_local_dir()

Returns the absolute path of the temporary directory where the remote
NFS share is mounted.

=cut

sub get_local_dir ($self) {
    return $self->[0];
}

=head2 $yn = I<OBJ>->unprivileged_group_chown_works()

Manipulates the remote NFS share to determine whether unprivileged
group chown works—e.g., whether an unprivileged process whose effective
groups are C<bob> and C<mail> can change a file’s group ownership between
C<bob> and C<mail>.

Returns a boolean that indicates the result of that test. Throws an
exception if something prevents discovery.

=cut

sub unprivileged_group_chown_works ($self) {
    my $username  = Cpanel::OS::nobody();
    my $groupname = 'mail';

    my $mount_dir = $self->[0];

    my $mailgid = getgrnam $groupname or die "Failed to get `$groupname` GID! ($!)";

    my ( $uid, $gid ) = ( getpwnam $username )[ 2, 3 ];
    die "Failed to get `$username` UID! ($!)" if !$uid;

    my ( $fh, $privs );

    try {

        # NB: On a local filesystem the file will be unlinked but will
        # still exist until the file descriptor closes. NFS can’t do this,
        # though, so under the hood it instead renames the file to some
        # “nfs-y-named” dot file, which gets deleted once the application
        # closes its filehandle. To the application it’s basically all the
        # same, but just FYI.
        #
        $fh = File::Temp::tempfile( DIR => $mount_dir );

        _chown( $uid, $gid, $fh ) or die "Failed to chown temp file ($username:$username): $!";

        $privs = Cpanel::AccessIds::ReducedPrivileges->new( $uid, $gid, $mailgid );
    }
    catch {
        die "Failed to set up check of unprivileged group chown: $_";
    };

    my $ok;

    if ( _chown( -1, $mailgid, $fh ) ) {
        $ok = 1;
    }
    elsif ( !$!{'EPERM'} ) {
        die "Failed to check unprivileged group chown: unexpected chown($username:$groupname) failure: $!";
    }

    return $ok || 0;
}

# Overridden in testing:
#
sub _chown ( $uid, $gid, $fh ) {
    return chown( $uid, $gid, $fh );
}

sub DESTROY ($self) {
    my ( $mount_dir, $pid ) = @$self;

    if ( $pid == $$ ) {
        my $err = Cpanel::Mount::umount( $mount_dir, $Cpanel::Mount::MNT_DETACH );
        warn "umount($mount_dir) (EUID=$>): $!" if 0 != $err;
    }

    return;
}

1;
