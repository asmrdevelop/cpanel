package Whostmgr::Addons::Legacy;

# cpanel - Whostmgr/Addons/Legacy.pm               Copyright 2022 cPanel, L.L.C.
#                                                           All rights reserved.
# copyright@cpanel.net                                         http://cpanel.net
# This code is subject to the cPanel license. Unauthorized copying is prohibited

use strict;
use warnings;

use Cpanel::RPM::Versions::File ();
use Cpanel::Update::Logger      ();

=encoding utf-8

=head1 NAME

Whostmgr::Addons::Legacy

=head1 SYNOPSIS

    $rpm_name = Whostmgr::Addons::Legacy::get_plugin_rpm_name('clamav');
    $rpm_name = Whostmgr::Addons::Legacy::get_plugin_rpm_name('munin');

    $rpm_version = Whostmgr::Addons::Legacy::get_plugin_rpm_version('clamav');
    $rpm_version = Whostmgr::Addons::Legacy::get_plugin_rpm_version('munin');

=head1 DESCRIPTION

ClamAV and Munin are “legacy” WHM plugins in that they’re versioned via
C<rpm.versions> rather than with cPanel’s YUM repo for plugins
(cf. L<Cpanel::Plugins>).

This module provides some logic for interacting with those plugins.

=head1 FUNCTIONS

=head2 $name = get_plugin_rpm_name( NAME )

Normalizes the passed-in NAME to return the actual plugin name that
YUM and other parts of this system will understand.

=cut

sub get_plugin_rpm_name {
    my ($plugin) = @_;

    die 'Need a plugin!' if !$plugin;

    # If we know the rpm to plugin mapping, do so otherwise return.
    my $rpm;

    if ( $plugin =~ m<clamav> ) {
        $rpm = 'cpanel-clamav';
    }
    elsif ( $plugin =~ m<munin> ) {
        $rpm = "cpanel-munin";
    }
    else {
        die "Unknown legacy plugin: “$plugin”";
    }

    return $rpm;
}

=head2 $version = get_plugin_rpm_version( NAME )

Returns the installed version of the plugin referred to by the
passed-in NAME. NAME is normalized via C<get_plugin_rpm_name()> as part of
this.

Returns undef if the plugin is not installed.

=cut

sub get_plugin_rpm_version {
    my ($plugin) = @_;

    die 'Need a plugin!' if !$plugin;

    # If we know the rpm to plugin mapping, do so otherwise return.
    my $rpm = get_plugin_rpm_name($plugin);
    die "Unknown plugin: “$plugin”" if !$rpm;

    my $v = Cpanel::RPM::Versions::File->new( { 'logger' => Cpanel::Update::Logger->new( { "stdout" => 0, "log_level" => "warn" } ) } );
    return $v->srpm_versions->{$rpm};
}

1;
