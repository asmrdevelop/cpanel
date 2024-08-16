
# cpanel - Cpanel/cPAddons/Module.pm               Copyright 2022 cPanel, L.L.C.
#                                                           All rights reserved.
# copyright@cpanel.net                                         http://cpanel.net
# This code is subject to the cPanel license. Unauthorized copying is prohibited

package Cpanel::cPAddons::Module;

use strict;
use warnings;

use Cpanel::cPAddons::Class           ();
use Cpanel::cPAddons::Globals::Static ();
use Cpanel::cPAddons::Integrity       ();
use Cpanel::cPAddons::LegacyNaming    ();
use Cpanel::cPAddons::License         ();
use Cpanel::cPAddons::Notices         ();
use Cpanel::LoadModule                ();
use Cpanel::MD5                       ();

use Cpanel::Imports;

# Constants
our $DEFAULT_MININUM_PASSWORD_LENGTH = 5;

our %loaded;
my $class_obj;

=head1 NAME

Cpanel::cPAddons::Module

=head1 DESCRIPTION

Loads Module Data for a cPAddons module. Module Data is a collection of
information that includes (but is not limited to) the metadata from the
.pm file for the addon under /usr/local/cpanel/cpaddons.

=head1 MODULE NAMES

Each cPAddon has a module name associated with it. This is a 3-piece double-colon-delimited
string.

Example:

  cPanel::Blogs::WordPress
    |       |       |
     \       \       \
   Vendor  Category  App name

This name serves a few purposes:

=over

=item - It is the actual name of a Perl module on disk under /usr/local/cpanel/cpaddons that gets
loaded to obtain metadata and management routines for the cPAddon.

=item - It serves as a one-piece key representing the addon in certain data structures in the cPAddons
system.

=item - The name is sometimes split into the three pieces illustrated above so each can be presented
individually.

=back

=head1 FUNCTIONS

=head2 get_module_data(MOD)

Retrieve the Module Data for MOD.

=head3 Arguments

- MOD - String - The name of the module for which to load Module Data (e.g., cPanel::CMS::E107)

=head3 Returns

Hash ref containing:

  name             The name of the module (e.g., cPanel::CMS::E107)
  app_name         The short name of the module (e.g., E107)
  display_app_name The short name of the addon for display purposes (may be more human-friendly than app_name in some cases)
  vendor           The name of the vendor (e.g., cPanel)
  filename         The relative path to the cPAddon module from the cPAddons base directory
  fullpath         The full path to the cPAddon module
  rel_folder       The relative path to the cPAddon subdirectory under the cPAddons base directory
  meta             The metadata loaded from the cPAddon module
  version          The version loaded from the cPAddon module
  md5              The actual current MD5 digest of the cPAddon module (whether correct or incorrect)
  is_modified      True if the addon has been tampered with; false if it is intact
  is_3rd_party     True if the addon was provided by an organization other than cPanel; false if it was provided by cPanel
  supports_action  Hash ref mapping action names (e.g., install) to booleans indicating whether they are supported or not

=cut

sub get_module_data {    ##no critic(ProhibitExcessComplexity)
    my ($mod) = @_;

    my %response;
    if ( !load_module( $mod, \%response ) ) {
        my $notices = Cpanel::cPAddons::Notices::singleton();
        $notices->add_critical_error( $response{error} );
        return;
    }

    no strict 'refs';    ## no critic(ProhibitNoStrict)
    my $meta = ${"$mod\:\:meta_info"};

    my $modver = ${"$mod\:\:VERSION"};
    use strict 'refs';

    my $vendor_name = _vendor_for_mod($mod);
    my $filename    = _filename_for_mod($mod);
    my $filepath    = "$Cpanel::cPAddons::Globals::Static::base/$filename";
    my $integrity   = Cpanel::cPAddons::Integrity::check( $mod, $filepath );
    my $rel_folder  = _folder_for_mod($mod);

    # For RPMs, this is still used for manual human verification of whether
    # a security advisory applies to a particular version of an addon.
    my $md5 = Cpanel::MD5::getmd5sum($filepath);

    # Cleanup
    $meta->{'adminarea_path'} = '' if !$meta->{'adminarea_path'};
    $meta->{'adminarea_path'} =~ s/[^\w\/]//g;

    # adjust security info
    $meta->{'security_rank'}     = _limit_security_rank( $meta->{'security_rank'} );
    $meta->{'security_id_valid'} = defined $meta->{'security_id'}
      && $meta->{'security_id'} =~ m/^\d$/ ? 1 : 0;

    # adjust mysql props
    $meta->{'minimum_mysql_version_valid'} =
      ( defined $meta->{'minimum-mysql-version'} && $meta->{'minimum-mysql-version'} =~ m/\A[0-9](?:\.[0-9]+)?\z/ ) ? 1 : 0;
    $meta->{'admin_user_pass_length'} =
      ( defined $meta->{'admin_user_pass_length'} && $meta->{'admin_user_pass_length'} =~ m/\d+/ )
      ? $meta->{'admin_user_pass_length'}
      : $DEFAULT_MININUM_PASSWORD_LENGTH;
    $meta->{'admin_user_pass_length_max'} =
      ( defined $meta->{'admin_user_pass_length_max'} && $meta->{'admin_user_pass_length_max'} =~ m/\d+/ )
      ? $meta->{'admin_user_pass_length_max'}
      : 0;

    if ( $meta->{install_fields} && ref $meta->{install_fields} eq 'HASH' ) {

        # It uses the legacy format (cpanel sync) that is a hash so
        # we need to convert to an array as the modern usage expects.
        my @fields_array;

        # We are just going to sort the keys since we really don't know
        # what order to put them in since hashes dont have an intrinsic
        # order.
        foreach my $field_name ( sort keys %{ $meta->{install_fields} } ) {
            my $field = $meta->{install_fields}{$field_name};
            $field->{name} = $field_name;
            push @fields_array, $field;
        }

        $meta->{install_fields} = \@fields_array;
    }

    # Get the license info
    my $resp = Cpanel::cPAddons::License::get_license_info(
        $meta->{'license'} || '',
        $rel_folder,
    );

    if ( $resp->{error} ) {
        my $notices = Cpanel::cPAddons::Notices::singleton();
        $notices->add_warning( $resp->{error} );
    }
    else {
        $meta->{'license'}      = $resp->{'license'};
        $meta->{'license_text'} = $resp->{'license_text'};
    }

    # Determine what standard actions the module supports
    my %supports_action;
    for my $name (qw(install upgrade manage uninstall installform manageform upgradeform uninstallform)) {
        my $fn = "$mod\:\:$name";
        eval {
            my $call = \&$fn;
            $supports_action{$name} = ref $call eq 'CODE' ? 1 : 0;
        };
    }

    # defaults for display, if undefined
    if ( !exists $meta->{display} ) {
        $meta->{display} = {};
    }
    if ( !exists $meta->{display}->{versions} ) {
        $meta->{display}->{versions} = 1;
    }
    if ( !exists $meta->{display}->{upgrades} ) {
        $meta->{display}->{upgrades} = 1;
    }

    my $files_and_folders                  = $meta->{ $meta->{'version'} } || $meta->{all_versions};
    my $can_be_installed_in_root_of_domain = ( exists $files_and_folders->{'public_html_install_files'} && ref $files_and_folders->{'public_html_install_files'} eq 'ARRAY' && @{ $files_and_folders->{'public_html_install_files'} } )
      || ( exists $files_and_folders->{'public_html_install_dirs'}
        && ref $files_and_folders->{'public_html_install_dirs'} eq 'ARRAY'
        && @{ $files_and_folders->{'public_html_install_dirs'} } )
      || ( exists $files_and_folders->{'public_html_install_unknown'}
        && ref $files_and_folders->{'public_html_install_unknown'} eq 'ARRAY'
        && @{ $files_and_folders->{'public_html_install_unknown'} } ) ? 1 : 0;

    my ( $vendor, $category, $app_name ) = split '::', $mod;

    my $display_app_name = Cpanel::cPAddons::LegacyNaming::get_app_name($mod);

    return {
        name                               => $mod,
        vendor                             => $vendor_name,
        category                           => $category,
        app_name                           => $app_name,
        display_app_name                   => $display_app_name,
        filename                           => $filename,
        fullpath                           => $filepath,
        rel_folder                         => $rel_folder,
        meta                               => $meta,
        version                            => $modver,
        md5                                => $md5,
        is_modified                        => $integrity->{is_modified},
        is_3rd_party                       => $integrity->{is_3rd_party},
        supports_action                    => \%supports_action,
        can_be_installed_in_root_of_domain => $can_be_installed_in_root_of_domain,
        is_approved                        => _get_is_approved($mod),
        is_deprecated                      => _get_is_deprecated($mod),
    };
}

sub _get_is_deprecated {
    my ($module) = @_;
    my $deprecated_addons = _class_obj()->get_deprecated_addons();
    return $deprecated_addons->{$module} || 0;
}

sub _get_is_approved {
    my ($module) = @_;
    my $approved_addons = _class_obj()->get_approved_addons();
    return $approved_addons->{$module} || 0;
}

sub _filename_for_mod {
    my ($module) = @_;
    my $file = $module;
    $file =~ s/\:\:/\//g;
    $file .= '.pm';
    return $file;
}

sub _vendor_for_mod {
    my ($module) = @_;
    my $vendor = $module;

    if ( $vendor =~ m/^([^:]+)[:]{2}.*$/ ) {
        $vendor = $1;
    }
    return $vendor;
}

=head2 get_alternative_for(MODULE)

Given a module, this method looks up an alternative module that provides similar functionality from the original module's metadata.

=head3 Arguments

- MODULE - String|Hash ref - The module name (e.g., cPanel::CMS::E107) or a hash ref in the form returned from get_module_data().

=head3 Returns

Undef if no alternative is found, or a hash ref containing:

  name               String    The namespace of the alternative module (e.g., cPanel::CMS::E107)
  display_app_name   String    The pretty version of the module name (e.g., WordPress or WordPress (legacy))
  is_installed       Boolean   1 if the alternative module is installed, 0 otherwise.
  is_deprecated      Boolean   1 if the alternative module is itself deprecated, 0 otherwise.

=cut

sub get_alternative_for {
    my $module = shift;

    my $alt_module_name;
    if ( ref $module eq 'HASH' ) {
        $alt_module_name = $module->{meta}{alternative};
    }
    else {
        load_module( $module, {} ) or return undef;

        no strict 'refs';
        my $meta = ${"$module\:\:meta_info"};
        $alt_module_name = $meta->{alternative};
    }

    return undef if !$alt_module_name;
    return {
        name             => $alt_module_name,
        display_app_name => Cpanel::cPAddons::LegacyNaming::get_app_name($alt_module_name),
        is_installed     => _get_is_approved($alt_module_name),
        is_deprecated    => _get_is_deprecated($alt_module_name),
    };
}

sub _class_obj {
    return $class_obj if $class_obj;

    $class_obj =
      Cpanel::LoadModule::module_is_loaded('Cpanel::cPAddons::Globals')
      ? $Cpanel::cPAddons::Class::SINGLETON || Cpanel::cPAddons::Class->new()
      : Cpanel::cPAddons::Class->new();

    return $class_obj;
}

=head2 load_module(MOD, RESPONSE)

Load the addon module (from under /usr/local/cpanel/cpaddons/).

=head3 Arguments

- MOD - String - The module name (e.g., cPanel::CMS::E107)

- RESPONSE - Hash ref - An empty hash ref into which the outcome details will be stored

=head3 Returns

True on success; false otherwise

=head3 Side effects

On error, alters RESPONSE to contain:

- error - String - The error message

=cut

sub load_module {
    my ( $mod, $response ) = @_;
    return 1 if exists $loaded{$mod};

    local @INC = ( '/usr/local/cpanel/cpaddons', @INC );

    my %disallowed_modules = _class_obj()->get_disabled_addons();

    my $pathx = $mod;
    $pathx =~ s/\:\:/\//g;
    $pathx =~ s/\.pm$//;

    if ( $mod !~ /\A(?:(?:[A-Za-z0-9_]+::){2}[A-Za-z0-9_]+)\z/ || !-e "/usr/local/cpanel/cpaddons/$pathx.pm" ) {
        $response->{error} = 'invalid or missing module';
        $loaded{$mod} = 0;
        return 0;
    }
    elsif ( exists $disallowed_modules{$mod} ) {
        $response->{error} = locale()->maketext( 'Your hosting provider disabled the “[_1]” [asis,cPAddon].', $mod );
        $loaded{$mod} = 0;
        return 0;
    }
    eval "use $mod;";
    if ($@) {
        $response->{error} = $@;
        $loaded{$mod} = 0;
        return 0;
    }
    $loaded{$mod} = 1;
    return 1;
}

sub _limit_security_rank {
    my $security_rank = shift;
    $security_rank = 0  if $security_rank !~ m/^\d+$/;
    $security_rank = 10 if $security_rank > 10;
    return $security_rank;
}

sub _folder_for_mod {
    my $mod_name = shift;
    my $folder   = $mod_name;
    $folder =~ s/\:\:/\//g;
    return $folder;
}

1;
