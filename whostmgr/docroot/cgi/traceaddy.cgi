#!/usr/local/cpanel/3rdparty/bin/perl

# cpanel - whostmgr/docroot/cgi/traceaddy.cgi      Copyright 2022 cPanel, L.L.C.
#                                                           All rights reserved.
# copyright@cpanel.net                                         http://cpanel.net
# This code is subject to the cPanel license. Unauthorized copying is prohibited

use Whostmgr::ACLS          ();
use Whostmgr::HTMLInterface ();

Whostmgr::ACLS::init_acls();

if ( !Whostmgr::ACLS::checkacl('mailcheck') ) {
    print "Content-type: text/html\r\n\r\n";
    Whostmgr::HTMLInterface::defheader( '', '', '/cgi/traceaddy.cgi' );
    print <<'EOM';

<br />
<br />
<div><h1>Permission denied</h1></div>
</body>
</html>
EOM
    exit;
}

exec '/usr/local/cpanel/base/backend/traceaddy.cgi';
