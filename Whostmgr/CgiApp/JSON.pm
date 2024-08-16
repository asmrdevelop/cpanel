package Whostmgr::CgiApp::JSON;

# cpanel - Whostmgr/CgiApp/JSON.pm                 Copyright 2022 cPanel, L.L.C.
#                                                           All rights reserved.
# copyright@cpanel.net                                         http://cpanel.net
# This code is subject to the cPanel license. Unauthorized copying is prohibited

use strict;

use base 'Whostmgr::CgiApp::Base';

sub _permission_denied {
    print "Status: 403\r\nContent-type: text/plain; charset=\"utf-8\"\r\n\r\n{'status': 403,'message': 'Forbidden'}";
    exit();
}
1;
