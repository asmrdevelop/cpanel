package Cpanel::DNS::Unbound::Workarounds::Config;

# cpanel - Cpanel/DNS/Unbound/Workarounds/Config.pm
#                                                  Copyright 2022 cPanel, L.L.C.
#                                                           All rights reserved.
# copyright@cpanel.net                                         http://cpanel.net
# This code is subject to the cPanel license. Unauthorized copying is prohibited

use strict;
use warnings;

=encoding utf-8

=head1 NAME

Cpanel::DNS::Unbound::Workarounds::Config - Configuration data for
L<Cpanel::DNS::Unbound::Workarounds>

=head1 DESCRIPTION

This module provides configuration data for the
Cpanel::DNS::Unbound::Workarounds modules.

=head1 CONSTANTS

=head2 @key_value_pairs = ORDERED_WORKAROUNDS()

Returns a list of key/value pairs that encompass different configuration
options to try with libunbound to achieve successful operation.

Those options are described in the code.

=cut

use constant ORDERED_WORKAROUNDS => (

    # Some servers cannot receive UDP DNS responses whose size
    # exceeds 512 bytes. So the first thing we try is making libunbound
    # forgo EDNS. This will increase the number of DNS queries that require
    # TCP, which slows things down.
    'edns-buffer-size' => '512',

    # Some servers cannot receive UDP DNS responses except from particular
    # nameservers. The only workaround here is to forgo UDP DNS entirely,
    # which is even slower than limiting buffer size to 512 bytes.
    'do-udp' => 'no',
);

our %UNBOUND_CONFIG_VALUES = (
    ORDERED_WORKAROUNDS(),

    'do-ip6' => 'no',
);

our %UNBOUND_KEYS_TO_FLAG_FILE_NAMES = (

    # do-ip6 is tested via hard-coded logic in Workarounds.pm.
    'do-ip6' => 'has_broken_ipv6',

    'edns-buffer-size' => 'has_udp_mtu_reassembly_problem',
    'do-udp'           => 'has_udp_dns_blocked',
);

our $DNS_FLAGS_DIR       = '/var/cpanel/dns_flags';
our $DNS_FLAGS_DIR_PERMS = 0755;
1;
