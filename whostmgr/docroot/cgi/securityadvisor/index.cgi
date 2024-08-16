#!/usr/local/cpanel/3rdparty/bin/perl

# cpanel - whostmgr/docroot/cgi/securityadvisor/index.cgi
#                                                  Copyright 2022 cPanel, L.L.C.
#                                                           All rights reserved.
# copyright@cpanel.net                                         http://cpanel.net
# This code is subject to the cPanel license. Unauthorized copying is prohibited

#WHMADDON:addonupdates:Security Advisor Tool
#ACLS:all

package cgi::addon_securityadvisor;

use cPstrict;

use Whostmgr::ACLS          ();
use Whostmgr::HTMLInterface ();
use Cpanel::Form            ();
use Cpanel::Template        ();
use Cpanel::Comet           ();
use Cpanel::Rlimit          ();
use POSIX                   ();

# from /var/cpanel/addons/securityadvisor/perl
use Cpanel::Security::Advisor ();

run(@ARGV) unless caller();

sub run {
    _check_acls();
    my $form = Cpanel::Form::parseform();
    if ( $form->{'start_scan'} ) {
        _start_scan( $form->{'channel'} );
        exit;    ## no critic qw(NoExitsFromSubroutines)
    }
    else {
        _headers("text/html");

        my $template_file =
          -e '/var/cpanel/addons/securityadvisor/templates/main.tmpl'
          ? '/var/cpanel/addons/securityadvisor/templates/main.tmpl'
          : '/usr/local/cpanel/whostmgr/docroot/templates/securityadvisor/main.tmpl';

        Cpanel::Template::process_template(
            'whostmgr',
            {
                'template_file'            => $template_file,
                'security_advisor_version' => $Cpanel::Security::Advisor::VERSION,
            },
        );
    }

    return 1;
}

sub _check_acls {
    Whostmgr::ACLS::init_acls();

    if ( !Whostmgr::ACLS::hasroot() ) {
        _headers('text/html');
        Whostmgr::HTMLInterface::defheader('cPanel Security Advisor');
        print <<'EOM';
<br />
<br />
<div align="center"><h1>Permission denied</h1></div>
</body>
</html>
EOM
        exit;    ## no critic qw(NoExitsFromSubroutine)
    }
}

sub _headers {
    my $content_type = shift;

    print "Content-type: ${content_type}; charset=utf-8\r\n\r\n";

    return 1;
}

# Start a new scan writing to the comet channel specified
sub _start_scan {
    Cpanel::Rlimit::set_rlimit_to_infinity();    # we need to run yum :)

    my $channel = shift;
    _headers('text/json');

    if ( !$channel ) {
        print qq({"status":0,"message":"No scan channel was specified."}\n);
        return;
    }
    if ( $channel !~ m{\A[/A-Za-z_0-9]+\z} ) {
        print qq({"status":0,"message":"Invalid channel name."}\n);
        return;
    }

    my $comet = Cpanel::Comet->new();
    if ( !$comet->subscribe($channel) ) {
        print qq({"status":0,"message":"Failed to subscribe to channel."}\n);
        return;
    }

    my $pid = fork();
    if ( !defined $pid ) {
        print qq({"status":0,"message":"Failed to fork scanning subprocess."}\n);
        return;
    }
    elsif ($pid) {
        print qq({"status":1,"message":"Scan started."}\n);
        return;
    }
    else {
        POSIX::setsid();
        open STDOUT, ">&STDERR" or die "Could not redirect STDOUT to STDERR";
        open STDIN, "<", "/dev/null" or die "Could not attach STDIN to /dev/null";
        my $advisor = Cpanel::Security::Advisor->new( 'comet' => $comet, 'channel' => $channel );

        $advisor->generate_advice();
        exit;
    }
}
