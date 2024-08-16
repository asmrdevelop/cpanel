package Cpanel::SafetyBits;

# cpanel - Cpanel/SafetyBits.pm                    Copyright 2022 cPanel, L.L.C.
#                                                           All rights reserved.
# copyright@cpanel.net                                         http://cpanel.net
# This code is subject to the cPanel license. Unauthorized copying is prohibited

use strict;
use Cpanel::AccessIds::ReducedPrivileges ();
use Cpanel::AccessIds                    ();
use Cpanel::AccessIds::SetUids           ();
use Cpanel::AccessIds::Utils             ();
use Cpanel::PwCache                      ();
use Cpanel::SafetyBits::Chown            ();
use Cpanel::Lchown                       ();
use Cwd                                  ();

$Cpanel::SafetyBits::VERSION       = '0.9';
$Cpanel::SafetyBits::hide_warnings = 0;

*safe_chown = *Cpanel::SafetyBits::Chown::safe_chown;
*ishardlink = *Cpanel::SafetyBits::Chown::ishardlink;
*setuid     = *Cpanel::AccessIds::SetUids::setuids;
*setuids    = *Cpanel::AccessIds::SetUids::setuids;
*runasuser  = *Cpanel::AccessIds::runasuser;

sub set_hide_warnings {
    my ($setting) = @_;
    if ($setting) {
        $Cpanel::SafetyBits::hide_warnings = 1;
    }
    else {
        $Cpanel::SafetyBits::hide_warnings = 0;
    }
    return $Cpanel::SafetyBits::hide_warnings;
}

################################################################
# safe_userchgid - Changes the gid of a file a user already owns
# Params:
#    UID - User's numeric ID or user's name.
#    GID - User's numeric ID, or undef if user name is provided.
#    Files- A list of files to chown.
sub safe_userchgid {
    my ( $uid, $gid, @files ) = @_;

    if ( $uid !~ m/^\d+$/ ) {
        $uid = ( Cpanel::PwCache::getpwnam($uid) )[2];
    }
    if ( $gid !~ m/^\d+$/ ) {
        $gid = ( getgrnam($gid) )[2];
    }

    if ( !defined $uid || !defined $gid ) {
        print "safe_userchgid: Error Fetching the uid/gid";
        return;
    }

    if ( $uid =~ m{(\d+)} ) {
        $uid = $1;
    }
    if ( $gid =~ m{(\d+)} ) {
        $gid = $1;
    }

    Cpanel::AccessIds::ReducedPrivileges::call_as_user(
        sub {
            foreach my $file (@files) {
                next if ( -l $file || ishardlink($file) );
                $file =~ m/(.*)/s;
                $file = $1;
                unless ( chown( $uid, $gid, $file ) ) {
                    if ( !$Cpanel::SafetyBits::hide_warnings ) {
                        warn "safe_userchgid: chown: $file: $!";
                    }
                }
            }
        },
        $uid,
        $gid
    );

    return 1;
}

##################################################################
# safe_recchown
#    See safe_chown.
#    This function provides the same functionality as safe_chown
#  only it provides a recursive interface for chowning entire
#  directory trees.
sub safe_recchown {
    my ( $uid, $gid, @files ) = @_;
    my $count = 0;
    if ( $uid !~ m/^\d+$/ ) {
        $uid = ( Cpanel::PwCache::getpwnam($uid) )[2];
    }
    if ( $gid !~ m/^\d+$/ ) {
        $gid = ( getgrnam($gid) )[2];
    }
    if ( !defined $uid || !defined $gid ) {
        print "safe_recchown: Error Fetching the uid/gid";
        return;
    }
    my @locked_dirs;
  FILE:
    foreach my $file (@files) {
        if ( -l $file ) {    # Prevent need for separate lstat call
            if ( Cpanel::Lchown::lchown( $uid, $gid, $file ) ) {
                $count++;
            }
            elsif ( !$Cpanel::SafetyBits::hide_warnings ) {
                warn "lchown $file: $!";    # Chown symlink not target
            }
            next FILE;
        }
        my $isdir = -d _;
        my ( $mode, $nlink ) = ( stat(_) )[ 2, 3 ];    # Reuse previous stat
        next FILE if !$mode;

        if ( !$isdir ) {
            if ( $nlink > 1 ) {                        # hardlinks skipped
                next FILE;
            }
            if ( Cpanel::Lchown::lchown( $uid, $gid, $file ) ) {
                $count++;
            }
            elsif ( !$Cpanel::SafetyBits::hide_warnings ) {
                warn "lchown $file: $!";    # Probably removed or set on demand
            }
            next FILE;
        }
        elsif ($isdir) {
            if ( $> == 0 ) {
                if ( Cpanel::Lchown::lchown( 0, 0, $file ) ) {
                    push @locked_dirs, $file;
                }
                elsif ( !$Cpanel::SafetyBits::hide_warnings ) {
                    warn "Unable to lock dir $file: $!";
                }
            }
            else {
                push @locked_dirs, $file;
            }

            if ( opendir my $dir_dh, $file ) {
                my @nfiles = map { $file . '/' . $_ } grep { !/^[.][.]?$/ } readdir $dir_dh;
                closedir $dir_dh;
                if (@nfiles) {
                    my ( $ncount, $lockdirs_ref ) = safe_recchown( $uid, $gid, @nfiles );
                    push @locked_dirs, @{$lockdirs_ref};
                    $count += $ncount;
                }
            }
            else {
                warn "Unable to read dir $file: $!";
                next FILE;
            }
        }
        else {
            warn "Cannot process $file";
            next FILE;
        }
    }
    if ( !wantarray ) {
        $count += Cpanel::Lchown::lchown( $uid, $gid, reverse @locked_dirs );
    }
    return wantarray ? ( $count, \@locked_dirs ) : $count;
}

##################################################################
# safe_userrecchown
#    See safe_chown.
#    This function provides the same functionality as safe_chown
#  only it provides a recursive interface for chowning entire
#  directory trees.  Runs as the user/group
sub safe_userrecchown {
    my ( $uid, $gid, @files ) = @_;
    if ( $uid !~ m/^\d+$/ ) {
        $uid = ( Cpanel::PwCache::getpwnam($uid) )[2];
    }
    if ( $gid !~ m/^\d+$/ ) {
        $gid = ( getgrnam($gid) )[2];
    }
    if ( !defined $uid || !defined $gid ) {
        print "safe_recchown: Error Fetching the uid/gid";
        return;
    }

    if ( my $pid = fork() ) {
        waitpid( $pid, 0 );
    }
    else {
        Cpanel::AccessIds::SetUids::setuids( $uid, $gid );
        if ( $uid =~ m{(\d+)} ) {
            $uid = $1;
        }
        if ( $gid =~ m{(\d+)} ) {
            $gid = $1;
        }

        foreach my $file (@files) {

            next if ( -l $file || ishardlink($file) );

            # Untaint
            if ( $file =~ m/(.*)/s ) {
                $file = $1;
            }
            chown $uid, $gid, $file;
            if ( -d $file ) {
                opendir( DIR, $file );
                my @nfiles = grep { !/^\.+$/ } readdir(DIR);
                my @newfiles;
                foreach my $nfile (@nfiles) {
                    push( @newfiles, $file . '/' . $nfile );
                }
                closedir(DIR);
                safe_recchown( $uid, $gid, @newfiles );
            }
        }
        exit;
    }
    return 1;
}

##################################################################
# safe_lrecchown
#    See safe_chown.
#    This function provides the same functionality as safe_chown
#  only it provides a recursive interface for chowning entire
#  directory trees.  However it only checks for symlinks and
#  not hard links
sub safe_lrecchown {
    my ( $uid, $gid, @files ) = @_;
    my $count = 0;

    if ( $uid !~ m/^\d+$/ ) {
        $uid = ( Cpanel::PwCache::getpwnam($uid) )[2];
    }
    if ( $gid !~ m/^\d+$/ ) {
        $gid = ( getgrnam($gid) )[2];
    }

    if ( !defined $uid || !defined $gid ) {
        print "safe_lrecchown: Error Fetching the uid/gid";
        return;
    }

    foreach my $file (@files) {
        next if ( -l $file );

        # Untaint
        $file =~ m/(.*)/s;
        $file = $1;
        chown $uid, $gid, $file;
        if ( -d $file ) {
            opendir( DIR, $file );
            my @nfiles = grep { !/^\.+$/ } readdir(DIR);
            my @newfiles;
            foreach my $nfile (@nfiles) {
                push( @newfiles, $file . '/' . $nfile );
            }
            closedir(DIR);
            $count += safe_lrecchown( $uid, $gid, @newfiles );
        }
        $count++;
    }
    return $count;
}

################################################################
# safe_chmod - Provides a perl-like interface to chmod.
#    Prior to chmoding a file, safe_chmod setuid's to the
#    given user.
# Params:
#    Perms  - Numeric permissions to chmod the file.
#    User   - User's UID or User name.
#    Files  - Array of files to chmod.
sub safe_chmod {
    my ( $perms, $user, @files ) = @_;

    if ( $user !~ m/^-?\d+$/ ) { $user = ( Cpanel::PwCache::getpwnam($user) )[2]; }

    my @dirs   = ();
    my @files2 = ();
    my $dircnt = 0;

    foreach my $file (@files) {
        if ( -d $file ) {
            push( @dirs, $file );
        }
        else {
            push( @files2, $file );
        }
    }

    # Allow setgid directories that are not the user's group
    if (@dirs) {
        my $orig = Cwd::fastcwd();
        foreach my $dir (@dirs) {

            # Ignore directories not owned by the user.
            #   Implementation of the double-checked locking algorithm to prevent
            #   wasting time on the chdir if not owned by user, but while still
            #   not allowing race condition in.
            next unless $user == ( stat($dir) )[4];

            # Change directory to prevent race condition of changing out from under us.
            #   if we can't change then there's no need to chmod.
            chdir $dir or next;
            if ( $user == ( stat('.') )[4] ) {    # Directory has not been changed.
                $dircnt = $dircnt + chmod $perms, '.';
            }

            # Restore original directory, protect from relative paths.
            #   If this directory goes away or becomes inaccessible, something horrible
            #   has happened and there is nothing we can do about it. Bailing seems to
            #   be our only option.
            chdir $orig or die "Original directory '$orig' is no longer accessible\n";
        }
    }

    if (@files2) {
        if ( my $pid = fork() ) {
            waitpid( $pid, 0 );
        }
        else {
            if ( $> != $user ) {
                Cpanel::AccessIds::SetUids::setuids($user);
            }

            foreach my $file (@files2) {

                # Untaint
                $file =~ m/(.*)/s;
                $file = $1;
                chmod $perms, $file;
            }
            exit;
        }
    }
    return ( ( $#files2 + 1 ) + $dircnt );
}

################################################################
# safe_recchmod - A recursive version of safe_chmod
sub safe_recchmod {
    my ( $perms, $user, @files ) = @_;

    # Untaint
    if ( $user =~ m{(.*)}s ) {
        $user = $1;
    }
    if ( $perms =~ m{(.*)}s ) {
        $perms = $1;
    }
    if ( $> != 0 ) {
        my ( $uid, $gid ) = Cpanel::AccessIds::Utils::normalize_user_and_groups($user);
        if ( $uid == $> && $gid == $) ) {

            # already running as the correct user
            return _safe_recchmod( $perms, @files );
        }
    }

    # Running as root or running as the incorrect user/group
    return Cpanel::AccessIds::ReducedPrivileges::call_as_user( sub { return _safe_recchmod( $perms, @files ); }, $user );
}

sub _safe_recchmod {
    my ( $perms, @files ) = @_;
    my $count = 0;
    foreach my $file (@files) {

        # Untaint
        if ( $file =~ m/(.*)/s ) {
            $file = $1;
        }

        if ( -d $file && opendir( my $dh, $file ) ) {
            my @nfiles = grep { !/^\./ } readdir($dh);
            my @newfiles;
            foreach my $nfile (@nfiles) {
                $nfile =~ s/(.*)/$1/;
                push( @newfiles, $file . '/' . $nfile );
            }
            closedir($dh);
            $count += _safe_recchmod( $perms, @newfiles );
        }

        $count += chmod $perms, $file;
    }
    return $count;
}

1;
