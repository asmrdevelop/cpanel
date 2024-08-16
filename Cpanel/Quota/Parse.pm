package Cpanel::Quota::Parse;

# cpanel - Cpanel/Quota/Parse.pm                   Copyright 2022 cPanel, L.L.C.
#                                                           All rights reserved.
# copyright@cpanel.net                                         http://cpanel.net
# This code is subject to the cPanel license. Unauthorized copying is prohibited

use strict;
use warnings;

use Cpanel::Filesys::Mounts ();
use Cpanel::Math            ();
use Cpanel::Backup::Config  ();

my %MNTPTS;

sub parse_quota {
    my ( $quota, $return_bytes ) = @_;
    my ( $FILES_REMAIN, $DISK_REMAIN );
    my $backup_dirs_ref = Cpanel::Backup::Config::get_backup_dirs();
    my $DISK_USED       = 0;
    my $DISK_LIMIT      = 0;
    my $FILES_USED      = 0;
    my $FILES_LIMIT     = 0;
    my $addline         = '';

    foreach my $line ( split( /\n/, $quota ) ) {
        chomp $line;
        $line =~ s/^\s*//g;
        if ( $line =~ /^\s*\/\S+$/ ) {
            $addline = $line;
            next;
        }
        if ( $addline ne '' ) {
            $line    = $addline . ' ' . $line;
            $addline = '';
        }
        if ( $line =~ /^\s*\// ) {

            my ( $device, $disk_used, $disk_limit, $files_used, $files_limit ) = parse_quota_line($line);

            my $mount_point = getmnt($device);
            next if !check_if_backup_directory( $mount_point, $backup_dirs_ref );

            my $length = length $disk_limit;
            if ( $length >= 12 ) {
                my $disk_limit_orig = $disk_limit;
                my $halflength      = int( $length / 2 );    # can be odd, then things get funny
                $disk_limit = substr( $disk_limit_orig, 0, $halflength );
            }

            $DISK_USED += $disk_used;
            $DISK_LIMIT ||= $disk_limit;
            $FILES_USED += $files_used;
            $FILES_LIMIT ||= $files_limit;
        }
    }

    $DISK_REMAIN  = $DISK_LIMIT  ? ( $DISK_LIMIT - $DISK_USED )   : undef;
    $FILES_REMAIN = $FILES_LIMIT ? ( $FILES_LIMIT - $FILES_USED ) : undef;
    if ($DISK_REMAIN) {
        if ($return_bytes) {
            $DISK_REMAIN *= 1024;
        }
        else {
            $DISK_REMAIN /= 1024;
            $DISK_REMAIN = Cpanel::Math::_floatNum( $DISK_REMAIN, 2 );
        }
    }

    if ( !$DISK_USED ) {
        $DISK_USED = undef;
    }
    elsif ($return_bytes) {
        $DISK_USED *= 1024;
    }
    else {
        $DISK_USED /= 1024;
        $DISK_USED = Cpanel::Math::_floatNum( $DISK_USED, 2 );
    }

    if ( !$DISK_LIMIT ) {
        $DISK_LIMIT = undef;
    }
    elsif ($return_bytes) {
        $DISK_LIMIT *= 1024;
    }
    else {
        $DISK_LIMIT /= 1024;
        $DISK_LIMIT = Cpanel::Math::_floatNum( $DISK_LIMIT, 2 );
    }
    return ( $DISK_USED, $DISK_LIMIT, $DISK_REMAIN, $FILES_USED, $FILES_LIMIT, $FILES_REMAIN );
}

sub check_if_backup_directory {
    my ( $mount_point, $backup_dirs_ref ) = @_;
    foreach my $backupdir ( @{$backup_dirs_ref} ) {
        return 0 if ( ( $backupdir && $mount_point =~ /^$backupdir/o ) || $mount_point =~ /backup/ );
    }
    return 1;
}

sub parse_quota_line {
    my $line = shift;

    # Although the quota command has a -p flag which makes it much easier to parse
    # the output, to retain backward compatibility with any callers not using -p,
    # the regular expression has been expanded to handle all three types of quota
    # output.
    $line =~ m{
              \A        \s*  # leading whitespace -- should not be present
              (\S+)     \s+  # device
              (\d+)[*]* \s+  # blocks used
              (\d+)     \s+  # blocks quota
              \d+       \s+  # blocks hard limit
              (?:
                # -p was used, so it is simple to parse
                \d+        \s+   # blocks grace period
                (\d+)[*]*  \s+   # files used
                (\d+)      \s+   # files quota
                \d+        \s+   # files hard limit
                \d+        \s*   # files grace period
                \Z
              |
                # -p was not used, and the grace period column contains a string
                \d*[^\d\s]+\S* \s+   # blocks grace period
                (\d+)[*]*      \s+   # files used
                (\d+)          \s+   # files quota
                \d+                  # files hard limit
              |
                # -p was not used, and the grace period column contain whitespace only
                (\d+)[*]* \s+  # files used
                (\d+)     \s+  # files quota
                \d+            # files hard limit
              )
            }xms;
    my $device     = $1;
    my $disk_used  = $2;
    my $disk_limit = $3;

    my $files_used  = defined($4) ? $4 : defined($6) ? $6 : defined($8) ? $8 : undef;
    my $files_limit = defined($5) ? $5 : defined($7) ? $7 : defined($9) ? $9 : undef;
    return ( $device, $disk_used, $disk_limit, $files_used, $files_limit );
}

sub getmnt {
    my ($device) = @_;
    if ( $device ne '/dev/mysql' && $device ne '/dev/postgres' ) {
        $device = Cpanel::Filesys::Mounts::get_mount_point_from_device($device);
        $device = '/' if !$device || $device eq '/dev/root';
    }
    return $device;
}

1;
