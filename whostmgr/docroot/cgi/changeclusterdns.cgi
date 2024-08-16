#!/usr/local/cpanel/3rdparty/bin/perl

# cpanel - whostmgr/docroot/cgi/changeclusterdns.cgi
#                                                  Copyright 2022 cPanel, L.L.C.
#                                                           All rights reserved.
# copyright@cpanel.net                                         http://cpanel.net
# This code is subject to the cPanel license. Unauthorized copying is prohibited

use strict;
use Cpanel::Encoder::Tiny      ();
use Cpanel::Form               ();
use Cpanel::DNSLib::PeerConfig ();
use Whostmgr::HTMLInterface    ();
use Whostmgr::DNS::Cluster     ();
use Whostmgr::DNS::Cluster::UI ();

## no critic(RequireUseWarnings)

# init_app() will init ACLS and verify we have the
# cluster acl.  TODO: Refactor all the cgis
# to use Whostmgr::CgiApp::DnsCluster
Whostmgr::DNS::Cluster::UI::init_app(1);

my %FORM = Cpanel::Form::parseform();

my $server            = $FORM{'server'};
my $dnsrole           = $FORM{'dnsrole'};
my $html_safe_server  = Cpanel::Encoder::Tiny::safe_html_encode_str($server);
my $html_safe_dnsrole = Cpanel::Encoder::Tiny::safe_html_encode_str($dnsrole);

my $cluster_user = Whostmgr::DNS::Cluster::get_validated_cluster_user_from_formenv( $FORM{'cluster_user'}, $ENV{'REMOTE_USER'} );

Whostmgr::DNS::Cluster::UI::render_cluster_masquerade_include_if_available($cluster_user);

$server =~ s/\.\.//g;
$server =~ s/\///g;

my ( $status, $statusmsg ) = Cpanel::DNSLib::PeerConfig::change_dns_role( $server, $dnsrole, $cluster_user );

if ($status) {
    print q{<div class="okmsg">} . Cpanel::Encoder::Tiny::safe_html_encode_str($statusmsg) . q{</div>};
    require Cpanel::DNSLib::PeerStatus;
    Cpanel::DNSLib::PeerStatus::set_change_expected( $cluster_user, $server, { dnsrole => $dnsrole } );
}
else {
    print q{<div class="errormsg">} . Cpanel::Encoder::Tiny::safe_html_encode_str($statusmsg) . q{</div>};
}

print qq{<div><br />};

Whostmgr::DNS::Cluster::UI::render_return_to_cluster_status($cluster_user);

Whostmgr::HTMLInterface::sendfooter();
