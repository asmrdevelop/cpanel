#!/usr/local/cpanel/3rdparty/bin/perl

# cpanel - whostmgr/docroot/cgi/process_tail.cgi   Copyright 2022 cPanel, L.L.C.
#                                                           All rights reserved.
# copyright@cpanel.net                                         http://cpanel.net
# This code is subject to the cPanel license. Unauthorized copying is prohibited

package cgi::process_tail;

use strict;
use CGI;
use Whostmgr::ACLS     ();
use Cpanel::LoadModule ();
use Carp;

$| = 1;

my $q = CGI->new;

my $process_name = $q->param('process');

if ( $process_name !~ m/^[a-zA-Z0-9\_]+$/ ) {
    exit;
}

my $process_module = 'Cpanel::ProcessTail::' . $process_name;
Cpanel::LoadModule::load_perl_module($process_module);

my $params = $q->Vars;

if ( my $resp = $process_module->can('run_tail') ) {
    exit( run() ) unless caller;
}

sub run {

    Whostmgr::ACLS::init_acls();
    if ( !Whostmgr::ACLS::hasroot() ) {
        return 1;
    }
    _html_header();
    $process_module->run_tail($params);
    _html_footer();

    return 0;
}

sub _html_header {
    my $security_token = $ENV{'cp_security_token'} || '';

    print "Content-type: text/html\r\n\r\n";
    print "<!DOCTYPE html>\n";
    print "<html>\n";
    print "<head>\n";
    print qq(<link rel="stylesheet" type="text/css" href="${security_token}/css2/tail.css">\n);
    _follow_output_js();
    print "</head>";
    print "<body>";
    return;
}

sub _html_footer {

    print "</body>\n";
    print "</html>";

    return;
}

sub _follow_output_js {

    print q[
        <script type='text/javascript'>
           self.update_ui_status = parent.update_ui_status;
           self.update_percent = parent.update_percent;

           var finished = false;
           var autoScroll = true;

           var Enable_Scroll = function () {
              if (document.body) {
                 document.body.style.background='white';
              }
              Do_Scroll = setInterval(scroll_bottom,100);
              autoScroll = true;
           }

           var Disable_Scroll = function () {
              document.body.style.background='#ddffdd';
              clearInterval(Do_Scroll);
              autoScroll = false;
           }

           var scroll_bottom = function () {
              if (autoScroll && document.body) {
                 window.scrollTo(0,document.body.scrollHeight);
              }
           }

           var logFinished = function () {
                finished = true;
                if (autoScroll) {
                    // let the auto scrolling continue for
                    // a bit, giving it time to scroll to the
                    // bottom of the log output before we
                    // turn it off
                    window.setTimeout(Disable_Scroll, 300);
                }
            }

            document.onclick = function () {
                if (finished) {
                    return;
                }
                else if (autoScroll) {
                    Disable_Scroll();
                }
                else {
                    Enable_Scroll();
                }
            }

           Enable_Scroll();
        </script>
    ];

    return;
}

1;
