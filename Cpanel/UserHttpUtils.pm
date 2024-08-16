package Cpanel::UserHttpUtils;

# cpanel - Cpanel/UserHttpUtils.pm                 Copyright 2022 cPanel, L.L.C.
#                                                           All rights reserved.
# copyright@cpanel.net                                         http://cpanel.net
# This code is subject to the cPanel license. Unauthorized copying is prohibited

use strict;
use Cpanel::AdminBin ();
use Cpanel::ConfigFiles::Apache 'apache_paths_facade';    # see POD for import specifics

sub UserHttpUtils_init { }

sub api2_getdirindices {
    my @RSD;
    foreach my $index ( @{ Cpanel::AdminBin::adminfetch( 'apache', apache_paths_facade->file_conf(), 'DIRINDEX', 'storable', '0' ) } ) {
        push @RSD, { 'index' => $index };
    }
    return @RSD;
}

our %API = (
    'getdirindices' => {
        needs_role => 'WebServer',
        allow_demo => 1,
    },
);

sub api2 {
    my ($func) = @_;
    return { %{ $API{$func} } } if $API{$func};
    return;
}

1;
