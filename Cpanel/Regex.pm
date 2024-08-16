package Cpanel::Regex;

# cpanel - Cpanel/Regex.pm                         Copyright 2022 cPanel, L.L.C.
#                                                           All rights reserved.
# copyright@cpanel.net                                         http://cpanel.net
# This code is subject to the cPanel license. Unauthorized copying is prohibited

use strict;

our $VERSION = '0.2.5';

#cf. "Mastering Regular Expressions", 3rd ed., p264
my $dblquotedstr = q{"([^\\\\"]*(?:\\\\.[^\\\\"]*)*)"};
my $sglquotedstr = $dblquotedstr;
$sglquotedstr =~ tr{"}{'};

#This rejects extra leading “0”.
my $zero_through_255 = '(?:25[0-5]|2[0-4][0-9]|1[0-9]{2}|[1-9][0-9]?|0)';

our %regex = (
    'emailaddr'              => '[a-zA-Z0-9!#\$\-=?^_{}~]+(?:\.[a-zA-Z0-9!#\$\-=?^_{}~]+)*(?:\+[a-zA-Z0-9 \.=\-\_]+)*\@[\da-zA-Z](?:[-\da-zA-Z]*[\da-zA-Z])?(?:\.[\da-zA-Z](?:[-\da-zA-Z]*[\da-zA-Z])?)*',
    'oneplusdot'             => '\.+',
    'oneplusspacetab'        => '[\s\t]+',
    'multipledot'            => '\.{2,}',
    'commercialat'           => '\@',
    'plussign'               => '\+',
    'singledot'              => '\.',
    'newline'                => '\n',
    'doubledot'              => '\.\.',
    'lineofdigits'           => '^\d+$',
    'lineofnonprintingchars' => '^[\s\t]*$',
    'getemailtransport'      => '^from\s+.*\s+by\s+\S+\s+with\s+(\S+)',
    'getreceivedfrom'        => '^from\s+(.*)\s+by\s+',
    'emailheaderterminator'  => '^[\r\n]*$',
    'forwardslash'           => '\/',

    # backslashes are goofy, this results in \\ when qr()'ed in settie()
    'backslash'             => chr(92) x 4,
    'singlequote'           => q('),
    'doublequote'           => '"',
    'allspacetabchars'      => '[\s\t]*',
    'beginswithspaceortabs' => '^[\s\t]',

    #NOTE: These regexps do NOT decode; they only capture between the quotes.
    doublequotedstring => $dblquotedstr,
    singlequotedstring => $sglquotedstr,

    #Dun & Bradstreet
    DUNS => '[0-9]{2}(?:-[0-9]{3}-[0-9]{4}|[0-9]{7})',

    YYYY_MM_DD => '[0-9]{4}-(?:1[012]|0[1-9])-(?:3[01]|[12][0-9]|0[1-9])',

    ipv4 => "(?:$zero_through_255\.){3}$zero_through_255",

    iso_z_time => '[0-9]{4}-[0-9]{2}-[0-9]{2}T[0-9]{2}:[0-9]{2}:[0-9]{2}Z',
);

1;
