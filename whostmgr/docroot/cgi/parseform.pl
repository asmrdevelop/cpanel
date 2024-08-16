#!/usr/local/cpanel/3rdparty/bin/perl

# cpanel - whostmgr/docroot/cgi/parseform.pl       Copyright 2022 cPanel, L.L.C.
#                                                           All rights reserved.
# copyright@cpanel.net                                         http://cpanel.net
# This code is subject to the cPanel license. Unauthorized copying is prohibited

use Cpanel::Form ();

if ( !caller() ) {
    print "Content-type: text/plain\r\n\r\nThis script is not indended to be called directly.";
    exit();
}

{
    no warnings 'once';
    *parseform = \&Cpanel::Form::parseform;
}
1;
