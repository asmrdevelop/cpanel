package Whostmgr::API::1::CountryCodes;

# cpanel - Whostmgr/API/1/CountryCodes.pm          Copyright 2022 cPanel, L.L.C.
#                                                           All rights reserved.
# copyright@cpanel.net                                         http://cpanel.net
# This code is subject to the cPanel license. Unauthorized copying is prohibited

use strict;
use warnings;

use Cpanel::CountryCodes::IPS ();
use Whostmgr::API::1::Utils   ();

use constant NEEDS_ROLE => {
    get_countries_with_known_ip_ranges => undef,
};

=encoding utf-8

=head1 NAME

Whostmgr::API::1::CountryCodes - CountryCodes related API functions

=head1 SYNOPSIS

    use Whostmgr::API::1::CountryCodes;

    # synopsis...

=head1 DESCRIPTION

WHM APIs for CountryCodes

=cut

=head1 functions

=head2 get_countries_with_known_ip_ranges

Returns list of countries with known ipbin16 ranges

=over 2

=item Output

=over 3

=item C<ARRAYREF>

    returns a list of countries with known ip ranges

=back

=back

=cut

sub get_countries_with_known_ip_ranges {
    my ( $args, $metadata ) = @_;
    Whostmgr::API::1::Utils::set_metadata_ok($metadata);

    my $countries = Cpanel::CountryCodes::IPS::get_countries_with_known_ip_ranges();

    return { 'countries' => $countries };
}

1;
