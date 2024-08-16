
# cpanel - Whostmgr/Addons/Manager.pm              Copyright 2022 cPanel, L.L.C.
#                                                           All rights reserved.
# copyright@cpanel.net                                         http://cpanel.net
# This code is subject to the cPanel license. Unauthorized copying is prohibited

package Whostmgr::Addons::Manager;

use strict;
use warnings;

use Cpanel::cPAddons::Filter      ();
use Cpanel::LoadModule::Utils     ();
use Cpanel::SafeDir::MK           ();
use Cpanel::SafeDir::RM           ();
use Cpanel::Pkgr                  ();
use Whostmgr::Cpaddon             ();
use Whostmgr::Cpaddon::Signatures ();
use Cpanel::Imports;

our $MODULE_BASE_DIR = "/usr/local/cpanel/cpaddons";

=head1 NAME

Whostmgr::Addons::Manager

=head1 DESCRIPTION

Provides the following addon management operations:

    * install   - downloads and enables the addon to be installed
    * uninstall - partial disable, no new installs
    * purge     - final disable, not visible in cPanel

=head1 SYNOPSIS

  my $manager = Whostmgr::Addons::Manager->new(
            CURRENT_MODULES   => {
                'company::group::module1' => {
                    ...
                }
            },
            AVAILABLE_MODULES => {
                'company::group::module1' => {
                    ...
                }
            },
            VENDORS           => {
                'company' => ...
            },

            # Flags
            debug     => 0,

            # Delegated operations
            notify_fn => sub {
                my ($message, $type, $id) = @_;
                ...
            },
            sync_cpanel_fn  => \&_cpanelsync,
            check_perl_fn   => \&_perl_c,
        );

  my $RECORD = $manage->install('company::group::module2');

=head1 CONSTRUCTOR

=head2 new()

Accepts key-value pairs:

=over

=item VENDORS - HASHREF

Where the name of key is the vendor and the value of each item is a hashref with the following format

=over

=item cphost - STRING

Host where cpanelsync requests will be fulfilled.

=item cphuri - STRING

Url at the above cphost where cpanelsync requests will be fulfilled.

=back

=item CURRENT_MODULES - HASHREF

Where the name of the key is the name of a perl module implementing the configuration and install, uninstall and upgrade actions for the addon and the value is a HASHREF with the following properties

=item AVAILABLE_MODULES - HASHREF

Where the name of the key is the name of a perl module implementing the configuration and install, uninstall and upgrade actions for the addon and the value is a HASHREF with the following properties

=item debug - FLAG

When true more messages are printed.

=item notify_fn - CODEREF

Custom output handler. Used to print formatted output to the output stream. The method has the following signature:

  send(MESSAGE, TYPE, ID)

Where the parameters are as follows:

=over

=item MESSAGE - STRING

=item TYPE - STRING

One of error, warning, info, success, header, <empty>

=item ID - STRING - optional

Unique identifier for the message.

=back

=item sync_cpanel_fn - CODEREF

cpanelsync function used to fetch addons from a vendor's server.

=item check_perl_fn - CODEREF

helper function to check if the addon config pm file compiles.

=back

=cut

sub new {
    my ( $class, %args ) = @_;
    return bless {
        VENDORS           => $args{VENDORS},
        CURRENT_MODULES   => $args{CURRENT_MODULES},
        AVAILABLE_MODULES => $args{AVAILABLE_MODULES},

        # flags
        debug      => $args{debug},
        htmlOutput => $args{htmlOutput},

        # helper methods
        _notify_fn      => $args{notify_fn},
        _sync_cpanel_fn => $args{sync_cpanel_fn},
        _check_perl_fn  => $args{check_perl_fn},
        _messages       => [],
    }, $class;
}

=head1 METHODS

=head2 install(MODULE, FORCE)

Installs a addon install on the server makeing it available for use by cpanel users.

=head3 ARGUMENTS

=over

=item MODULE - STRING

Name of the addon module to install. Will be in the format <company>::<group>::<module>. Must be listed in the AVAILABLE_MODULES collection to install.

=item FORCE - FLAG

When true, will attempt to force reinstall the current version of the addon. This is intened to be used when the addon is either incorrectly uninstalled manually or has been tampered with to restore it to its default state.

=back

=head3 RETURNS

HASHREF with the following properties. Note, for certain error conditions, only specific flags are returned in the hash.

=over

=item  version - STRING

Public version of piece of software being distributed.

=item VERSION - STRING

Internal version number for the cPAddon package.

=item is_rpm - FLAG

When true, the module is distributed as an RPM, otherwise, it is distributed using cpanelsync sources.

=item display_app_name - STRING

Optional display name for the module. Only the RPM distributions support this.

=item desc - STRING

Optional description for the module. Only the RPM distributions support this.

=item deprecated - FLAG

True when the module is deprecated. False otherwise.

=item blacklisted - FLAG

True when the module is blacklisted. False otherwise.

=item unavailable - FLAG

True when the module is unavailable from any of the configured vendors. False otherwise.

=back

=head3 SIDE EFECTS

This method makes use of the notify() callback registred in the constructor to send message to the calling application.

=cut

sub install {
    my ( $self, $module, $force ) = @_;

    my $module_class = _get_module_classname($module);

    # Skip the install if the module is not available
    if ( !$self->{AVAILABLE_MODULES}{$module} ) {
        $self->_notify( locale()->maketext( 'The requested [asis,cPAddon], “[_1]”, is not available from the currently configured vendors.', $module ), 'error', 'module_not_available_error', $module_class );
        return { unavailable => 1 };
    }

    # Skip the install if the module is blacklisted
    if ( Cpanel::cPAddons::Filter::is_blacklisted($module) ) {
        $self->_notify( locale()->maketext( 'The requested [asis,cPAddon], “[_1]”, is blacklisted and the system cannot install or update it.', $module ), 'error', 'module_blacklisted_error', $module_class );
        return { blacklisted => 1 };
    }

    # Skip the install if module is deprecated and its not already installed.
    if ( !$self->{CURRENT_MODULES}{$module}{VERSION} && Cpanel::cPAddons::Filter::is_deprecated($module) ) {
        $self->_notify( locale()->maketext( 'The requested [asis,cPAddon], ”[_1]”, is deprecated and the system cannot install it.', $module ), 'warning', 'module_deprecated_warning', $module_class );
        return { deprecated => 1 };
    }

    my $installed_ok;
    if ( $self->{CURRENT_MODULES}{$module}{VERSION} ne $self->{AVAILABLE_MODULES}{$module}{VERSION} || $force ) {

        $self->_notify( locale()->maketext( 'Installing “[_1]” …', $module ), 'header' );

        my $addon = $self->{AVAILABLE_MODULES}{$module};
        if ( $addon->{package} && $addon->{package}{rpm_name} ) {
            my $rpm_name = $addon->{package}{rpm_name};

            my $valid = $self->_validate_rpm_addon( $addon, $module );
            if ( !$valid ) {
                $self->_notify( locale()->maketext('The requested [asis,cPAddon] does not contain the needed metadata. Skipping installation …'), 'error', 'addon_missing_metadata_error', $module_class );
            }
            else {

                $self->_notify( locale()->maketext('Installing [asis,cPAddon] [asis,RPM] …') );
                $installed_ok = eval { Whostmgr::Cpaddon::install_addon($rpm_name) };
                my $exception = $@;
                if ($installed_ok) {
                    my $module_name = Cpanel::LoadModule::Utils::module_path( $addon->{namespace} );
                    my $module_path = "$MODULE_BASE_DIR/$module_name";

                    $installed_ok = $self->_validate_addon_post_install( $module_name, $module_path, $addon->{vendor} );
                    if ($installed_ok) {
                        $self->_notify( locale()->maketext('The [asis,RPM] installed.'), 'success', 'module_enable_success', $module_class );
                    }
                }
                elsif ($exception) {
                    $self->_notify( locale()->maketext( 'The [asis,RPM] installation failed: [_1]', $exception ), 'error', 'module_enable_failed', $module_class );
                }
                else {
                    $self->_notify( locale()->maketext('The [asis,RPM] installation failed.'), 'error', 'module_enable_failed', $module_class );
                }
            }
        }
        else {
            my ( $vendor, $category, $name ) = split /\:\:/, $module;
            my ( $url, $uri ) = ( $self->{VENDORS}{$vendor}{cphost}, $self->{VENDORS}{$vendor}{cphuri} );

            if ( !$url ) {
                $self->_notify( locale()->maketext( 'The system cannot determine the [asis,URL] for “[_1]”. Contact “[_2]” for support.', $module, $vendor ), 'error', 'no_vendor_url_error', $module_class );
                return;
            }

            Cpanel::SafeDir::MK::safemkdir("$MODULE_BASE_DIR/$vendor/$category/");

            my $sync_cpanel_ok = $self->_sync_cpanel(
                Whostmgr::Cpaddon::Signatures::cpanelsync_sig_flags($vendor),
                $url,
                "$uri/$vendor/$category/$name",
                "$MODULE_BASE_DIR/$vendor/$category/$name",
            );

            eval {
                require Cpanel::HttpRequest;
                Cpanel::HttpRequest->new( 'htmlOutput' => $self->{htmlOutput} )->request(
                    host     => $url,
                    url      => "$uri/$vendor/$category/$name.pm",
                    destfile => "$MODULE_BASE_DIR/$vendor/$category/$name.pm",
                    Whostmgr::Cpaddon::Signatures::httprequest_sig_flags($vendor)
                );
            };
            my $httprequest_ok = !$@ ? 1 : 0;

            my $module_name = "$vendor/$category/$name.pm";
            my $module_path = "$MODULE_BASE_DIR/$module_name";

            if ( !$sync_cpanel_ok || !$httprequest_ok ) {
                $self->_notify( locale()->maketext( 'The system failed to download the “[_1]” files. Contact “[_2]” for support.', $name, $vendor ), 'error', 'module_enable_failed', $module_class );
            }
            else {
                $installed_ok = $self->_validate_addon_post_install( $module_name, $module_path, $vendor );
                if ($installed_ok) {
                    $self->_notify( locale()->maketext( 'The system installed “[_1]”.', $name ), 'success', 'module_enable_success', $module_class );
                }
            }
        }
    }
    else {
        $installed_ok = 1;
    }

    my ( $is_rpm, $display_app_name, $desc ) = $self->_fetch_meta_data( $self->{AVAILABLE_MODULES}{$module}, $module );

    return {
        version          => $installed_ok ? $self->{AVAILABLE_MODULES}{$module}{version} : $self->{CURRENT_MODULES}{$module}{version},
        VERSION          => $installed_ok ? $self->{AVAILABLE_MODULES}{$module}{VERSION} : $self->{CURRENT_MODULES}{$module}{VERSION},
        is_rpm           => $is_rpm,
        display_app_name => $display_app_name,
        desc             => $desc,
        deprecated       => Cpanel::cPAddons::Filter::is_deprecated($module),
        blacklisted      => Cpanel::cPAddons::Filter::is_blacklisted($module),
    };
}

=head2 uninstall(MODULE, FORCE)

Uninstalls an addon from the server making it no longer available for use by cPanel users.

=head3 ARGUMENTS

=over

=item MODULE - STRING

Name of the addon module to uninstall. Will be in the format <company>::<group>::<module>.

=item FORCE - FLAG

When true, will attempt to force uninstall the current version of the addon even if it's not installed. This is intended to be used when the addon is either incorrectly uninstalled manually or something didn't finish uninstalling and left the system in a weird state.

=back

=head3 RETURNS

HASHREF with the following properties. Note, for certain error conditions, only specific flags are returned in the hash.

=over

=item  version - STRING

0 if successful

=item VERSION - STRING

0 if successful

=item is_rpm - FLAG

When true, the module is distributed as an RPM, otherwise, it is distributed using cpanelsync sources.

=item display_app_name - STRING

Optional display name for the module. Only the RPM distributions support this.

=item desc - STRING

Optional description for the module. Only the RPM distributions support this.

=item deprecated - FLAG

True when the module is deprecated. False otherwise.

=item blacklisted - FLAG

True when the module is blacklisted. False otherwise.

=back

=head3 SIDE EFFECTS

This method makes use of the notify() callback registered in the constructor to send messages to the calling application.

=cut

sub uninstall {
    my ( $self, $module, $force ) = @_;
    my $module_class = _get_module_classname($module);

    my $uninstalled_ok;
    my $is_blacklisted = Cpanel::cPAddons::Filter::is_blacklisted($module);
    if ( $self->{CURRENT_MODULES}{$module}{VERSION} || $force ) {

        if ( my $pkg_name = $self->{AVAILABLE_MODULES}{$module}{package}{rpm_name} ) {

            if ( _pkgcheck($pkg_name) ) {    #verify if the rpm is installed before proceeding

                $self->_notify( locale()->maketext( 'Uninstalling “[_1]” …', $module ), 'header' );
                $self->_notify("Removing cPAddon installer RPM …");
                $uninstalled_ok = eval { Whostmgr::Cpaddon::erase_addon($pkg_name) };    # TODO: Should YUM uninstall be run for blacklisted controls, may not be safe
                $self->_notify( $@, 'error' ) if $@;
                if ($uninstalled_ok) {
                    $self->_notify( locale()->maketext('The system removed the [asis,RPM].'), 'success', 'module_disable_success', $module_class );
                }
                else {
                    $self->_notify( locale()->maketext('The [asis,RPM] removal failed.'), 'error', 'module_disable_failed', $module_class );
                }
            }
            else {
                $uninstalled_ok = 1;
            }
        }
        else {

            # Module looks like cPAddons::Blogs::WordPress
            my ( $vendor, $category, $name ) = split /\:\:/, $module;
            my $module_dir = "$MODULE_BASE_DIR/$vendor/$category/$name";

            if ( -d $module_dir ) {

                $self->_notify( locale()->maketext( 'Uninstalling “[_1]” …', $module ), 'header' );

                if ($is_blacklisted) {
                    $self->_notify( locale()->maketext( 'The [asis,cPAddon] “[_1]” is blacklisted and the system will remove it.', $module ) );
                }

                $self->_notify( locale()->maketext('Removing [asis,cPAddon] installer …') );

                Cpanel::SafeDir::RM::safermdir($module_dir);

                if ( !-d $module_dir ) {
                    $uninstalled_ok = 1;
                    $self->_notify( locale()->maketext( 'The system removed “[_1]”.', $name ), 'success', 'module_disable_success', $module_class );    ####
                }
                else {
                    $self->_notify( locale()->maketext( 'The system could not remove “[_1]”.', $name ), 'error', 'module_disable_failed', $module_class );
                }

                if ($is_blacklisted) {

                    # We don't want anyone use this addon, so remove its pm file too
                    # so the cPanel users can't use it either from Site Software.
                    # If you want users to still be able to install it, put the module on
                    # the deprecated list in the install_cpaddons script instead of the
                    # blacklist.
                    $self->purge( $module, { blacklisted => 1 } );
                    return {
                        blacklisted => 1,
                    };
                }
            }
        }
    }
    else {
        $uninstalled_ok = 1;
    }

    my ( $is_rpm, $display_app_name, $desc ) = $self->_fetch_meta_data( $self->{AVAILABLE_MODULES}{$module}, $module );

    return {
        version          => $uninstalled_ok  ? 0       : $self->{CURRENT_MODULES}{$module}{version},
        VERSION          => $uninstalled_ok  ? 0       : $self->{CURRENT_MODULES}{$module}{version},
        is_rpm           => defined($is_rpm) ? $is_rpm : ( !!$self->{AVAILABLE_MODULES}{$module}{package}{rpm_name} ? 1 : 0 ),    # falls back if the metadata lookup failed
        display_app_name => $display_app_name || '',
        desc             => $desc             || '',
        deprecated       => Cpanel::cPAddons::Filter::is_deprecated($module),
        blacklisted      => $is_blacklisted,
    };
}

=head2 purge(MODULE, OPTS)

Purge an addon from the server entirely, meaning it will no longer be visible in cPanel at all.

This is a step beyond uninstall(), which only prevents new installations from being made while
allowing existing installations to be maintained/updated.

=head3 ARGUMENTS

=over

=item MODULE - STRING

Name of the addon module to purge. Will be in the format <company>::<group>::<module>.

=item OPTS - HASH REF - Optional

Used internally to call purge with a blacklisted addon only. Public users should never need this.

=over

=item blacklisted - FLAG

When true, will use the blacklist output messages instead of the standard one.

=back

=back

=head3 RETURNS

FLAG - When true, the purge succeeded, when false, it failed.

=head3 SIDE EFECTS

This method makes use of the notify() callback registered in the constructor to send messages to the calling application.

=cut

sub purge {
    my ( $self, $module, $OPTS ) = @_;
    $OPTS ||= {};

    if ( !$module || $module !~ m/^\w+\:\:\w+\:\:\w+$/ ) {
        $self->_notify( "The requested addon has an invalid name.", 'error', 'invalid_argument' );
        return 0;
    }

    my $module_class = _get_module_classname($module);

    my $module_name = $module;
    $module =~ s/\:\:/\//g;
    my $module_dir  = "$MODULE_BASE_DIR/$module/";
    my $module_file = "$MODULE_BASE_DIR/$module.pm";

    if ( !-d $module_dir ) {
        if ( -e $module_file ) {
            if ( _unlink($module_file) ) {
                my $message =
                  $OPTS->{blacklisted}
                  ? "Blacklisted $module_name completely removed."
                  : "$module_name completely removed.";

                $self->_notify( $message, 'success', 'module_remove_success', $module_class );
                return 1;
            }
            else {
                $self->_notify( "$module_name could not be removed: $!", 'error', 'module_remove_failed', $module_class );
                return 0;
            }
        }
        else {
            $self->_notify( "The module $module_name is already gone.", 'error', 'module_not_installed', $module_class );
            return 0;
        }
    }
    else {
        $self->_notify( "The files for $module_name have not been uninstalled yet, so the module may not be purged.", 'warning', 'module_still_enabled', $module_class );
        return 0;
    }
}

sub _validate_rpm_addon {
    my ( $self, $addon, $module ) = @_;

    my $module_class = _get_module_classname($module);

    my $ok = 1;
    if ( !$addon->{namespace} ) {
        $self->_notify( "No namespace defined for the RPM based cPAddon.", 'p', 'addon_namespace_meta_not_provided', $module_class );
        $ok = 0;
    }
    elsif ( !$addon->{application}{name} ) {
        $self->_notify( "No application name defined for the RPM based cPAddon.", 'p', 'addon_application_name_meta_not_provided', $module_class );
        $ok = 0;
    }
    elsif ( !$addon->{application}{summary} ) {
        $self->_notify( "No application summary defined for the RPM based cPAddon.", 'p', 'addon_application_summary_meta_not_provided', $module_class );
        $ok = 0;
    }
    elsif ( !$addon->{categories}
        || ( ref $addon->{categories} eq 'ARRAY' && !@{ $addon->{categories} } ) ) {
        $self->_notify( "No category list defined for the RPM based cPAddon.", 'p', 'addon_categories_meta_not_provided', $module_class );
        $ok = 0;
    }

    return $ok;
}

#----------------------------------------------
# Helper method to call the registered callbacks
#----------------------------------------------
sub _sync_cpanel {
    my ( $self, @arguments ) = @_;
    if ( $self->{_sync_cpanel_fn} && ref $self->{_sync_cpanel_fn} eq 'CODE' ) {
        return $self->{_sync_cpanel_fn}->(@arguments);
    }
    die "Developer forgot to register a _sync_cpanel_fn callback.";
}

sub _check_perl {
    my ( $self, @arguments ) = @_;
    if ( $self->{_check_perl_fn} && ref $self->{_check_perl_fn} eq 'CODE' ) {
        return $self->{_check_perl_fn}->(@arguments);
    }
    die "Developer forgot to register a check_perl_fn callback.";
}

sub _notify {
    my ( $self, $message, $type, $id, $classes ) = @_;

    $type = 'line' if !$type;

    if ( $self->{_notify_fn} && ref $self->{_notify_fn} eq 'CODE' ) {
        return $self->{_notify_fn}->( $message, $type, $id, { classes => $classes } );
    }
    die "Developer forgot to register a notify_fn callback.";
}

# For testing
sub _unlink {
    return unlink @_;
}

# Fetch the metadata for a given addon
sub _fetch_meta_data {
    my ( $self, $available_module, $module ) = @_;
    my ( $is_rpm, $display_app_name, $desc );
    eval {
        require Whostmgr::Cpaddon::Conf;
        ( $is_rpm, $display_app_name, $desc ) = Whostmgr::Cpaddon::Conf::gather_addon_conf_info( $available_module, $module );
    };
    if ( my $exception = $@ ) {
        $self->_notify( $exception, 'warning', 'failed_to_collect_metadata_warning' );
    }
    return ( $is_rpm, $display_app_name, $desc );
}

# Validate the installed addon is setup right and handle limited cases where it isn't
sub _validate_addon_post_install {
    my ( $self, $module_name, $module_path, $vendor ) = @_;

    my $module_class = _get_module_classname($module_name);

    my $ok = 1;
    if ( !-e $module_path ) {
        $ok = 0;
        $self->_notify( "The addon is missing the required ‘$module_name’ contents. Contact $vendor for support.", 'error', 'addon_pm_file_missing_error', $module_class );
    }
    elsif ( !$self->_check_perl($module_path) ) {
        $ok = 0;
        $self->_notify( "Invalid syntax in ‘$module_name’. Contact $vendor for support.", 'error', 'addon_pm_has_invalid_syntax_error', $module_class );
        unlink $module_path;    # so cpanel users can't try to install
    }
    elsif ( $self->{debug} ) {
        $self->_notify("Module ‘$module_name’ exists on disk.");
        $self->_notify("Module ‘$module_name’ compiles.");
    }

    return $ok;
}

# verify if a given RPM is already installed on the system and return the status code (0 = present, >0 = not present)
# placed in a separate sub for easier mocking
sub _pkgcheck {
    my ($pkg_name) = @_;
    return Cpanel::Pkgr::is_installed($pkg_name);
}

# generated a sensible css class name from the perl module name.
sub _get_module_classname {
    my $module       = shift;
    my $module_class = $module;
    $module_class =~ s/::/-/g;
    $module_class = 'module-' . $module_class;
    return $module_class;
}

1;
