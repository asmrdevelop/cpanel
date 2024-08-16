package Cpanel::Homedir::Modify;

# cpanel - Cpanel/Homedir/Modify.pm                Copyright 2022 cPanel, L.L.C.
#                                                           All rights reserved.
# copyright@cpanel.net                                         http://cpanel.net
# This code is subject to the cPanel license. Unauthorized copying is prohibited

use strict;
use Cpanel::LoadModule         ();
use Cpanel::Autodie            ();
use Cpanel::Chdir              ();
use Cpanel::Config::LoadCpConf ();
use Cpanel::Exception          ();
use File::Path                 ();
use Try::Tiny;

our $MAX_ATTEMPTS = 4;

=pod

=encoding utf-8

=head1 NAME

Cpanel::Homedir::Modify - Tools for making changes (re)moving a users homedir

=head1 SYNOPSIS

    Cpanel::Homedir::Modify::remove_homedir($user, $homedir);

    Cpanel::Homedir::Modify::rename_homedir($user, $oldhomedir, $newhomedir);


=head1 DESCRIPTION

This module provides functionality to rename or remove a user's
home directory and work around any EBUSY results from the the
rename() and rmdir() calls caused by open files or mount namespace
being held by BIND.

=head1 WARNINGS

If a user has running processes that have files open in the home directory
they will be killed.

If BIND is still holding on to the user's mount namespace it may
be restarted.

=head1 METHODS

=head2 remove_homedir( USER, HOMEDIR )

Remove a user's homedir and all files under it

=head3 Arguments

Required:

  USER            - scalar:   The username that owns the home directory
  HOMEDIR         - scalar:   The home directory to remove

=head3 Return Value

  >0 - Success (number of files removed)
  0  - Failure

=cut

sub remove_homedir {
    my ( $user, $homedir ) = @_;

    Cpanel::Autodie::chown( 0, 0, $homedir );
    Cpanel::Autodie::chmod( 0, $homedir );

    my $chdir;
    if ( rindex( Cwd::getcwd(), $homedir ) == 0 ) {

        # We cannot chdir() back to the user's homedir
        # if we are about to delete it.  This currently
        # only happens in tests
        chdir('/') or die "Failed to chdir(/): $!";
    }
    else {
        $chdir = Cpanel::Chdir->new('/');
    }

    return _perform_op_for_user_that_may_get_blocked_by_fs_ebusy(
        $user,
        $homedir,
        sub {
            my ( $ret, $exception, $last_err );
            try {
                local $!;
                $ret      = File::Path::rmtree($homedir);
                $last_err = $!;
            }
            catch {
                $exception = $_;
            };
            if ($exception) {
                die Cpanel::Exception::create( 'IO::DirectoryDeleteError', [ error => $exception, path => $homedir ] );
            }
            elsif ( $last_err || !$ret || $ret == -1 ) {
                die Cpanel::Exception::create( 'IO::DirectoryDeleteError', [ error => $last_err, path => $homedir ] );
            }
            return $ret;
        }
    );

}

=head2 rename_homedir( USER, OLDHOMEDIR, NEWHOMEDIR )

Rename a user's home directory from one location to another
as long as the old and new home directories are on the same
file system.

=head3 Arguments

Required:

  USER            - scalar:   The username that owns the home directory
  OLDHOMEDIR      - scalar:   The home directory to rename
  NEWHOMEDIR      - scalar:   The new path for the home directory

=head3 Return Value

  1 - Success
  0 - Failure

=cut

sub rename_homedir {
    my ( $user, $oldhome, $newhome ) = @_;

    return _perform_op_for_user_that_may_get_blocked_by_fs_ebusy(
        $user,
        $oldhome,
        sub { return Cpanel::Autodie::rename( $oldhome, $newhome ) }
    );
}

=head2 restart_bind_to_release_mount_namespace

Restart bind in order to release the mount namespace.

Bind uses it own mount namespace
which may make the rename or rmdir return
EBUSY (Device or resource busy) because
it still has a reference to the virtfs
mounts.

=head3 Arguments

None

=head3 Return Value

  1 - Success

=cut

sub restart_bind_to_release_mount_namespace {
    if ( Cpanel::Config::LoadCpConf::loadcpconf_not_copy()->{'local_nameserver_type'} eq 'bind' ) {
        require Cpanel::Services::Restart;
        Cpanel::Services::Restart::restartservice('named');
    }
    return 1;
}

sub _perform_op_for_user_that_may_get_blocked_by_fs_ebusy {
    my ( $user, $sourcedir, $op_coderef ) = @_;

    # May need to try multiple times to rename
    # in case something hasn't closed the dir yet
    # or we will get Device or resource busy
    my $attempts = 0;
    my $ok       = 0;
    while ( !$ok ) {
        try {
            $ok = $op_coderef->();
        }
        catch {
            if ( ++$attempts > $MAX_ATTEMPTS ) {
                local $@ = $_;
                die;
            }
            Cpanel::LoadModule::load_perl_module('Cpanel::Sys::Kill');
            Cpanel::Sys::Kill::kill_users_processes($user);

            # Virtfs uses it own mount namespace
            # which may make the the call return
            # Device or resource busy
            if ( $attempts == $MAX_ATTEMPTS - 3 ) {
                Cpanel::LoadModule::load_perl_module('Cpanel::Filesys::Virtfs');
                Cpanel::Filesys::Virtfs::clean_user_virtfs($user);
            }
            if ( $attempts == $MAX_ATTEMPTS - 2 ) {
                Cpanel::LoadModule::load_perl_module('Cpanel::Kill::OpenFiles');
                Cpanel::Kill::OpenFiles::safekill_procs_access_files_under_dir($sourcedir);
            }
            restart_bind_to_release_mount_namespace($user) if $attempts == $MAX_ATTEMPTS - 1;
        };
    }

    return $ok;
}

1;
