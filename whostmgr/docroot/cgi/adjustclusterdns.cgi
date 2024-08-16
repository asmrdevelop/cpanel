#!/usr/local/cpanel/3rdparty/bin/perl

# cpanel - whostmgr/docroot/cgi/adjustclusterdns.cgi
#                                                  Copyright 2022 cPanel, L.L.C.
#                                                           All rights reserved.
# copyright@cpanel.net                                         http://cpanel.net
# This code is subject to the cPanel license. Unauthorized copying is prohibited

use cPstrict;

BEGIN { unshift @INC, '/usr/local/cpanel', '/usr/local/cpanel/whostmgr/docroot/cgi'; }

use Cpanel::Form     ();
use Cpanel::Template ();

use Whostmgr::ACLS                     ();
use Whostmgr::DNS::Cluster             ();
use Whostmgr::DNS::Cluster::UI         ();
use Cpanel::GlobalCache::Build::cpanel ();

#Allows mainCommand features to display in left nav. To ensure that ACL init happens for all the pages that use _defheader so that Left navigation and ACL checks work, as Cluster::UI::init_app does not work alone if Cpanel::Template::Plugin::Whostmgr is not imported.
Whostmgr::ACLS::init_acls();

# init_app() will init ACLS and verify we have the
# cluster acl.  TODO: Refactor all the cgis
# to use Whostmgr::CgiApp::DnsCluster
Whostmgr::DNS::Cluster::UI::init_app(1);
if ( !Whostmgr::ACLS::hasroot() ) {
    Whostmgr::DNS::Cluster::UI::fatal_error_and_exit("Permission denied");
}

my %FORM       = Cpanel::Form::parseform();
my $clusterdns = $FORM{'clusterdns'};

my $cluster_user = Whostmgr::DNS::Cluster::get_validated_cluster_user_from_formenv( $FORM{'cluster_user'}, $ENV{'REMOTE_USER'} );

Whostmgr::DNS::Cluster::UI::render_cluster_masquerade_include_if_available($cluster_user);

if ($clusterdns) {
    Whostmgr::DNS::Cluster::enable();
}
else {
    Whostmgr::DNS::Cluster::disable();
}

# Rebuild global cache so that the 'is_dnssec_supported' value is updated
eval { Cpanel::GlobalCache::Build::cpanel::build(); };

Whostmgr::DNS::Cluster::UI::render_success_message('Your changes have been saved.');

Whostmgr::DNS::Cluster::UI::render_return_to_cluster_status($cluster_user);

Cpanel::Template::process_template(
    'whostmgr',
    {
        'print'         => 1,
        'template_file' => 'master_templates/_deffooter.tmpl'
    },
);
