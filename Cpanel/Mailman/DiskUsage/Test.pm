package Cpanel::Mailman::DiskUsage::Test;

# cpanel - Cpanel/Mailman/DiskUsage/Test.pm        Copyright 2022 cPanel, L.L.C.
#                                                           All rights reserved.
# copyright@cpanel.net                                         http://cpanel.net
# This code is subject to the cPanel license. Unauthorized copying is prohibited

use strict;

use Cpanel::SafeFind         ();
use Cpanel::Mailman::Filesys ();

sub get_uncached_mailman_archive_dir_attachments_disk_usage {
    my $list     = shift;
    my $dir_size = 0;

    my $MAILMAN_ARCHIVE_DIR = Cpanel::Mailman::Filesys::MAILMAN_ARCHIVE_DIR();

    Cpanel::SafeFind::find(
        sub {
            $dir_size += ( lstat($File::Find::name) )[7];
        },
        "$MAILMAN_ARCHIVE_DIR/$list/attachments"
    );
    return $dir_size;
}

sub get_uncached_mailman_archive_dir_disk_usage {
    my $list     = shift;
    my $dir_size = 0;

    my $MAILMAN_ARCHIVE_DIR = Cpanel::Mailman::Filesys::MAILMAN_ARCHIVE_DIR();

    Cpanel::SafeFind::find(
        sub {
            $dir_size += ( lstat($File::Find::name) )[7];
        },
        "$MAILMAN_ARCHIVE_DIR/$list"
    );
    return $dir_size;
}

1;
