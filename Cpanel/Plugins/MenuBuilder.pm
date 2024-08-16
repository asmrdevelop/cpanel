# cpanel - Cpanel/Plugins/MenuBuilder.pm           Copyright 2023 cPanel, L.L.C.
#                                                           All rights reserved.
# copyright@cpanel.net                                         http://cpanel.net
# This code is subject to the cPanel license. Unauthorized copying is prohibited

package Cpanel::Plugins::MenuBuilder;

use cPstrict;

our $BUILTIN_PATH = '/usr/local/cpanel/Cpanel/Plugins/menus';
our $CACHE_PATH   = '/var/cpanel/menus';
our $PLUGINS_PATH = '/var/cpanel/plugins';

use Cpanel::Mkdir            ();
use Cpanel::YAML             ();
use Cpanel::FileUtils::Write ();
use Cpanel::Imports;

=head1 MODULE

C<Cpanel::Plugins::MenuBuilder>

=head1 DESCRIPTION

C<Cpanel::Plugins::MenuBuilder> is used to build menus from configuration files. The current format is a YAML
file that contains an array of menu items. Each item has the following properties:

=over

=item key - string

The feature key used to lookup that application.

=item feature - string - optional

The feature must be enabled for it to show up in the menu.

=item priority - number

Used to calculate the order of the items in the menu from smallest to largest number.

=item icon - string

An SVG literal icon for the menu item.

=item if - string - optional

An additional conditional ExpVar used to decide if the item should be shown. This is used in conjunction with the feature check to decide if the item should be displayed.

=back

=head1 SYNOPSIS

  use Cpanel::Plugins::MenuBuilder();

  # Build the combind menu from buildin and plugins. This
  # only needs to happen at plugin install/uninstall time.
  Cpanel::Plugins::MenuBuilder::build_menu("LeftMenu");

  ...

  # Load the menu as a consumer
  my @items = Cpanel::Plugins::MenuBuilder::load_menu("LeftMenu");

=head1 FUNCTIONS

=head2 build_menu($name)

Build a combined menu from the builtin and plugin menu configuration.

=head3 ARGUMENTS

=over

=item $name - string

Name of the menu.

=back

=cut

sub build_menu ($name) {
    my $menu_name         = "$name.yaml";
    my $default_menu_file = $BUILTIN_PATH . "/$menu_name";

    my @menu = eval { Cpanel::YAML::LoadFile($default_menu_file)->@* };
    if ( my $exception = $@ ) {

        # This one is controlled by us so it better be present, readable and in the right format.
        die "Failed to load the menu file: $default_menu_file: $exception";
    }

    require File::Find::Rule;
    my @plugin_menu_files = File::Find::Rule->extras( { follow => 1 } )->file()->name("$menu_name")->in($PLUGINS_PATH);

    foreach my $plugin_menu_file (@plugin_menu_files) {
        my @more = eval { Cpanel::YAML::LoadFile($plugin_menu_file)->@* };
        if ( my $exception = $@ ) {

            # We don't want to die just because someone installed a
            # problematic plugin.
            warn "Failed to load the menu file: $plugin_menu_file: $exception";
        }
        else {
            push @menu, @more;
        }
    }

    my $sorted = [ sort { $a->{order} <=> $b->{order} } @menu ];

    Cpanel::Mkdir::ensure_directory_existence_and_mode( $CACHE_PATH, 0711 );

    my $cache_menu_file = $CACHE_PATH . "/$menu_name";
    eval { Cpanel::FileUtils::Write::overwrite( $cache_menu_file, Cpanel::YAML::Dump($sorted), 0644 ) };
    if ( my $exception = $@ ) {
        logger()->error("Failed to save the combined menu for $name with the following error: $exception");
        die "Failed to save the combined menu for $name";
    }

    return 1;
}

=head2 load_menu($name)

Load the requested menu. If plugins add menus then we load the prebuilt combined cache, otherwise
we load just the builtin list for the named menu.

=head3 ARGUMENTS

=over

=item $name - string

Name of the menu.

=back

=cut

sub load_menu ($name) {
    my $menu_name       = "$name.yaml";
    my $cache_menu_file = $CACHE_PATH . "/$menu_name";
    my @items;

    if ( -e $cache_menu_file ) {
        local $@;
        @items = eval { Cpanel::YAML::LoadFile($cache_menu_file)->@* };
        if ( my $error = $@ ) {
            warn $error;
        }
        return \@items;
    }

    # If no cache is built, then no plugins have added items, so just
    # use the buildin list.
    my $default_menu_file = $BUILTIN_PATH . "/$menu_name";
    {
        local $@;
        @items = eval { Cpanel::YAML::LoadFile($default_menu_file)->@* };
        if ( my $error = $@ ) {
            warn $error;
        }
    }

    return \@items;
}

1;
