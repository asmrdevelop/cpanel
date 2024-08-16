package Cpanel::SetLang;

# cpanel - Cpanel/SetLang.pm                       Copyright 2022 cPanel, L.L.C.
#                                                           All rights reserved.
# copyright@cpanel.net                                         http://cpanel.net
# This code is subject to the cPanel license. Unauthorized copying is prohibited

use strict;
use warnings;

use Cpanel::API ();

sub api2_setlocale {
    my %OPTS   = @_;
    my $result = Cpanel::API::wrap_deprecated(
        'Locale',
        "set_locale",
        {
            locale      => $OPTS{locale},
            'api.quiet' => 1
        }
    );
    if ( !$result->status() ) {
        $Cpanel::CPERROR{'setlang'} = $result->errors_as_string();
    }
    return;
}

our %API = (
    setlocale => { needs_feature => 'setlang', allow_demo => 1 },
);

sub api2 {
    my ($func) = @_;
    return { %{ $API{$func} } } if $API{$func};
    return;
}

1;
