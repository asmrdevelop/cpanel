package Whostmgr::API::1::RPMVersions;

# cpanel - Whostmgr/API/1/RPMVersions.pm           Copyright 2022 cPanel, L.L.C.
#                                                           All rights reserved.
# copyright@cpanel.net                                         http://cpanel.net
# This code is subject to the cPanel license. Unauthorized copying is prohibited

use strict;
use warnings;

use constant NEEDS_ROLE => {
    delete_rpm_version   => undef,
    edit_rpm_version     => undef,
    get_rpm_version_data => undef,
    list_rpms            => undef,
};

our $file;
our $dir = '/var/cpanel/rpm.versions.d';

my $versions;

my $safe_methods = {
    'install_targets'    => 1,
    'rpm_groups'         => 1,
    'rpm_locations'      => 1,
    'rpm_versions'       => 1,
    'srpms_sub_packages' => 1,
    'target_settings'    => 1,
    'file_format'        => 1,
};

sub _create_version_object {
    require Cpanel::ConfigFiles::RpmVersions;
    $file ||= $Cpanel::ConfigFiles::RpmVersions::RPM_VERSIONS_FILE;

    require Cpanel::RPM::Versions::File;
    return ( $versions ||= Cpanel::RPM::Versions::File->new( { file => $file, directory => $dir } ) );
}

sub list_rpms {
    my ( $args, $metadata ) = @_;

    _create_version_object();

    my $install  = $versions->install_hash();
    my @rpm_list = keys %{$install};
    $metadata->{'result'} = 1;
    $metadata->{'reason'} = 'OK';

    return if !scalar @rpm_list;
    return { 'rpms' => \@rpm_list };
}

sub edit_rpm_version {
    my ( $args, $metadata ) = @_;
    my $section = $args->{'section'};
    my $key     = $args->{'key'};
    my $value   = $args->{'value'};

    unless ( $section && $key && $value ) {
        $metadata->{'result'} = 0;
        $metadata->{'reason'} = 'Invalid arguments';
        return;
    }

    _create_version_object();

    my $method = "set_$section";

    if ( $safe_methods->{$section} && $versions->can($method) ) {
        my $error = $versions->$method( { 'key' => [$key], 'value' => $value } );
        if ($error) {
            $metadata->{'result'} = 0;
            $metadata->{'reason'} = $error;
            return;
        }
        $versions->save();
        $metadata->{'result'} = 1;
        $metadata->{'reason'} = 'OK';

        return { status => 1 };
    }
    else {
        $metadata->{'result'} = 0;
        $metadata->{'reason'} = "Unknown section: $method";
        return;
    }
}

sub get_rpm_version_data {
    my ( $args, $metadata ) = @_;

    my $section = $args->{'section'};
    my $key     = $args->{'key'};

    unless ($section) {
        $metadata->{'result'} = 0;
        $metadata->{'reason'} = "Invalid arguments: $section";
        return;
    }

    _create_version_object();

    if ( exists $safe_methods->{$section} && $versions->can($section) ) {
        my $data;
        if ($key) {
            $data = $versions->$section($key);

            $metadata->{'result'} = 1;
            $metadata->{'reason'} = 'OK';
            return { $key => $data };
        }
        else {
            $data = $versions->$section();

            $metadata->{'result'} = 1;
            $metadata->{'reason'} = 'OK';
            return { $section => $data };
        }
    }
    else {
        $metadata->{'result'} = 0;
        $metadata->{'reason'} = "Invalid arguments: $section";
        return;
    }
}

sub delete_rpm_version {
    my ( $args, $metadata ) = @_;
    my $section = $args->{'section'};
    my $key     = $args->{'key'};
    my $value   = $args->{'value'};

    unless ( $section && $key && $value ) {
        $metadata->{'result'} = 0;
        $metadata->{'reason'} = 'Invalid arguments';
        return;
    }

    _create_version_object();

    my $method = "delete_$section";

    if ( $safe_methods->{$section} && $versions->can($method) ) {
        $versions->$method( { 'key' => $key, 'value' => $value } );
        $versions->save();
        $metadata->{'result'} = 1;
        $metadata->{'reason'} = 'OK';

        return { status => 1 };
    }
    else {
        $metadata->{'result'} = 0;
        $metadata->{'reason'} = "Unknown section: $method";
        return;
    }
}

1;
