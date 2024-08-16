#!/usr/local/cpanel/3rdparty/bin/perl
# cpanel - whostmgr/docroot/cgi/enableclusterserver.cgi
#                                                  Copyright 2022 cPanel, L.L.C.
#                                                           All rights Reserved.
# copyright@cpanel.net                                         http://cpanel.net
# This code is subject to the cPanel license. Unauthorized copying is prohibited

use strict;
use Cpanel::Exit               ();
use Cpanel::Encoder::Tiny      ();
use Cpanel::Form               ();
use Whostmgr::HTMLInterface    ();
use Whostmgr::ACLS             ();
use Cpanel::SafeFile           ();
use IO::Handle                 ();
use Whostmgr::DNS::Cluster::UI ();
use Cpanel::DNSLib::PeerStatus ();

## no critic(RequireUseWarnings)

# init_app() will init ACLS and verify we have the
# cluster acl.  TODO: Refactor all the cgis
# to use Whostmgr::CgiApp::DnsCluster
Whostmgr::DNS::Cluster::UI::init_app(1);

if ( !Whostmgr::ACLS::hasroot() ) {
    Whostmgr::DNS::Cluster::UI::fatal_error_and_exit("Permission denied");
}

my %FORM = Cpanel::Form::parseform();

my $server           = $FORM{'server'};
my $html_safe_server = Cpanel::Encoder::Tiny::safe_html_encode_str($server);

$server =~ s/\///g;
$server =~ s/\.\.//g;

unless ( -e '/var/cpanel/cluster/root/config/' . $server ) {
    Whostmgr::DNS::Cluster::UI::fatal_error_and_exit("$server does not appear to be configured as a member of the cluster.");
}

my $cslog_fh = IO::Handle->new();
my $cslock   = Cpanel::SafeFile::safeopen( $cslog_fh, '>', '/var/cpanel/clusterqueue/status/' . $server );
unless ($cslock) {
    Whostmgr::DNS::Cluster::UI::fatal_error_and_exit("Could not open /var/cpanel/clusterqueue/status/$server for writing.");
}

print $cslog_fh "1\n";
Cpanel::SafeFile::safeclose( $cslog_fh, $cslock );
unlink '/var/cpanel/clusterqueue/status/' . $server . '-down';

# Invalidate cache for cluster member
Cpanel::DNSLib::PeerStatus::invalidate_and_refresh_cache( $ENV{REMOTE_USER}, $server );

if ( -e '/var/cpanel/clusterqueue/status/' . $server . '-down' ) {
    Whostmgr::DNS::Cluster::UI::fatal_error_and_exit("Failed to remove /var/cpanel/clusterqueue/status/$server-down file.");
}
else {
    Whostmgr::DNS::Cluster::UI::render_success_message("$server is now enabled.");
}

Whostmgr::HTMLInterface::sendfooter();
Cpanel::Exit::exit_with_stdout_closed_first();
