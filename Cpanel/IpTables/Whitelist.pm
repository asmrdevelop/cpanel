package Cpanel::IpTables::Whitelist;

# cpanel - Cpanel/IpTables/Whitelist.pm            Copyright 2022 cPanel, L.L.C.
#                                                           All rights reserved.
# copyright@cpanel.net                                         http://cpanel.net
# This code is subject to the cPanel license. Unauthorized copying is prohibited

use strict;

use base 'Cpanel::IpTables';

sub accept_in_both_directions {
    my ( $self, $ip ) = @_;

    my $ipdata = $self->validate_ip_is_correct_version_or_die($ip);

    return $self->exec_checked_calls( [ map { [ qw(-A), $self->{'chain'}, $_, $ip, qw(-j ACCEPT) ]; } (qw(-s -d)) ] );

}

1;
