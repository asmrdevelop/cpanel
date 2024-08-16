
# cpanel - Cpanel/cPAddons/Integrity.pm            Copyright 2022 cPanel, L.L.C.
#                                                           All rights reserved.
# copyright@cpanel.net                                         http://cpanel.net
# This code is subject to the cPanel license. Unauthorized copying is prohibited

package Cpanel::cPAddons::Integrity;

use strict;
use warnings;

use Cpanel::cPAddons::Class ();
use Cpanel::MD5             ();
use Cpanel::Pkgr            ();

=head1 NAME

Cpanel::cPAddons::Integrity

=head1 DESCRIPTION

Integrity and origin (vendor source) checking for cPAddons, both legacy and RPM-based.

=head1 FUNCTIONS

=head2 check(MOD, FULL_FILE)

Checks the integrity and origin of an addon.

=head3 Arguments

- MOD - String - Module name (e.g., cPanel::CMS::E107)

- MODULE_PATH - STRING - Full path to the module

=head3 Returns

Hash ref containing:

- is_3rd_party - Boolean - True if the module was provided by a third party. False if it was provided by cPanel.

- is_modified - Boolean - True if the module has been tampered with by someone other than the original provider.
(Some server admins have been known to do this in order to provide alternative versions of software through cPAddons.)
False if it is intact.

=cut

sub check {
    my ( $mod, $module_path ) = @_;
    my $response = {
        is_3rd_party => 1,
        is_modified  => 1,
    };

    my $md5    = Cpanel::MD5::getmd5sum($module_path);
    my $vendor = _extract_vendor_from_mod($mod);
    my ( $ok, $cpanelincluded ) = get_cpanel_included();

    if ( Cpanel::Pkgr::package_file_is_signed_by_cpanel($module_path) || ( exists $cpanelincluded->{$vendor}->{$mod} && $vendor eq 'cPanel' ) ) {
        $response->{is_3rd_party} = 0;
    }
    else {
        $response->{is_3rd_party} = 1;
    }

    my $module_package_name = Cpanel::Pkgr::what_provides($module_path);

    if ( Cpanel::Pkgr::verify_package($module_package_name) ) {
        $response->{is_modified} = 0;
    }
    else {
        # Fallback to legacy checking, if its a legacy addon
        my $legacy_mod_md5 = $cpanelincluded->{$vendor}->{$mod}->{'md5'};
        if ( $legacy_mod_md5 && $legacy_mod_md5 eq $md5 ) {
            $response->{is_modified} = 0;
        }
        else {
            $response->{is_modified} = 1;
        }
    }
    return $response;
}

=head2 get_cpanel_included()

Get the list of cPanel-provided addons.

=head3 Arguments

none

=head3 Returns

A list of:

- STATUS - Boolean - True on success; false on failure

- CPANELINCLUDED - Hash ref - With the following structure:

    {
        VENDOR_NAME_1 => {
            PERL_MODULE_NAME_1 => {
                desc => '...', # The summary line from the module metadata
                is_rpm => ..., # Boolean indicating whether the addon came from an RPM
            },
            PERL_MODULE_NAME_2 => {
                ...
            },
            ...
        },
        VENDOR_NAME_2 => {
            ...
        },
        ...
    }

=cut

sub get_cpanel_included {
    no strict 'refs';
    my %cpanelincluded;
    my $class_obj        = $Cpanel::cPAddons::Class::SINGLETON || Cpanel::cPAddons::Class->new();
    my %approved_vendors = $class_obj->get_approved_vendors();
    for ( keys %approved_vendors ) {
        if ( -e "/usr/local/cpanel/cpaddons/cPAddonsMD5/$_.pm" ) {
            eval " use cPAddonsMD5::$_; ";
            $cpanelincluded{$_} = \%{"cPAddonsMD5\:\:$_\:\:cpaddons"};
        }

        # Else: Still continue on and check for RPM-based addons
    }

    # Load the rpm based addons
    my $enabled_rpm_addons = $class_obj->get_rpm_packaged_modules();

    # Build the regex of all the vendors so we can do
    # the filtering in a single pass thru the list.
    my @vendors             = keys %approved_vendors;
    my $vendor_name_pattern = '^(' . join( '|', map { "\Q$_\E" } @vendors ) . ')::';
    my $vendor_names_regex  = qr/$vendor_name_pattern/;

    for my $addon ( @{$enabled_rpm_addons} ) {
        my $perl_module_name = $addon->{module};

        # Only allow modules that are from approved vendors
        next if $perl_module_name !~ m/$vendor_names_regex/;

        # Build the data structure
        my $vendor_name = $1;
        $cpanelincluded{$vendor_name}{$perl_module_name} = {
            'desc'   => $addon->{desc},
            'is_rpm' => 1,
        };
    }

    return ( 1, \%cpanelincluded );
}

sub _extract_vendor_from_mod {
    my ($mod)    = @_;
    my ($vendor) = $mod =~ m/^(\w+)::/;
    return $vendor;
}

1;
