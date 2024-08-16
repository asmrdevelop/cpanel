package Cpanel::API::Parser;

# cpanel - Cpanel/API/Parser.pm                    Copyright 2022 cPanel, L.L.C.
#                                                           All rights reserved.
# copyright@cpanel.net                                         http://cpanel.net
# This code is subject to the cPanel license. Unauthorized copying is prohibited

use strict;
## no critic qw(TestingAndDebugging::RequireUseWarnings) -- not fully vetted for warnings

use Cpanel::Parser::Vars ();
use Cwd                  ();

sub firstfile_relative_uri {
    ## no args
    my ( $args, $result ) = @_;
    my $uri = $Cpanel::Parser::Vars::firstfile;
    $uri =~ s/^\./Cwd::fastcwd()/e;
    $uri =~ s!^/usr/local/cpanel/base/?!/!;
    $result->data( { uri => $uri } );
    return 1;
}

our %API = (
    firstfile_relative_uri => { allow_demo => 1 },
);

1;
