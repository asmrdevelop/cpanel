#!/usr/local/cpanel/3rdparty/bin/perl -T

# cpanel - cgi-sys/universal-redirect.cgi          Copyright 2022 cPanel, L.L.C.
#                                                           All rights reserved.
# copyright@cpanel.net                                         http://cpanel.net
# This code is subject to the cPanel license. Unauthorized copying is prohibited

use Cpanel::Redirect ();

$ENV{'PATH'} = '/bin:/sbin:/usr/bin:/usr/sbin';

my ($zero) = reverse( split( /\//, $0 ) );

Cpanel::Redirect::redirect(
    service => ( $zero =~ /whm/     ? 'whm' : ( $zero =~ /^w|\s+w/ ? 'webmail' : 'cpanel' ) ),
    ssl     => ( $zero =~ /^s|\s+s/ ? 1     : 0 )
);
