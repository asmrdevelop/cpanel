package Cpanel::ASCII;

# cpanel - Cpanel/ASCII.pm                         Copyright 2022 cPanel, L.L.C.
#                                                           All rights reserved.
# copyright@cpanel.net                                         http://cpanel.net
# This code is subject to the cPanel license. Unauthorized copying is prohibited

#TODO: This might be useful to upload to CPAN.

use strict;
use warnings;

use Cpanel::Context ();

my @CODES = qw(
  NULL    SOH STX ETX EOT ENQ ACK BEL BS  HT
  LF      VT  FF  CR  SO  SI  DLE DC1 DC2 DC3
  DC4     NAK SYN ETB CAN EM  SUB ESC FS  GS
  RS      US
);
$CODES[127] = 'DEL';

sub get_control_numbers {
    Cpanel::Context::must_be_list();

    return grep { $CODES[$_] } 0 .. $#CODES;
}

sub get_symbol_for_control_number {
    return $CODES[ $_[0] ] || die "Unrecognized ASCII control number: “$_[0]”";
}

1;
