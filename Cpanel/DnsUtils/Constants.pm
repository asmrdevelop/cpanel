package Cpanel::DnsUtils::Constants;

# cpanel - Cpanel/DnsUtils/Constants.pm            Copyright 2022 cPanel, L.L.C.
#                                                           All rights reserved.
# copyright@cpanel.net                                         http://cpanel.net
# This code is subject to the cPanel license. Unauthorized copying is prohibited

use strict;
use warnings;

=encoding utf-8

=head1 NAME

Cpanel::DnsUtils::Constants

=head1 SYNOPSIS

    my $size = Cpanel::DnsUtils::Constants::SYNCZONES_BATCH_SIZE();

=head1 CONSTANTS

=head2 SYNCZONES_BATCH_SIZE

The number of domains to sync at a time during a SYNCZONES.

=cut

use constant SYNCZONES_BATCH_SIZE => 512;

1;
