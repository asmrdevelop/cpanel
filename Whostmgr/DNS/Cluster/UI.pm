package Whostmgr::DNS::Cluster::UI;

# cpanel - Whostmgr/DNS/Cluster/UI.pm              Copyright 2022 cPanel, L.L.C.
#                                                           All rights reserved.
# copyright@cpanel.net                                         http://cpanel.net
# This code is subject to the cPanel license. Unauthorized copying is prohibited

use strict;
use Cpanel::Encoder::Tiny ();
use Cpanel::Locale ('lh');
use Cpanel::Exception       ();
use Whostmgr::ACLS          ();
use Whostmgr::HTMLInterface ();
use Cpanel::Form            ();
use Whostmgr::DNS::Cluster  ();

##
## TODO:
## Most of this module should be moved into templates, however the current
## DNS Clustering UIs need to be updated before this is possible
##

sub render_common {
    my ($callback) = @_;
    Whostmgr::DNS::Cluster::UI::init_app(1);

    my %FORM = Cpanel::Form::parseform();

    my $cluster_user = Whostmgr::DNS::Cluster::get_validated_cluster_user_from_formenv( $FORM{'cluster_user'}, $ENV{'REMOTE_USER'} );

    my $clustermaster = $FORM{'server'};
    return Whostmgr::DNS::Cluster::UI::fatal_error_and_exit( lh()->maketext('Server Not Specified') ) unless $clustermaster;

    my ( $success, $msg ) = $callback->( $clustermaster, $cluster_user );
    return Whostmgr::DNS::Cluster::UI::fatal_error_and_exit($msg) unless $success;
    Whostmgr::DNS::Cluster::UI::render_success_message($msg);

    Whostmgr::DNS::Cluster::UI::render_return_to_cluster_status($cluster_user);

    return Whostmgr::HTMLInterface::sendfooter();
}

sub render_cluster_masquerade_include_if_available {
    return;
}

sub render_return_to_cluster_status {
    my ($cluster_user) = @_;

    if ( !length $cluster_user ) {

        # Should never happen
        die Cpanel::Exception::create( 'MissingParameter', 'You must provide a cluster user.' );
    }

    my $html_safe_cluster_user = Cpanel::Encoder::Tiny::safe_html_encode_str($cluster_user);

    my $return_text = Cpanel::Encoder::Tiny::safe_html_encode_str( lh()->maketext('Return to Cluster Status') );

    return print qq{<div id="cluster_go_back"><br /><a href="$ENV{'cp_security_token'}/scripts7/clusterstatus?cluster_user=$html_safe_cluster_user">$return_text</a></div>};
}

sub init_app {
    my ($legacy_header_handling) = @_;

    print "Content-type: text/html\r\n\r\n" unless tell STDOUT;

    Whostmgr::ACLS::init_acls();

    if ( !Whostmgr::ACLS::checkacl('clustering') ) {

        Whostmgr::HTMLInterface::defheader( lh()->maketext('[asis,DNS] Cluster Management'), '', '/scripts7/clusterstatus' );

        fatal_error_and_exit( lh()->maketext('Permission denied') );
    }

    if ($legacy_header_handling) {
        Whostmgr::HTMLInterface::defheader( lh()->maketext('[asis,DNS] Cluster Management'), '', '/scripts7/clusterstatus' );
    }

    return 1;
}

sub render_success_message {
    my ($msg) = @_;

    my $html_safe_msg = Cpanel::Encoder::Tiny::safe_html_encode_str($msg);

    return print qq{<div class="okmsg"><h3>$html_safe_msg</h3></div>};
}

sub fatal_error_and_exit {
    my ($msg) = @_;

    my $html_safe_msg = Cpanel::Encoder::Tiny::safe_html_encode_str($msg);

    print qq{<div class="errormsg"><h3>$html_safe_msg</h3></div>};

    Whostmgr::HTMLInterface::sendfooter();

    exit(1);
}

1;
