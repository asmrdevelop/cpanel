package Whostmgr::Config::Backup::System::ModSecurity;

# cpanel - Whostmgr/Config/Backup/System/ModSecurity.pm
#                                                  Copyright 2022 cPanel, L.L.C.
#                                                           All rights reserved.
# copyright@cpanel.net                                         http://cpanel.net
# This code is subject to the cPanel license. Unauthorized copying is prohibited

use cPstrict;

=encoding utf-8

=head1 NAME

Whostmgr::Config::Backup::System::ModSecurity

=head1 DESCRIPTION

This module implements ModSecurity backups for inter-server configuration
transfers.

=cut

#----------------------------------------------------------------------

use parent qw( Whostmgr::Config::Backup::Base::JSON );

use Whostmgr::ModSecurity                   ();
use Whostmgr::ModSecurity::Settings         ();
use Whostmgr::ModSecurity::VendorList       ();
use Whostmgr::ModSecurity::ModsecCpanelConf ();

#----------------------------------------------------------------------

sub _backup ( $self, $parent ) {

    my @ret = $self->SUPER::_backup($parent);

    my $config_hr = $self->{'_backup_struct'};

    my $vendor_dir = Whostmgr::ModSecurity::config_prefix() . '/' . Whostmgr::ModSecurity::vendor_configs_dir();

    for my $vendor_hr ( @{ $config_hr->{'vendors'} } ) {
        my $vendor_id = $vendor_hr->{'vendor_id'};

        $parent->{'dirs_to_copy'}{"cpanel::system::modsecurity"}{"$vendor_dir/$vendor_id"} = { archive_dir => "vendor_$vendor_id" };
    }

    return @ret;
}

sub _get_backup_structure ($self) {    ## no critic qw(Prototype)
    my $settings_ar = Whostmgr::ModSecurity::Settings::get_settings();

    my @settings = grep { !length $_->{'missing'} } @$settings_ar;
    @settings = map {
        { %{$_}{ 'setting_id', 'state' } }
    } @settings;

    my $vendors_ar = Whostmgr::ModSecurity::VendorList::list_detail();

    my @vendors = map {
        { %{$_}{ 'vendor_id', 'installed_from', 'update', 'enabled', 'configs', 'is_rpm', 'is_pkg' } }
    } @$vendors_ar;

    for my $vendor_hr (@vendors) {
        for my $cfg_hr ( @{ $vendor_hr->{'configs'} } ) {
            $cfg_hr = { %{$cfg_hr}{ 'active', 'config' } };
        }
    }

    my $disabled_rules = Whostmgr::ModSecurity::ModsecCpanelConf->disabled_rules();

    my %config = (
        settings       => \@settings,
        vendors        => \@vendors,
        disabled_rules => $disabled_rules,
    );

    $self->{'_backup_struct'} = \%config;

    return \%config;
}

1;
