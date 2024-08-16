#!/usr/local/cpanel/3rdparty/bin/perl

# cpanel - base/frontend/jupiter/integration_examples/test.live.pl
#                                                  Copyright 2022 cPanel, L.L.C.
#                                                           All rights reserved.
# copyright@cpanel.net                                         http://cpanel.net
# This code is subject to the cPanel license. Unauthorized copying is prohibited

## no critic qw(RequireUseStrict)

BEGIN {
    unshift @INC, '/usr/local/cpanel';
}

use Cpanel::LiveAPI       ();
use Data::Dumper          ();
use Cpanel::Encoder::Tiny ();

sub print_dumper_html {
    my ($data) = @_;
    print Cpanel::Encoder::Tiny::safe_html_encode_str( Data::Dumper::Dumper($data) );
    return;
}

my $cpanel = Cpanel::LiveAPI->new();

print "Content-type: text/html\r\n\r\n";

print "<pre>";

print_dumper_html( $cpanel->exec('<cpanel print="cow">') );
print_dumper_html( $cpanel->api1( 'print', '', ['cow'] ) );
print_dumper_html( $cpanel->exec('<cpanel setvar="debug=0">') );
print_dumper_html( $cpanel->api( 'exec', 1, 'print', '', ['cow'] ) );
print_dumper_html( $cpanel->cpanelprint('$homedir') );
print_dumper_html( $cpanel->cpanelprint('$hasvalidshell') );
print_dumper_html( $cpanel->cpanelprint('$isreseller') );
print_dumper_html( $cpanel->cpanelprint('$isresellerlogin') );
print_dumper_html( $cpanel->exec('<cpanel Branding="file(local.css)">') );
print_dumper_html( $cpanel->exec('<cpanel Branding="image(ftpaccounts)">') );
print_dumper_html( $cpanel->api2( 'Email', 'listpopswithdisk', { 'api2_paginate' => 1, 'api2_paginate_start' => 1, 'api2_paginate_size' => 10, "acct" => 1 } ) );
print_dumper_html( $cpanel->fetch('$CPDATA{\'DNS\'}') );
print_dumper_html( $cpanel->api2( 'Ftp', 'listftpwithdisk', { "skip_acct_types" => 'sub' } ) );
print_dumper_html( $cpanel->api3( 'SSL',          'list_keys' ) );
print_dumper_html( $cpanel->api3( { 'SSL' => 1 }, 'list_keys' ) );    # should complain about an untrappable error

if ( $cpanel->cpanelif('$haspostgres') )  { print "Postgres is installed\n"; }
if ( $cpanel->cpanelif('!$haspostgres') ) { print "Postgres is not installed\n"; }
if ( $cpanel->cpanelfeature("fileman") ) {
    print "The file manager feature is enabled\n";
}
print "test complete\n";
$cpanel->end();
