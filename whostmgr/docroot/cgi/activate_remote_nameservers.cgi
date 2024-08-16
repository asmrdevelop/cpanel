#!/usr/local/cpanel/3rdparty/bin/perl

# cpanel - whostmgr/docroot/cgi/activate_remote_nameservers.cgi
#                                                  Copyright 2022 cPanel, L.L.C.
#                                                           All rights reserved.
# copyright@cpanel.net                                         http://cpanel.net
# This code is subject to the cPanel license. Unauthorized copying is prohibited

use cPstrict;

use Cpanel::Form               ();
use Cpanel::IxHash             ();
use Cpanel::Encoder::Tiny      ();
use Whostmgr::DNS::Cluster     ();
use Whostmgr::DNS::Cluster::UI ();
use Whostmgr::HTMLInterface    ();
use Cpanel::Encoder::Tiny      ();

$Cpanel::App::appname   = 'whostmgr-cgi';
$Cpanel::IxHash::Modify = 'safe_html_encode';

local $| = 1;

# init_app() will init ACLS and verify we have the
# cluster acl.  TODO: Refactor all the cgis
# to use Whostmgr::CgiApp::DnsCluster
Whostmgr::DNS::Cluster::UI::init_app(1);

my %FORM         = Cpanel::Form::parseform();
my $cluster_user = Whostmgr::DNS::Cluster::get_validated_cluster_user_from_formenv( $FORM{'cluster_user'}, $ENV{'REMOTE_USER'} );

Whostmgr::DNS::Cluster::UI::render_cluster_masquerade_include_if_available($cluster_user);

my $pm = $FORM{'module'};
$pm =~ s/\///g;
$pm =~ s/\.yaml$//g;

my ( $status, $statusmsg, $notices );
{
    # TODO:
    #
    # Setting $ENV{'REMOTE_USER'} is a workaround to ensure all third party
    # Cpanel::NameServer::Setup::Remote modules continue to work
    #
    # We should come up with a better method to pass the user to
    # setup the nameserver remote for in the future
    #
    local $ENV{'REMOTE_USER'} = $cluster_user;
    local $@;
    ( $status, $statusmsg, $notices ) = eval { Whostmgr::DNS::Cluster::configure_provider(%FORM) };
    $statusmsg ||= $@ if !$status;
}

if ($status) {
    say '<div class="okmsg" id="activateNameserverSucceeded">' . join( '<br />', split( /\n/, Cpanel::Encoder::Tiny::safe_html_encode_str($statusmsg) ) ) . '</div>';
}
else {
    say '<div class="errormsg" id="activateNameserverFailed">' . join( '<br />', split( /\n/, Cpanel::Encoder::Tiny::safe_html_encode_str($statusmsg) ) ) . '</div>';
}

if ( length $notices ) {
    say '<div class="warningmsg">' . join( '<br />', split( /\n/, Cpanel::Encoder::Tiny::safe_html_encode_str($notices) ) ) . '</div>';
}

Whostmgr::DNS::Cluster::UI::render_return_to_cluster_status($cluster_user);
Whostmgr::HTMLInterface::deffooter();

#FIXME: template include /usr/local/cpanel/Cpanel/NameServer/Setup/Remote/$module/activate_remote_nameserver_footer.tmpl
