package Cpanel::Gzip;

# cpanel - Cpanel/Gzip.pm                          Copyright 2022 cPanel, L.L.C.
#                                                           All rights reserved.
# copyright@cpanel.net                                         http://cpanel.net
# This code is subject to the cPanel license. Unauthorized copying is prohibited

use strict;
use warnings;
use Cpanel::Gzip::gzip   ();
use Cpanel::Gzip::ungzip ();

use vars qw(@ISA @EXPORT $VERSION);
require Exporter;
@ISA    = qw( Exporter );
@EXPORT = qw( gzipmem );

$VERSION = '1.0';

sub gzipmem   { goto &Cpanel::Gzip::gzip::gzipmem; }
sub gunzipmem { goto &Cpanel::Gzip::ungzip::gunzipmem; }

1;
