package Cpanel::CORE::Dependencies;

# cpanel - Dependencies.pm                           Copyright 2021 cPanel L.L.C.
#                                                            All rights Reserved.
# copyright@cpanel.net                                          http://cpanel.net
# This code is subject to the cPanel license.  Unauthorized copying is prohibited

=pod

List of module required by RPMs to run cpanel scripts

=cut

use strict;
use warnings;

our $VERSION = '3.098007';

sub version {
    return $VERSION;
}

1;

__END__
