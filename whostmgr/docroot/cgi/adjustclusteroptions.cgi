#!/usr/local/cpanel/3rdparty/bin/perl

# cpanel - whostmgr/docroot/cgi/adjustclusteroptions.cgi
#                                                  Copyright 2022 cPanel, L.L.C.
#                                                           All rights reserved.
# copyright@cpanel.net                                         http://cpanel.net
# This code is subject to the cPanel license. Unauthorized copying is prohibited

use strict;
use Cpanel::Form                ();
use Cpanel::Config::CpConfGuard ();
use Cpanel::DNSLib::Config      ();
use Whostmgr::HTMLInterface     ();
use Whostmgr::ACLS              ();
use Whostmgr::DNS::Cluster      ();
use Whostmgr::DNS::Cluster::UI  ();

## no critic(RequireUseWarnings)

# init_app() will init ACLS and verify we have the
# cluster acl.  TODO: Refactor all the cgis
# to use Whostmgr::CgiApp::DnsCluster
Whostmgr::DNS::Cluster::UI::init_app(1);
if ( !Whostmgr::ACLS::hasroot() ) {
    Whostmgr::DNS::Cluster::UI::fatal_error_and_exit("Permission denied");
}

my %FORM = Cpanel::Form::parseform();
my $cpconf_guard;

my $cluster_user = Whostmgr::DNS::Cluster::get_validated_cluster_user_from_formenv( $FORM{'cluster_user'}, $ENV{'REMOTE_USER'} );

Whostmgr::DNS::Cluster::UI::render_cluster_masquerade_include_if_available($cluster_user);

# Autodisable Threshold
my $autodisable_threshold = $FORM{'autodisablethreshold'};
my $a_d_t_control         = $FORM{'autodisablethreshold_control'};
if ($a_d_t_control) {
    if ( $a_d_t_control eq 'default' ) {
        $autodisable_threshold = $Cpanel::DNSLib::Config::DEFAULT_AUTODISABLE_THRESHOLD;
    }
    elsif ( $a_d_t_control eq 'disabled' ) {
        $autodisable_threshold = 0;
    }
}

if ( defined $autodisable_threshold ) {
    $autodisable_threshold = int($autodisable_threshold) >= 0 ? int($autodisable_threshold) : 0;
    $cpconf_guard ||= Cpanel::Config::CpConfGuard->new();
    unless ($cpconf_guard) {
        Whostmgr::DNS::Cluster::UI::fatal_error_and_exit("Failed to load cpanel.config!: $!");
    }
    $cpconf_guard->{'data'}->{'cluster_autodisable_threshold'} = $autodisable_threshold;
}
else {
    Whostmgr::DNS::Cluster::UI::fatal_error_and_exit("Missing failure threshold setting.");
}

$cpconf_guard ||= Cpanel::Config::CpConfGuard->new();

# Notifications of downed cluster members
$cpconf_guard->{'data'}->{'cluster_failure_notifications'} = ( defined $FORM{'cluster_failure_notifications'} && $FORM{'cluster_failure_notifications'} eq '1' ) ? '1' : '0';
$cpconf_guard->save();

Whostmgr::DNS::Cluster::UI::render_success_message('Your changes have been saved.');

Whostmgr::DNS::Cluster::UI::render_return_to_cluster_status($cluster_user);
Whostmgr::HTMLInterface::sendfooter();
