package Cpanel::StringFunc::Group;

# cpanel - Cpanel/StringFunc/Group.pm              Copyright 2022 cPanel, L.L.C.
#                                                           All rights reserved.
# copyright@cpanel.net                                         http://cpanel.net
# This code is subject to the cPanel license. Unauthorized copying is prohibited

use strict;

# @method: group_words
# This method is used to group words in a given
# string by joining them with '_'. It removes
# all other special characters that exist in between.
sub group_words {
    my ($input) = @_;
    $input =~ tr{A-Z}{a-z};         #lower-case ASCII
    $input =~ s/[^a-z0-9_\s]//g;    #get rid of anything else
    $input =~ s/^\s+|\s+$//g;       # Trim whitespace from both ends
    $input =~ s/[-\s]+/_/g;         # Replace all occurrences of spaces and hyphens with a single hyphen
    return $input;
}

1;
