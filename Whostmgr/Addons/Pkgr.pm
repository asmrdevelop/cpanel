package Whostmgr::Addons::Pkgr;

# cpanel - Whostmgr/Addons/Pkgr.pm                  Copyright 2022 cPanel, L.L.C.
#                                                           All rights reserved.
# copyright@cpanel.net                                         http://cpanel.net
# This code is subject to the cPanel license. Unauthorized copying is prohibited

use strict;
use warnings;

use Cpanel::Context               ();
use Cpanel::Pkgr                  ();
use Whostmgr::Addons::Pkgr::Cache ();

=encoding utf-8

=head1 NAME

Whostmgr::Addons::Pkgr - WHM plugin index

=head1 SYNOPSIS

    my @modules = Whostmgr::Addons::Pkgr::get_modules();

=head1 DESCRIPTION

This provides a catalog of all available WHM plugins.

=head1 FUNCTIONS

=head2 @mods = get_modules()

Returns a list of hashes: one hash per plugins. Each hash has the following
properties:

=over

=item * C<id> - The plugin’s ID string.

=item * C<pkg> - The name of the plugin’s package. For modern, YUM-based plugins
this will be the same as the C<id>.

=item * C<label> - A short, human-readable identifier for the plugin.

=item * C<description> - A longer, human-readable description of the plugin.

=item * C<version> - The available version.

=item * C<installed_version> - The installed version, or undef if not installed.

=item * C<logo> - A data URI of a logo for the plugin.

=item * C<url> - A URL for more information about the plugin. Possibly undef.

=back

=cut

sub get_modules {
    Cpanel::Context::must_be_list();

    my @modules = Whostmgr::Addons::Pkgr::Cache->load();
    die "No modules discovered by Whostmgr::Addons::Pkgr::Cache->load!" if !@modules;

    @modules = grep { defined( $_->{pkg} ) } @modules;

    my $installed_hr = Cpanel::Pkgr::query( map { $_->{'pkg'} } @modules );

    foreach my $mod (@modules) {
        $mod->{'installed_version'} = $installed_hr->{ $mod->{'pkg'} };

        # "installed_by" means that this plugin normally gets installed as a side effect of another
        # plugin being installed, so:
        #   - When that other plugin isn't installed yet, there's no need to show this one, because
        #     the way to install it is by installing the other plugin.
        #   - When both are installed, this one should be shown for uninstall purposes.
        #   - When the other plugin is installed, but this one is not, this plugin should be shown
        #     for install purposes because the normal way it gets installed is not applicable.
        $mod->{'should_hide'} = ( $mod->{'installed_by'} && !$installed_hr->{ $mod->{'installed_by'} } ) ? 1 : 0;
    }

    return @modules;
}

1;
