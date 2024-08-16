package Cpanel::Plugins::DynamicUI;

# cpanel - Cpanel/Plugins/DynamicUI.pm             Copyright 2022 cPanel, L.L.C.
#                                                           All rights reserved.
# copyright@cpanel.net                                         http://cpanel.net
# This code is subject to the cPanel license. Unauthorized copying is prohibited

use strict;
use warnings;

use Cpanel::CachedDataStore;
use Whostmgr::ACLS;

=encoding utf-8

=head1 NAME

Cpanel::Plugins::DynamicUI

=head1 SYNOPSIS

 use Cpanel::Plugins::DynamicUI ();
 my $plugins = Cpanel::Plugins::DynamicUI::get();
 foreach my $plugin (@$plugins) {
     # Do somthing with the plugin menu data.
 }

=head1 DESCRIPTION

Retrive the menu data for the plugins.

=head1 FUNCTIONS

=head2 cache_file_path()

The path to the configured plugins registry.

=cut

sub cache_file_path { return '/var/cpanel/pluginscache.yaml'; }

=head2 get()

Retrieve the list of plugins the user has access to from the
list of all installed plugin applications.

=head3 RETURNS

An ARRAYREF of HASHREF with the following structure:

=over

=item uniquekey - string

A unique identifier for the application linked here.

=item showname - string

A name we show the the users in the user interface for this application.

=item cgi - string

The view controller CGI related to the plugin that handles server side page generation.

=item icon - string - optional

The name of the icon in the addon_plugins/ folder. You must provide one of
icon or tagname.

=item tagname - string - optional

The name of the application icon png under the icons/ folder. You must provide one of
icon or tagname.

=item target - string - optional

The name of the target window to open the application into.

=back

=cut

sub get {
    my $installed_plugins = -e cache_file_path() && Cpanel::CachedDataStore::loaddatastore( cache_file_path() );
    unless ($installed_plugins) {
        return [];
    }

    my @available_plugins;
    foreach my $plugin ( @{ $installed_plugins->{'data'}{'addons'} } ) {

        if ( !scalar @{ $plugin->{'acllist'} } ) {
            push @available_plugins, $plugin;
        }
        else {
            foreach my $acl ( @{ $plugin->{'acllist'} } ) {
                if ( $acl eq 'any' || Whostmgr::ACLS::checkacl($acl) ) {
                    push @available_plugins, $plugin;
                    last;
                }
            }
        }
    }

    return \@available_plugins;
}

1;
