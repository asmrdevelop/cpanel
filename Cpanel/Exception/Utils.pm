package Cpanel::Exception::Utils;

# cpanel - Cpanel/Exception/Utils.pm               Copyright 2022 cPanel, L.L.C.
#                                                           All rights reserved.
# copyright@cpanel.net                                         http://cpanel.net
# This code is subject to the cPanel license. Unauthorized copying is prohibited

use strict;
use warnings;

# This method is used to get the error message from the first line of a stacktrace provided by some
# CPAN modules we use or die statements.
# It will end the error message before the first sign of 'at /', which isn't technically correct
sub traceback_to_error {
    my ($traceback) = @_;

    $traceback =~ s{ at /.*}{}s;

    return $traceback;
}

1;
