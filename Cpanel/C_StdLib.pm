package Cpanel::C_StdLib;

# cpanel - Cpanel/C_StdLib.pm                      Copyright 2022 cPanel, L.L.C.
#                                                           All rights reserved.
# copyright@cpanel.net                                         http://cpanel.net
# This code is subject to the cPanel license. Unauthorized copying is prohibited

use strict;
use warnings;

=encoding utf-8

=head1 NAME

Cpanel::C_StdLib - Ports of C standard library functions

=head1 DISCUSSION

It is conceived that functions in this module emulate their C standard
library counterparts closely enough as to need minimal documentation.

For example, if you type:

    man 3 isspace

… you’ll get documentation that will describe the behavior of this
module’s equivalently named function. (NB: “man 3 isspace” isn’t in
some Linux default installs)

=head1 FUNCTIONS

=head2 isspace(CHR)

Equivalent function is in C’s C<ctype.h>.

=cut

sub isspace {    ##no critic qw(RequireArgUnpacking)
    die "single char only, not “$_[0]”!" if 1 < length $_[0];
    return $_[0] =~ tr< \t\x0a-\x0d><>;
}

1;
