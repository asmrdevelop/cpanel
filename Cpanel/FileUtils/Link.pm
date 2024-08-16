package Cpanel::FileUtils::Link;

# cpanel - Cpanel/FileUtils/Link.pm                Copyright 2022 cPanel, L.L.C.
#                                                           All rights reserved.
# copyright@cpanel.net                                         http://cpanel.net
# This code is subject to the cPanel license. Unauthorized copying is prohibited

use strict;
use warnings;

use Cpanel::Debug ();
##
## ** Never call system() or exec() in this module ***
##

#XXX DEPRECATED. Please see Cpanel::Autodie instead.
sub safeunlink {
    my $file = shift;
    return 1 if !-l $file && !-e _;
    if ( unlink $file ) {
        return 1;
    }
    else {
        Cpanel::Debug::log_warn("Unable to unlink $file: $!");
        return;
    }
}

sub _replicate_file {
    my $orig = shift;
    my $dest = shift;

    my ( $mode, $uid, $gid, $atime, $mtime ) = ( stat($orig) )[ 2, 4, 5, 8, 9 ];
    $mode = $mode & 07777;

    return 0 if ( !-e _ );
    return 0 unless ( -r _ || -w _ || -x _ );

    require Cpanel::SafeFile;
    my $ori_fh;
    my $dest_fh;
    open( $ori_fh, '<', $orig ) || return 0;
    my $destlock = Cpanel::SafeFile::safeopen( $dest_fh, '>', $dest ) || do {
        Cpanel::Debug::log_warn("Unable to open $dest for write!");
        close($ori_fh);
        return 0;
    };
    while (<$ori_fh>) {
        print {$dest_fh} $_;
    }
    close($ori_fh);
    Cpanel::SafeFile::safeclose( $dest_fh, $destlock );
    if ( -z $orig != -z $dest ) {
        unlink($dest);
        Cpanel::Debug::log_warn("Unable to properly write $dest");
        return 0;
    }
    unless ( chown( $uid, $gid, $dest ) ) {
        Cpanel::Debug::log_warn("Unable to chown $dest to UID $uid GID $gid");
    }
    unless ( chmod( $mode, $uid, $dest ) ) {
        Cpanel::Debug::log_warn("Unable to chmod $dest for UID $uid");
    }
    unless ( utime( $atime, $mtime, $dest ) ) {
        Cpanel::Debug::log_warn("Unable to set utime on $dest for UID $uid");
    }

    return 1;
}

sub safelink {
    my $orig = shift;
    my $dest = shift;

    return 0 if ( $orig eq '' || $dest eq '' || !-e $orig );

    # Disallow linking to files that the EUID doesn't have access to
    return 0 unless ( -r $orig || -w $orig || -x $orig );

    if ( !link( $orig, $dest ) ) {

        # Link failed just rewrite the file
        return _replicate_file( $orig, $dest );
    }
    return 1;
}

sub forced_symlink {
    my ( $target, $file ) = @_;

    my $current_target = readlink($file);

    if ($current_target) {
        return 1 if $current_target eq $target;
        unlink($file);
    }

    return symlink( $target, $file );
}

sub find_symlink_in_path {
    my ($path) = @_;

    my @split_path = split m{/}, $path;
    my $test_path  = q{};
    while (@split_path) {
        my $path_node = shift @split_path;
        next if !length $path_node;

        $test_path .= "/$path_node";
        return $test_path if -l $test_path;

        last if !-e _;
    }

    return;
}

1;
