package Whostmgr::UI;

# cpanel - Whostmgr/UI.pm                          Copyright 2022 cPanel, L.L.C.
#                                                           All rights reserved.
# copyright@cpanel.net                                         http://cpanel.net
# This code is subject to the cPanel license. Unauthorized copying is prohibited

use strict;
use warnings;

use Cpanel::JSON       ();
use Cpanel::LoadModule ();

our $method             = 'print';
our $nohtml             = 0;
our $status_block_depth = 0;

sub setstatus {
    local $| = 1;
    my $statusdata = shift;
    $statusdata =~ s/\n//g;

    $status_block_depth++;

    my $js_status = Cpanel::JSON::SafeDump($statusdata);
    if (   !$nohtml
        && !( -t STDOUT || !defined $ENV{'GATEWAY_INTERFACE'} || $ENV{'GATEWAY_INTERFACE'} !~ m/CGI/i ) ) {
        if ( $method ne 'hide' ) {
            print "<script>if (window.update_ui_status) update_ui_status($js_status);</script>" . ( qq{ } x 4096 ) . "\n";
        }
        my $indent = ( $status_block_depth > 1 ) ? " margin-left: 1rem;" : "";
        my $txt    = qq{<div style="border-bottom: 1px #ccc dotted; font: 12px 'Andale Mono', 'Courier New', Courier, monospace; padding: .5em 0;$indent">};
        $txt .= qq{<span style="white-space: pre-wrap;">$statusdata...</span><pre style="margin: 0;">};
        $method eq 'print' ? print $txt : return $txt;
    }
    else {
        $method eq 'print' ? print qq{$statusdata...} : return qq{$statusdata...};
    }
    return '';
}

sub setstatusdone {
    Cpanel::LoadModule::load_perl_module('Cpanel::MagicRevision') if !$INC{'Cpanel/MagicRevision.pm'};
    return _end_status_block( "Done", Cpanel::MagicRevision::calculate_magic_url( '/cjt/images/icons/success.png', $ENV{'REQUEST_URI'}, '/usr/local/cpanel/whostmgr/docroot' ) );
}

sub setstatuserror {
    Cpanel::LoadModule::load_perl_module('Cpanel::MagicRevision') if !$INC{'Cpanel/MagicRevision.pm'};
    return _end_status_block( "Failed", Cpanel::MagicRevision::calculate_magic_url( '/cjt/images/icons/error.png', $ENV{'REQUEST_URI'}, '/usr/local/cpanel/whostmgr/docroot' ) );
}

sub _end_status_block {
    my ( $msg, $img ) = @_;
    local $| = 1;
    $status_block_depth--;
    if ( !$nohtml && !( -t STDOUT || !defined $ENV{'GATEWAY_INTERFACE'} || $ENV{'GATEWAY_INTERFACE'} !~ /CGI/i ) ) {
        my $txt = qq{</pre><span style="white-space: pre;">...$msg</span><img style="float: right;" src="} . $img . qq{"></div>\n};
        $method eq 'print' ? print $txt : return $txt;
    }
    else {
        $method eq 'print' ? print qq{...$msg\n} : return qq{...$msg\n};
    }
    return '';
}

sub clearstatus {
    local $| = 1;
    if (   !$nohtml
        && !( -t STDOUT || !defined $ENV{'GATEWAY_INTERFACE'} || $ENV{'GATEWAY_INTERFACE'} !~ /CGI/i ) ) {
        if ( $method ne 'hide' ) { print "<script>if (window.clear_ui_status) clear_ui_status();</script>\n"; }
    }
    return '';
}

1;
