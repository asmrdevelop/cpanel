package Cpanel::WebCalls::Constants;

# cpanel - Cpanel/WebCalls/Constants.pm            Copyright 2022 cPanel, L.L.C.
#                                                           All rights reserved.
# copyright@cpanel.net                                         http://cpanel.net
# This code is subject to the cPanel license. Unauthorized copying is prohibited

use cPstrict;

=encoding utf-8

=head1 NAME

Cpanel::WebCalls::Constants

=head1 SYNOPSIS

    my $allowance = Cpanel::WebCalls::Constants::RATE_LIMIT_ALLOWANCE;
    my $period    = Cpanel::WebCalls::Constants::RATE_LIMIT_PERIOD;

=head1 DESCRIPTION

This module stores constants for use in dynamic DNS modules.

=cut

#----------------------------------------------------------------------

use constant {
    RATE_LIMIT_ALLOWANCE => 5,
    RATE_LIMIT_PERIOD    => 300,    # 5 minutes
};

#----------------------------------------------------------------------

=head1 CONSTANTS

=head2 C<RATE_LIMIT_PERIOD>

The period after which rate limit counts reset.

=head2 C<RATE_LIMIT_ALLOWANCE>

The number of hits allowed per C<RATE_LIMIT_PERIOD> seconds.

i.e., a user can hit the webcall C<RATE_LIMIT_ALLOWANCE> times within
C<RATE_LIMIT_PERIOD> seconds before the rate limiting kicks in.

=cut

1;
