package Whostmgr::Transfers::Session::Items::PackageRemoteRoot;

# cpanel - Whostmgr/Transfers/Session/Items/PackageRemoteRoot.pm
#                                                    Copyright 2022 cPanel L.L.C.
#                                                           All rights reserved.
# copyright@cpanel.net                                         http://cpanel.net
# This code is subject to the cPanel license. Unauthorized copying is prohibited

use strict;

our $VERSION = '1.0';

use base qw(Whostmgr::Transfers::Session::Items::FileBase Whostmgr::Transfers::Session::Items::Schema::PackageRemoteRoot);

use Cpanel::Themes::Available ();
use Whostmgr::Packages::Load  ();

sub module_info {
    my ($self) = @_;

    return {
        'dir'       => '/var/cpanel/packages',
        'perms'     => 0755,
        'item_name' => $self->_locale()->maketext('Package'),
    };
}

sub post_transfer {
    my ($self) = @_;

    _valid_theme_or_update( $self->item() );

    return ( 1, "Package migrated" );
}

sub _valid_theme_or_update {
    my ($name) = @_;

    my $pkg_ref = Whostmgr::Packages::Load::load_package($name);

    return if Cpanel::Themes::Available::is_theme_available( $pkg_ref->{'CPMOD'} );

    require Whostmgr::Packages::Info;
    require Whostmgr::Packages::Mod;

    my %defaults = Whostmgr::Packages::Info::get_defaults();
    my $updates  = {};
    $updates->{'name'}  = $name;
    $updates->{'CPMOD'} = $defaults{'cpmod'}->{'default'};
    Whostmgr::Packages::Mod::_editpkg( %{$updates} );

    return;
}

1;
