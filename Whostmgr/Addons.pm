package Whostmgr::Addons;

# cpanel - Whostmgr/Addons.pm                      Copyright 2022 cPanel, L.L.C.
#                                                           All rights reserved.
# copyright@cpanel.net                                         http://cpanel.net
# This code is subject to the cPanel license. Unauthorized copying is prohibited

=head1 NAME

Whostmgr::Addons -- Code for figuring out whether you need to check for addon updates.

=head1 SYNOPSIS

    use Whostmgr::Addons;

    if( Whostmgr::Addons::should_run_upgrade_script('mySuperCoolAddon') ) {
        ... # Do the needful to upgrade
        Whostmgr::Addons::set_upgrade_performed('mySuperCoolAddon') || die "Couldn't write the update version to disk!";
    }

=head1 DESCRIPTION

Basically looks at /var/cpanel/addons_update/$key and tells you whether the version matches the current cP version.

=cut

use strict;
use warnings;

use Cpanel::SafeFile      ();
use Cpanel::Version::Full ();

our $DEFAULT_KEY   = 'cpanel_provided_addons';
our $FLAG_FILE_DIR = '/var/cpanel/version/addons_update';

=head1 SUBROUTINES

=head2 should_run_upgrade_script(KEY)

For the passed in KEY corresponding to the addon, returns BOOL regarding whether an update needs to be performed.

=cut

sub should_run_upgrade_script {
    my ($key) = @_;
    if ( get_previous_version($key) ne Cpanel::Version::Full::getversion() ) {
        return 1;
    }
    return 0;
}

=head2 set_upgrade_performed(KEY)

For the passed in KEY corresponding to the addon, returns BOOL regarding whether we could mark the addon as updated to the current version.

=cut

sub set_upgrade_performed {
    my ($key) = @_;

    my $file = _flag_file($key);

    if ( my $lock = Cpanel::SafeFile::safeopen( my $fh, '>', $file ) ) {
        print {$fh} Cpanel::Version::Full::getversion();
        Cpanel::SafeFile::safeclose( $fh, $lock );
        return 1;
    }

    return 0;
}

sub _flag_file {
    my ($key) = @_;

    $key ||= $DEFAULT_KEY;

    if ( !-d $FLAG_FILE_DIR ) {

        # was a file at one point OR the path to the directory doesn't exist (-d will fail if doesn't exist too)
        unlink($FLAG_FILE_DIR) if -e _;
        require File::Path;
        File::Path::make_path( $FLAG_FILE_DIR, { 'mode' => 0700 } ) || die "Could not create directory: $FLAG_FILE_DIR";
    }

    return "$FLAG_FILE_DIR/$key";
}

=head2 get_previous_version(KEY)

For the passed in KEY corresponding to the addon, returns STRING of the currently installed addon version.
If none exist, returns '11.36.0.0'.

=cut

sub get_previous_version {
    my ($key) = @_;

    my $file = _flag_file($key);

    my $version;
    if ( -f $file and my $lock = Cpanel::SafeFile::safeopen( my $version_fh, '<', $file ) ) {
        $version = readline($version_fh);
        chomp $version;
        Cpanel::SafeFile::safeclose( $version_fh, $lock );
    }

    return ( $version || '11.36.0.0' );
}

1;
