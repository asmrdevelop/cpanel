#!/usr/local/cpanel/3rdparty/bin/perl

# cpanel - whostmgr/docroot/cgi/addrbl.cgi         Copyright 2022 cPanel, L.L.C.
#                                                           All rights reserved.
# copyright@cpanel.net                                         http://cpanel.net
# This code is subject to the cPanel license. Unauthorized copying is prohibited

use strict;
use Whostmgr::ACLS          ();
use Whostmgr::HTMLInterface ();
use Whostmgr::Mail::RBL     ();
use Cpanel::Encoder::Tiny   ();
use Cpanel::Form            ();
use Cpanel::Template        ();
use Whostmgr::Template      ();

Whostmgr::ACLS::init_acls();

print "Content-type: text/html\r\n\r\n";

Whostmgr::HTMLInterface::defheader();

if ( !Whostmgr::ACLS::hasroot() ) {
    print qq{
<br />
<br />
<div><h1>Permission denied</h1></div>
</body>
</html>
    };
    Whostmgr::HTMLInterface::deffooter();
    exit;
}

my %FORM = Cpanel::Form::parseform();
my %values;

if ( $FORM{'action'} eq 'addrbl' ) {
    my $url = $FORM{'url'};
    if ($url) {
        if ( $url !~ m/^(?:ftp|https?):\/\// ) {
            $url = 'http://' . $url;
        }
    }
    my $name = $FORM{'name'};
    $name =~ s/\-//g;
    my $dnslists = $FORM{'dnslists'};

    my ( $status, $txt ) = Whostmgr::Mail::RBL::add_rbl( 'rblname' => $name, 'rblurl' => $url, 'dnslists' => $dnslists );
    $values{'name'}            = Cpanel::Encoder::Tiny::safe_html_encode_str( $FORM{'name'} );
    $values{'settings-status'} = $status;
    $values{'txt'}             = $txt;
    $values{'file'}            = 'addrbl';
    print Whostmgr::Template::process( \%values );
}
elsif ( $FORM{'action'} eq 'delrbl' ) {
    my $name = $FORM{'name'};
    my ( $status, $txt ) = Whostmgr::Mail::RBL::del_rbl( 'rblname' => $name );
    $values{'name'}            = Cpanel::Encoder::Tiny::safe_html_encode_str( $FORM{'name'} );
    $values{'file'}            = 'delrbl';
    $values{'settings-status'} = $status;
    $values{'txt'}             = $txt;
    print Whostmgr::Template::process( \%values );
}
else {
    my $rbls_hr = Whostmgr::Mail::RBL::list_rbls_from_yaml() || undef;
    my $rbls_ar = $rbls_hr && [ map { { name => $_, %{ $rbls_hr->{$_} }, } } sort keys %{$rbls_hr} ];

    Cpanel::Template::process_template(
        'whostmgr',
        {
            'template_file' => 'addrbls.tmpl',
            'rbls'          => $rbls_ar,
        },
    );
}
Whostmgr::HTMLInterface::deffooter();
