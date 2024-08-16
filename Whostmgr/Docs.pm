package Whostmgr::Docs;

# cpanel - Whostmgr/Docs.pm                        Copyright 2022 cPanel, L.L.C.
#                                                           All rights reserved.
# copyright@cpanel.net                                         http://cpanel.net
# This code is subject to the cPanel license. Unauthorized copying is prohibited

use strict;
use warnings;

use Cpanel::Logger ();

sub fetch_key {
    my $module = shift;

    if ( !defined $module ) {
        Cpanel::Logger->new->warn("Cannot Load an empty module for Whostmgr::Docs::");
        return;
    }

    ($module) = $module =~ /([A-Za-z0-9]+)/;

    if ( !exists $INC{"Whostmgr/Docs/$module.pm"} ) {
        eval "require Whostmgr::Docs::$module;";
        if ($@) {
            Cpanel::Logger->new->warn("Failed to Load Whostmgr::Docs::$module: $@");
            return;
        }
    }
    my $result = eval 'Whostmgr::Docs::' . $module . '::fetch_key(@_);';
    if ($@) {
        Cpanel::Logger->new->warn("Failed to fetch_key in Whostmgr::Docs::$module: $@");
        return;
    }
    return $result;
}
1;
