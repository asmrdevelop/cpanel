package Cpanel::Parser;

# cpanel - Cpanel/Parser.pm                        Copyright 2022 cPanel, L.L.C.
#                                                           All rights reserved.
# copyright@cpanel.net                                         http://cpanel.net
# This code is subject to the cPanel license. Unauthorized copying is prohibited

use Cpanel::API ();

## DEPRECATED!
sub firstfile_relative_uri {
    my $result = Cpanel::API::_execute( "Parser", "firstfile_relative_uri" );
    return { 'status' => 1, 'statusmsg' => $result->data()->{'uri'}, 'error' => '' };
}

our $api1 = {
    'firstfile_relative_uri' => {
        'modify'          => 'none',
        'function'        => \&firstfile_relative_uri,    # not allowed to return html
        'legacy_function' => 2                            #Cpanel::Api::PRINT_STATUSMSG(), -- uses function if not defined -- legacy functions are allowed to print html
    },
};

1;
