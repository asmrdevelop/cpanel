package Cpanel::Plugin::Install;

# cpanel - Cpanel/Plugin/Install.pm                Copyright 2022 cPanel, L.L.C.
#                                                           All rights reserved.
# copyright@cpanel.net                                         http://cpanel.net
# This code is subject to the cPanel license. Unauthorized copying is prohibited

use cPstrict;

use File::MMagic ();    # Prevents compilation into binary.

use Cpanel::Logger                         ();
use Cpanel::ServerTasks                    ();
use Cpanel::Parser::FeatureIf              ();
use Cpanel::Plugins::MenuBuilder           ();
use Cpanel::Themes::Serializer             ();
use Cpanel::Themes::SiteMap                ();
use Cpanel::Themes::Utils                  ();
use Whostmgr::AccountEnhancements::Install ();

my $logger = Cpanel::Logger->new();

sub _add_plugins_to_feature_manager {
    my ($to_install) = @_;

    my $addon_feature_dir = _addon_feature_directory();
    foreach my $plugin ( keys %{$to_install} ) {
        next if -e $addon_feature_dir . '/' . $plugin;

        if ( open( my $feature_cfg, '>', $addon_feature_dir . '/' . $plugin ) ) {
            $logger->info("Installing $plugin in Feature Manager ...");
            print {$feature_cfg} $plugin . ':' . $to_install->{$plugin} . "\n";
            close($feature_cfg);
            $logger->info("Done");
        }
    }

    return 1;
}

sub _remove_plugins_from_feature_manager {
    my ($to_uninstall) = @_;

    my $addon_feature_dir = _addon_feature_directory();
    foreach my $plugin ( keys %{$to_uninstall} ) {
        next unless -f $addon_feature_dir . '/' . $plugin;

        $logger->info("Removing $plugin from Feature Manager ...");
        unlink $addon_feature_dir . '/' . $plugin;

        if ( -e $addon_feature_dir . '/' . $plugin ) {
            $logger->warn("Unable to remove $plugin from Feature Manager");
        }
        else {
            $logger->info("Done");
        }
    }

    return 1;
}

sub _addon_feature_directory {
    return '/usr/local/cpanel/whostmgr/addonfeatures';
}

sub install_plugin {    ## no critic qw(Subroutines::ProhibitExcessComplexity)
    my ( $staging_dir, $theme, $delete ) = @_;

    $logger->info( $delete ? "Uninstalling from $theme" : "Installing to $theme" );

    # build theme object(s)
    my $theme_docroot = Cpanel::Themes::Utils::get_theme_root($theme);

    if ( !-d $theme_docroot ) {
        $logger->warn( "The specified theme [" . $theme . "] does not exist." );
        return 0;
    }

    # several methods require REMOTE_USER set to function.
    if ( !defined( $ENV{REMOTE_USER} ) ) {
        require Cpanel::PwCache;
        $ENV{REMOTE_USER} = Cpanel::PwCache::getpwuid($<);
    }

    my %feature_list = ();
    eval {
        # build JSON object
        my $to_install           = Cpanel::Themes::Serializer::get_serializer_obj( 'JSON', $staging_dir );
        my $plugins              = $to_install->links();
        my $account_enhancements = $to_install->account_enhancements();

        # verify we are using a PNG image or svg for the plugin(s)
        foreach my $plugin ( @{$plugins} ) {

            if ( !$delete && exists $plugin->{icon} && defined $plugin->{icon} ) {
                _check_icon_type($plugin);    # dies if invalid
            }

            # Account Enhancements
            # The user can define multiple plugins, and multiple enhancements for each

            if ($delete) {
                my @warnings = Whostmgr::AccountEnhancements::Install::uninstall( $plugin->{'id'} );
                $logger->warn($_) for @warnings;
            }
            else {
                my @plugins_enhancements = grep { exists $_->{'plugin_id'} && $_->{'plugin_id'} eq $plugin->{'id'} } @{$account_enhancements};
                foreach my $enhancement (@plugins_enhancements) {
                    eval { Whostmgr::AccountEnhancements::Install::install( $plugin->{'id'}, $enhancement ) };
                    $logger->warn($@) if $@;
                }
            }

            if ( $delete || !defined $plugin->{'featuremanager'} || ( $plugin->{'featuremanager'} ne '0' && $plugin->{'featuremanager'} ne 'false' ) ) {
                $plugin->{feature}     ||= $plugin->{id};
                $plugin->{description} ||= $plugin->{name};

                if ( !$delete ) {
                    my $val = Cpanel::Parser::FeatureIf::featureresult( $plugin->{feature} );
                    unless ( $val eq '0' || $val eq '1' ) {
                        $logger->die("Feature name for $plugin->{name} is invalid: $plugin->{feature}");
                    }
                }

                if ( $plugin->{feature} && $plugin->{description} ) {
                    $feature_list{ $plugin->{feature} } = $plugin->{description};
                }
            }
        }

        # verify we are using a PNG image or svg for the plugin group(s)
        foreach my $plugin_group ( @{ $to_install->groups() } ) {
            last if $delete;

            if ( exists $plugin_group->{icon} && defined $plugin_group->{icon} ) {
                _check_icon_type($plugin_group);    # dies if invalid
            }
        }

        # run add_link on theme object
        my $sitemap_obj = Cpanel::Themes::SiteMap->new(
            'path' => $theme_docroot,
        );

        if ( $sitemap_obj->load() ) {
            if ($delete) {
                $sitemap_obj->delete_link( $to_install->links );
                $sitemap_obj->delete_group( $to_install->groups );
            }
            else {
                $sitemap_obj->add_group( $to_install->groups );
                $sitemap_obj->add_link( $to_install->links );
            }
        }
        else {
            if ($delete) {
                $logger->warn("The system failed to load and update the SiteMap while installing plugin: The plugin may not appear since the group and link could not be added to “$theme”");
            }
            else {
                $logger->warn("The system failed to load and update the SiteMap while uninstalling plugin: The plugin may still appear in “$theme” even though it is uninstalled");

            }
        }

    };

    my $val;
    if ($@) {
        $logger->warn( "Error in " . ( $delete ? "uninstalling" : "installing" ) . " plugin: " . $@ );
        $val = 0;
    }
    else {
        $val = $delete ? _remove_plugins_from_feature_manager( \%feature_list ) : _add_plugins_to_feature_manager( \%feature_list );
    }

    _build_menus(qw/LeftMenu/) if _has_custom_menus($staging_dir);
    _schedule_rebuild_sprites();
    _schedule_verify_api_spec_files();

    return $val;
}

# Determine if the plugin base has a single directory in it
# if so, we'll assume that that directory is where the actual plugin file is
#
# This is to account for normal archive best practices where the archive
# contains directories at it's top level structure.
sub determine_plugin_docroot {
    my ($docroot) = @_;

    my $count = 0;
    my $dir;

    opendir( my $plugin_dh, $docroot );
    foreach my $file ( readdir($plugin_dh) ) {
        next if $file =~ /^\./;    # skip if path begins with a .
        $count++;
        $dir = $file if -d $docroot . '/' . $file;
    }
    closedir $plugin_dh;

    # if the only file in the archive is a directory
    # then we'll assume that directory is our docroot
    if ( defined $dir && $count == 1 ) {
        return $docroot . '/' . $dir;
    }

    # if that's not the case, just return the docroot;
    return $docroot;
}

sub _schedule_rebuild_sprites {
    $logger->info("Scheduling task to update sprites");

    local $@;
    eval { Cpanel::ServerTasks::schedule_task( ['SpriteTasks'], 1, 'sprite_generator' ); };

    if ($@) {
        $logger->warn( 'Failed to schedule sprite_generator: ' . $@ );
    }
    return;
}

sub _schedule_verify_api_spec_files {
    $logger->info("Scheduling task to update API spec files");
    local $@;
    eval { Cpanel::ServerTasks::schedule_task( ['API'], 1, "verify_api_spec_files" ); };
    if ($@) {
        $logger->warn( 'Failed to schedule verify_api_spec_files: ' . $@ );
    }
    return;
}

sub _check_icon_type {
    my ($plugin_or_plugin_group) = @_;

    my $class = ref $plugin_or_plugin_group;
    my $ext   = File::MMagic->new->checktype_filename( $plugin_or_plugin_group->{icon} );

    my $icon_path = $plugin_or_plugin_group->{icon};
    if ( length $icon_path && !-e $icon_path ) {
        $logger->die("Icon file “$icon_path” does not exist.");
    }
    if ( $icon_path =~ /\.svg$/i ) {
        $ext = 'svg';
    }

    if ( $ext ne 'svg' ) {
        if ( !defined $class ) {
            $logger->die("Icon must be associated with a feature or group.");
        }
        elsif ( $class eq 'Cpanel::Themes::Assets::Group' ) {
            $logger->die( "Group plugins require icon images to be in SVG format. " . $icon_path . " does not meet this requirement." );
        }
        elsif ( $class eq 'Cpanel::Themes::Assets::Link' && $ext !~ /png$/ ) {
            $logger->die( "Link plugins require icon images to be in SVG or PNG format. " . $icon_path . " does not meet this requirement." );
        }
    }

    return;
}

sub _build_menus (@menu_names) {
    foreach my $menu_name (@menu_names) {
        Cpanel::Plugins::MenuBuilder::build_menu($menu_name);
    }
    return 1;
}

=head1 FUNCTIONS

=head2 _has_custom_menus($staging_dir)

Check if the plugin includes any menus.

=head3 ARGUMENTS

=over

=item $staging_dir - string

The path to the plugins staging directory

=back

=head3 RETURNS

True if there are any files in the /var/cpanel/plugins/<plugin>/menu directory. False otherwise.

=cut

sub _has_custom_menus ($staging_dir) {
    my $dir = "$staging_dir/menu";

    opendir my $h, $dir or return 0;

    while ( defined( my $entry = readdir $h ) ) {
        return 1 unless $entry =~ m/^\.{1,2}$/;
    }

    return 0;
}

1;
