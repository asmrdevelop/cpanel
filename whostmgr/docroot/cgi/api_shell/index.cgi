#!/usr/local/cpanel/3rdparty/bin/perl

# cpanel - whostmgr/docroot/cgi/api_shell/index.cgi
#                                                  Copyright 2022 cPanel, L.L.C.
#                                                           All rights reserved.
# copyright@cpanel.net                                         http://cpanel.net
# This code is subject to the cPanel license. Unauthorized copying is prohibited

use strict;

use Cpanel::App                ();
use Cpanel::Template           ();
use Cpanel::Config::LoadCpConf ();
use Whostmgr::ACLS             ();

Whostmgr::ACLS::init_acls();

$Cpanel::App::appname = 'whostmgr';

print "Content-type: text/html\r\n\r\n";

my $cpconf_ref = Cpanel::Config::LoadCpConf::loadcpconf();

#This is redundent since we are validating ACLS elsewhere as well
if ( !Whostmgr::ACLS::hasroot() || !$cpconf_ref->{'api_shell'} ) {
    print "Access Denied\n";
    exit;
}

Cpanel::Template::process_template(
    'whostmgr',
    {
        'template_file' => 'api_shell.tmpl',
    },
);
