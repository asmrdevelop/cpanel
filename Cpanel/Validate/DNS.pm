package Cpanel::Validate::DNS;

# cpanel - Cpanel/Validate/DNS.pm                  Copyright 2022 cPanel, L.L.C.
#                                                           All rights reserved.
# copyright@cpanel.net                                         http://cpanel.net
# This code is subject to the cPanel license. Unauthorized copying is prohibited

use strict;
use warnings;

#IMPORTANT: This module's regular expressions must be valid both in Perl and in JavaScript.

#Per RFC 4034:
#key tag, algorithm, digest type, digest

# This code had to be commented below to prevent perltidy from making the code all 1 line.
# The fact this had to be done suggests it might be written differently.
# Maybe even with comments explaining what each one is?
# TODO: This should be considered if this code is ever re-factored.

my $octet      = '0*(?:(?:25[0-5]|2[0-4]\d?|1?\d{0,2}))';
my $two_octets = '0*(?:'                                    #
  . '6553[0-5]' . '|'                                       #
  . '655[0-2]\d?' . '|'                                     #
  . '65[0-4]\d{0,2}' . '|'                                  #
  . '6[0-4]\d{0,3}' . '|'                                   #
  . '[0-5]?\d{0,4}'                                         #
  . ')';

my $hex   = '[\da-fA-F]';
my $hex_s = '[\d\sa-fA-F]';
my $b64   = '[\da-zA-Z=/+]';
my $b64_s = '[\s\da-zA-Z=/+]';

our $dnskey_regex = "^($two_octets)\\s+($octet)\\s+($octet)\\s+\\(\\s*($b64(?:$b64_s*$b64+)?)\\s*\\)\$";

our $ds_regex = $dnskey_regex;
$ds_regex =~ s{\Q$b64\E}{$hex}g;
$ds_regex =~ s{\Q$b64_s\E}{$hex_s};

#RFC 1876

my $deg_lat  = '0*(?:(?:90(?:\.0+)?|[1-8]?\d(?:\.\d+)?|\.\d+))';
my $deg_long = '0*(?:(?:180(?:\.0+)?|(?:1[0-7]\d|\d\d?)(?:\.\d+)?)|\.\d+)';
my $minutes  = '0*(?:(?:59(?:\.0+)?|(?:5[1-8]|[1-4]?\d)(?:\.\d+)?)|\.\d+)';
my $seconds  = '0*(?:|59(|\.9990*|\.99(?:0*|[0-8]\d*)|\.9[0-8]\d*|\.[0-8]\d*)|[0-5]?\d(?:\.\d+)?|\.\d+)';
my $altitude = '(?:-0*(?:100000(?:\.0+)?|\d{1,5}(\.\d\d?0*)?)|0*'                                           #
  . '42849672\.9[0-5?]0*|'                                                                                  #
  . '42849672(?:\.[1-8]\d0*)?|'                                                                             #
  . '(?:'                                                                                                   #
  . '4284967[01]|'                                                                                          #
  . '428496[0-6]\d|'                                                                                        #
  . '42849[0-5]\d\d?|'                                                                                      #
  . '4284[0-8]\d{1,3}|'                                                                                     #
  . '428[0-3]\d{1,4}|'                                                                                      #
  . '42[0-7]\d{1,5}|'                                                                                       #
  . '4[01]\d{1,6}|'                                                                                         #
  . '[1-3]?\d{1,7}|'                                                                                        #
  . ')'                                                                                                     #
  . '(?:\.\d{1,2}0*)?'                                                                                      #
  . ')';
my $size_prc = '0*(?:90000000(?:\.0+)?|[1-8]?\d{1,7}(?:\.\d+)?|\.\d+)';

our $loc_regex = "^($deg_lat)(?:\\s+($minutes)(?:\\s+($seconds))?)?\\s+[NS]"                                #
  . "\\s+($deg_long)(?:\\s+($minutes)(?:\\s+($seconds))?)?\\s+[EW]"                                         #
  . "\\s+(${altitude})m?(?:\\s+(${size_prc})m?(?:\\s+(${size_prc})m?(?:\\s+(${size_prc})m?)?)?)?\$";

sub is_valid_dnskey {
    my $dnskey = shift || return;
    return $dnskey =~ m{$dnskey_regex};
}

sub is_valid_ds {
    my $ds = shift || return;
    return $ds =~ m{$ds_regex};
}

sub is_valid_loc {
    my $loc = shift || return;
    return $loc =~ m{$loc_regex};
}

1;
