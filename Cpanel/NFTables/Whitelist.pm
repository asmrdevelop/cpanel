package Cpanel::NFTables::Whitelist;

# cpanel - Cpanel/NFTables/Whitelist.pm            Copyright 2022 cPanel, L.L.C.
#                                                           All rights reserved.
# copyright@cpanel.net                                         http://cpanel.net
# This code is subject to the cPanel license. Unauthorized copying is prohibited

use cPstrict;

use parent 'Cpanel::NFTables';

=head1 NAME

Cpanel::NFTables::Whitelist

=head1 SYNOPSIS

    use Cpanel::XTables::Whitelist();

    my $obj = Cpanel::XTables::Whitelist->new( 'chain' => 'someChain' );
    my $rules = $obj->accept_in_both_directions('1.2.3.4');

=head1 DESCRIPTION

This module is meant to be the NFTables side of the Cpanel::XTables logic
for whitelisting hosts.

CentOS 7 or below: Cpanel::IPTables object
CentOS 8: Cpanel::NFTables object

=head1 METHODS

=head2 accept_in_both_directions

Whitelists the given IP.

=cut

sub accept_in_both_directions ( $self, $ip = undef ) {
    my $ipdata = $self->validate_ip_is_correct_version_or_die($ip);

    return $self->exec_checked_calls( [ map { [ qw{add rule}, $self->IP_FAMILY, $self->TABLE, $self->{'chain'}, 'ip', $_, $ip, qw(counter accept) ]; } (qw(saddr daddr)) ] );
}

1;
