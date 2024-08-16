package Whostmgr::CgiApp::HTML;

# cpanel - Whostmgr/CgiApp/HTML.pm                 Copyright 2022 cPanel, L.L.C.
#                                                           All rights reserved.
# copyright@cpanel.net                                         http://cpanel.net
# This code is subject to the cPanel license. Unauthorized copying is prohibited

use strict;

use Whostmgr::HTMLInterface ();

use base 'Whostmgr::CgiApp::Base';

sub _permission_denied {
    print "Status: 403\r\nContent-type: text/html; charset=\"utf-8\"\r\n\r\n";
    Whostmgr::HTMLInterface::defheader();
    print <<'EOM';

<br />
<br />
<div><h1>Forbidden</h1></div>
</body>
</html>
EOM
    exit();
}

1;
