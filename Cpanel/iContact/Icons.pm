package Cpanel::iContact::Icons;

# cpanel - Cpanel/iContact/Icons.pm                Copyright 2022 cPanel, L.L.C.
#                                                           All rights reserved.
# copyright@cpanel.net                                         http://cpanel.net
# This code is subject to the cPanel license. Unauthorized copying is prohibited

use strict;
use warnings;

#TODO: Make these \x{NNNN} sequences instead,
#and put the literal character in a comment.
my %_ICONS = (
    error           => '⛔',
    critical        => '⛔',
    fatal           => '⛔',
    failed          => '⛔',
    blacklist       => '📙',
    warning         => '⚠',
    warn            => '⚠',
    hang            => '⚠',
    unknown         => '❓',
    info            => '❕',
    stall           => '🚦',
    success         => '✅',
    recovered       => '❇',
    local_network   => '✅',
    whitelist       => '📗',
    known_network   => '✔',
    unknown_network => '⚠',
    test            => '🎰',
);

sub get_icon {
    my $name = shift;
    return $_ICONS{$name};
}

1;
