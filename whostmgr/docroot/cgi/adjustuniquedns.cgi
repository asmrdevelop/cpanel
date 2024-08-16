#!/usr/local/cpanel/3rdparty/bin/perl

# cpanel - whostmgr/docroot/cgi/adjustuniquedns.cgi
#                                                  Copyright 2022 cPanel, L.L.C.
#                                                           All rights reserved.
# copyright@cpanel.net                                         http://cpanel.net
# This code is subject to the cPanel license. Unauthorized copying is prohibited

BEGIN { unshift @INC, '/usr/local/cpanel', '/usr/local/cpanel/whostmgr/docroot/cgi'; }

use strict;
use Cpanel::Form                 ();
use Cpanel::FileUtils::TouchFile ();
use Whostmgr::HTMLInterface      ();
use Whostmgr::DNS::Cluster       ();
use Whostmgr::DNS::Cluster::UI   ();

# init_app() will init ACLS and verify we have the
# cluster acl.  TODO: Refactor all the cgis
# to use Whostmgr::CgiApp::DnsCluster
Whostmgr::DNS::Cluster::UI::init_app(1);

my %FORM       = Cpanel::Form::parseform();
my $clusterdns = $FORM{'clusterdns'};

my $cluster_user = Whostmgr::DNS::Cluster::get_validated_cluster_user_from_formenv( $FORM{'cluster_user'}, $ENV{'REMOTE_USER'} );

Whostmgr::DNS::Cluster::UI::render_cluster_masquerade_include_if_available($cluster_user);

if ( !-d "/var/cpanel/cluster/$cluster_user" ) {
    mkdir "/var/cpanel/cluster/$cluster_user", 0700;
}

if ($clusterdns) {
    Cpanel::FileUtils::TouchFile::touchfile("/var/cpanel/cluster/$cluster_user/uniquedns");
    if ( !-d "/var/cpanel/cluster/$cluster_user/config" ) {
        mkdir "/var/cpanel/cluster/$cluster_user/config", 0700;
    }
}
else {
    unlink "/var/cpanel/cluster/$cluster_user/uniquedns";
}

Whostmgr::DNS::Cluster::UI::render_success_message('Your changes have been saved.');

Whostmgr::DNS::Cluster::UI::render_return_to_cluster_status($cluster_user);

Whostmgr::HTMLInterface::sendfooter();
