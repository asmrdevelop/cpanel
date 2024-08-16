package Cpanel::Template::Plugin::API_Shell;

# cpanel - Cpanel/Template/Plugin/API_Shell.pm     Copyright 2022 cPanel, L.L.C.
#                                                           All rights reserved.
# copyright@cpanel.net                                         http://cpanel.net
# This code is subject to the cPanel license. Unauthorized copying is prohibited

use cPstrict;

use base 'Template::Plugin';

use Cpanel::ApiInfo::UAPI ();    # PPI USE OK - Used right below here with _get_api_spec
use Cpanel::ApiInfo::Api2 ();    # PPI USE OK - Used right below here with _get_api_spec
use Cpanel::ApiInfo::Whm1 ();    # PPI USE OK - Used right below here with _get_api_spec

sub _sort_case_insensitve : prototype($$) ( $x, $y ) {    ## no critic(Prototypes)
    return lc $x cmp lc $y;
}

sub uapi_functions {
    return _format_cpanel_api_spec( _get_api_spec('UAPI') );
}

sub api2_functions {
    return _format_cpanel_api_spec( _get_api_spec('Api2') );
}

sub whm1_functions {
    return _get_api_spec('Whm1');
}

sub _format_cpanel_api_spec {
    my ($module_funcs_hr) = @_;

    my @formatted_functions;
    for my $module ( keys %$module_funcs_hr ) {
        push @formatted_functions, map { $module . "::$_" } @{ $module_funcs_hr->{$module} };
    }

    return [ sort _sort_case_insensitve @formatted_functions ];
}

sub _get_api_spec {
    my ($api_version) = @_;

    my $spec_obj = "Cpanel::ApiInfo::$api_version"->new();
    return $spec_obj->get_data();
}

1;
