package Cpanel::Filesys::Root;

# cpanel - Cpanel/Filesys/Root.pm                  Copyright 2022 cPanel, L.L.C.
#                                                           All rights reserved.
# copyright@cpanel.net                                         http://cpanel.net
# This code is subject to the cPanel license. Unauthorized copying is prohibited

use strict;
use warnings;

use Cpanel::LoadModule ();

our $DEV_ROOT   = q{/dev/root};
our $MTAB_PATH  = q{/etc/mtab};
our $FSTAB_PATH = q{/etc/fstab};

sub get_dev_root {

    # old school
    return $DEV_ROOT if -e $DEV_ROOT;

    # on CentOS 7 /dev/root is not available
    #   let s guess it

    # This previously used Cpanel::cPQuota but that only
    # returns filesystems that have quota enabled

    Cpanel::LoadModule::load_perl_module('Cpanel::Filesys::Info');
    my $filesys_ref = Cpanel::Filesys::Info::_all_filesystem_info();

    if ( $filesys_ref->{'/'} && $filesys_ref->{'/'}{'device'} ) {
        return $filesys_ref->{'/'}{'device'};    # This is really the device
    }

    die "Cannot guess /dev/root";
}

sub get_root_device_path {

    # /etc/fstab and then (/etc/mtab which may be a symlink to /proc/mounts) are checked only if its not in fstab
    foreach my $fs_info_source ( $FSTAB_PATH, $MTAB_PATH ) {

        # Will be closed on return.
        open( my $fh, '<', $fs_info_source ) or die "Couldn't open $fs_info_source: $!";

        while ( my $line = readline $fh ) {
            my ( $dev, $mount ) = $line =~ m/^(\/dev\/\S+)\s+(\S+)\s+/;

            local $!;    #so we can error-check the readline()
            if ( defined $mount && $mount eq '/' && -e $dev ) {
                return $dev;
            }
        }

        if ($!) {
            die "read from $fs_info_source failed: $!";
        }
    }

    die qq{Couldn't locate / mount in /etc/fstab or /etc/mtab};

}

1;
