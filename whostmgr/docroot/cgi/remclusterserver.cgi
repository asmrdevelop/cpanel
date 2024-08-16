#!/usr/local/cpanel/3rdparty/bin/perl
# cpanel - whostmgr/docroot/cgi/remclusterserver.cgi
#                                                  Copyright 2022 cPanel, L.L.C.
#                                                           All rights Reserved.
# copyright@cpanel.net                                         http://cpanel.net
# This code is subject to the cPanel license. Unauthorized copying is prohibited

use strict;

use Cpanel::Form               ();
use Whostmgr::HTMLInterface    ();
use Whostmgr::DNS::Cluster     ();
use Whostmgr::DNS::Cluster::UI ();

## no critic(RequireUseWarnings)

# init_app() will init ACLS and verify we have the
# cluster acl.  TODO: Refactor all the cgis
# to use Whostmgr::CgiApp::DnsCluster
Whostmgr::DNS::Cluster::UI::init_app(1);

my %FORM = Cpanel::Form::parseform();

my $cluster_user = Whostmgr::DNS::Cluster::get_validated_cluster_user_from_formenv( $FORM{'cluster_user'}, $ENV{'REMOTE_USER'} );

Whostmgr::DNS::Cluster::UI::render_cluster_masquerade_include_if_available($cluster_user);

my $clustermaster = $FORM{'server'};
if ( !$clustermaster ) {
    Whostmgr::DNS::Cluster::UI::fatal_error_and_exit('Server Not Specified');
}
$clustermaster =~ s/\///g;
$clustermaster =~ s/\.\.//g;

unlink(
    "/var/cpanel/cluster/$cluster_user/config/$clustermaster",
    "/var/cpanel/cluster/$cluster_user/config/$clustermaster.cache",
    "/var/cpanel/cluster/$cluster_user/config/$clustermaster-dnsrole",
    "/var/cpanel/cluster/$cluster_user/config/$clustermaster-state.json",
);

Whostmgr::DNS::Cluster::UI::render_success_message('Server removed from cluster.');

Whostmgr::DNS::Cluster::UI::render_return_to_cluster_status($cluster_user);

Whostmgr::HTMLInterface::sendfooter();
