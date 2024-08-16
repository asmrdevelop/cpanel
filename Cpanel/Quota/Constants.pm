package Cpanel::Quota::Constants;

# cpanel - Cpanel/Quota/Constants.pm               Copyright 2022 cPanel, L.L.C.
#                                                           All rights reserved.
# copyright@cpanel.net                                         http://cpanel.net
# This code is subject to the cPanel license. Unauthorized copying is prohibited

=head1 NAME

Cpanel::Quota::Constants

=head1 SYNOPSIS

    my $max = Cpanel::Quota::Constants::MAXIMUM_BLOCKS();

=cut

use strict;
use warnings;

use Cpanel::OSSys::Bits ();

=head1 FUNCTIONS

=head2 MAXIMUM_BLOCKS()

Returns the maximum number of blocks that a quota may set on this
system.

=cut

use constant MAXIMUM_BLOCKS => $Cpanel::OSSys::Bits::MAX_64_BIT_UNSIGNED;

#----------------------------------------------------------------------

=head2 BYTES_PER_BLOCK()

Returns the number of bytes per block.

=cut

use constant BYTES_PER_BLOCK => 1024;

1;
