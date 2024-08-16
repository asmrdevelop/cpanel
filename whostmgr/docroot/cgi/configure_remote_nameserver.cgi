#!/usr/local/cpanel/3rdparty/bin/perl

# cpanel - whostmgr/docroot/cgi/configure_remote_nameserver.cgi
#                                                  Copyright 2022 cPanel, L.L.C.
#                                                           All rights reserved.
# copyright@cpanel.net                                         http://cpanel.net
# This code is subject to the cPanel license. Unauthorized copying is prohibited

use strict;
use warnings;

use Cpanel::Form               ();
use Cpanel::Template           ();
use Cpanel::DNSLib::Config     ();
use Cpanel::Template           ();
use Whostmgr::ACLS             ();
use Whostmgr::DNS::Cluster     ();
use Whostmgr::DNS::Cluster::UI ();

$Cpanel::App::appname = 'whostmgr-cgi';

local $| = 1;

#Allows mainCommand features to display in left nav. To ensure that ACL init happens for all the pages that use _defheader so that Left navigation and ACL checks work, as Cluster::UI::init_app does not work alone if Cpanel::Template::Plugin::Whostmgr is not imported.
Whostmgr::ACLS::init_acls();

# init_app() will init ACLS and verify we have the
# cluster acl.  TODO: Refactor all the cgis
# to use Whostmgr::CgiApp::DnsCluster
Whostmgr::DNS::Cluster::UI::init_app();

my %FORM = Cpanel::Form::parseform();

my $cluster_user = Whostmgr::DNS::Cluster::get_validated_cluster_user_from_formenv( $FORM{'cluster_user'}, $ENV{'REMOTE_USER'} );

#FIXME: template include /usr/local/cpanel/Cpanel/NameServer/Setup/Remote/$module/configure_remote_nameserver_header.tmpl

my $module = $FORM{'module'} || 'cPanel';
$module =~ s/\///g;

if ( $module !~ m/^[A-Za-z0-9\.]+$/ ) {
    Whostmgr::DNS::Cluster::UI::fatal_error_and_exit("Invalid Module requested: $module");
}

my $server = $FORM{'server'};    # THIS IS ONLY FILLED IN IF WE ARE EDITING AN EXISTING SERVER

my $is_edit = 0;
my $server_config;
if ( defined $server ) {
    $server_config = Cpanel::DNSLib::Config::get_cluster_member_config( $server, $cluster_user );
    if ( !Whostmgr::ACLS::hasroot() && ( !defined $ENV{'REMOTE_USER'} || $server_config->{'_cluster_config_user'} ne $ENV{'REMOTE_USER'} ) ) {

        # Resellers with clustering privs are not allowed to see/edit root's configuration for specific hosts
        $server_config = undef;
        $server        = undef;
    }
    else {
        $is_edit = 1;
        $module  = $server_config->{'module'} || 'cPanel';
    }
}

my $namespace = "Cpanel::NameServer::Setup::Remote::$module";

if ( !exists $INC{ 'Cpanel/NameServer/Setup/Remote/' . $module . '.pm' } ) {
    eval "require Cpanel::NameServer::Setup::Remote::$module;";    ## no critic(ProhibitStringyEval)
}
if ($@) {
    print STDERR $@;
}

my $config                = $namespace->get_config();
my $users_with_clustering = [];
if ( Whostmgr::ACLS::hasroot() ) {
    $users_with_clustering = Whostmgr::DNS::Cluster::get_users_with_clustering();
}

Cpanel::Template::process_template(
    'whostmgr',
    {
        'template_file' => 'configure_nameserver.tmpl',
        'breadcrumburl' => '/scripts7/clusterstatus',
        'data'          => {
            'cluster_user'          => $cluster_user,
            'config'                => $config,
            'module'                => $module,
            'is_edit'               => $is_edit,
            'hasroot'               => Whostmgr::ACLS::hasroot() ? 1 : 0,
            'users_with_clustering' => $users_with_clustering,
            'server'                => $server_config,
        },
    }
);

#FIXME: template include /usr/local/cpanel/Cpanel/NameServer/Setup/Remote/$module/configure_remote_nameserver_footer.tmpl
