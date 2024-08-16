package Whostmgr::DiskUsage;

# cpanel - Whostmgr/DiskUsage.pm                   Copyright 2022 cPanel, L.L.C.
#                                                           All rights reserved.
# copyright@cpanel.net                                         http://cpanel.net
# This code is subject to the cPanel license. Unauthorized copying is prohibited

use strict;

use Cpanel::DiskLib ();

sub _FAIL_DISK_USAGE_THRESHOLD {
    return 99;
}

sub _DISABLE_DISK_FREE_CHECK_TOUCHFILE {
    return '/var/cpanel/disablediskfreecheck';
}

sub _MOUNTS_TO_CHECK {
    return map { $_ => undef } qw(
      /
      /usr
      /var
    );
}

sub checkdisk {
    my ( $ok, $msg ) = verify_partitions();

    if ( !$ok ) {
        print "$msg </h3></body></html>";
        exit;
    }
}

#Returns two-arg format.
sub verify_partitions {
    return 1 if -e _DISABLE_DISK_FREE_CHECK_TOUCHFILE();

    my @nearly_full = find_nearly_full_partitions();

    if (@nearly_full) {
        eval 'require Cpanel::Locale' if !$INC{'Cpanel/Locale.pm'};

        my $locale = Cpanel::Locale->get_handle();
        return ( 0, $locale->maketext( 'The following disk [numerate,_1,partition is,partitions are] almost full: [list_and,_2]. You must remove unused files in [numerate,_1,that partition,those partitions] before proceeding.', scalar(@nearly_full), \@nearly_full ) );
    }

    return 1;
}

sub find_nearly_full_partitions {
    my $diskfree_ref = Cpanel::DiskLib::get_disk_used_percentage_with_dupedevs();

    my @nearly_full_partitions;

    my %mounts_to_check = _MOUNTS_TO_CHECK();

    foreach my $device (@$diskfree_ref) {
        my $mount = $device->{'mount'};
        next if !exists $mounts_to_check{$mount};

        if ( $device->{'percentage'} > _FAIL_DISK_USAGE_THRESHOLD() ) {
            push @nearly_full_partitions, $mount;
        }
    }

    return @nearly_full_partitions;
}

1;
