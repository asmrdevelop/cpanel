package Whostmgr::Transfers::Session::Items;

# cpanel - Whostmgr/Transfers/Session/Items.pm     Copyright 2022 cPanel, L.L.C.
#                                                           All rights reserved.
# copyright@cpanel.net                                         http://cpanel.net
# This code is subject to the cPanel license. Unauthorized copying is prohibited

use strict;

use Try::Tiny;

use Cpanel::LoadModule                   ();
use Cpanel::Locale                       ();
use Whostmgr::Transfers::Session::Config ();

my $locale;

sub available {
    return { reverse %Whostmgr::Transfers::Session::Config::ITEMTYPE_NAMES };
}

sub schema {
    my ($module) = @_;

    my $available_modules = available();

    if ( !$available_modules->{$module} ) {
        return ( 0, _locale()->maketext( "The transfer session module “[_1]” does not exist.", $module ) );
    }
    my $object_type = "Whostmgr::Transfers::Session::Items::Schema::$module";

    my $err;
    try {
        Cpanel::LoadModule::load_perl_module($object_type);
    }
    catch { $err = $_; };

    if ($err) {
        return ( 0, $err->to_locale_string() );
    }

    return ( 1, "$object_type"->schema() );
}

sub _locale {
    return $locale ||= Cpanel::Locale->get_handle();
}

1;
