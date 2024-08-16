#!/usr/local/cpanel/3rdparty/bin/perl

use strict;
use warnings;

use Cpanel::Version ();

my $short_version = Cpanel::Version::get_short_release_number() . "\n";
my $long_version  = Cpanel::Version::get_version_display();
$long_version =~ tr{.}{-};

my $headers = 'Status: 301' . "\r\n";
$headers .= 'Location: ' . sprintf( 'https://docs.cpanel.net/changelogs/%d-change-log/#%s', $short_version, $long_version ) . "\r\n";
$headers .= "\r\n";
print $headers;    # minimize the number of packets sent
