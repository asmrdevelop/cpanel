package Whostmgr::API::1::License;

# cpanel - Whostmgr/API/1/License.pm               Copyright 2022 cPanel, L.L.C.
#                                                           All rights reserved.
# copyright@cpanel.net                                         http://cpanel.net
# This code is subject to the cPanel license. Unauthorized copying is prohibited

use strict;
use warnings;
use Try::Tiny;

use Cpanel::Imports;
use Cpanel::Verify          ();
use Cpanel::Server::Type    ();
use Cpanel::DIp::LicensedIP ();
use Whostmgr::API::1::Utils ();

use constant NEEDS_ROLE => {
    is_eligible_for_trial => undef,
    get_licenses          => undef,
};

=head1 NAME

whostmgr::API::1::License - API calls to verify server licensing.

=head1 SYNOPSIS

    use whostmgr::API::1::License ();
    whostmgr::API::1::get_licenses (
        {
            'ip' => '1.1.1.1',
        },
    );

=cut

=head1 METHODS

=over 8

=item B<get_licenses>

Calls the Verify service to list all current licenses for an ip.

B<Input>: ip (optional)
    If an ip address is provided, the function will check the license of that
    server.  If no ip is provided it will use the server's own ip.

B<Output>:
    Returns an array of hashes representing entries in the results
    from Verify.  The values for "current" and "history" are
    guaranteed to be defined arrays, even if empty.

=cut

sub get_licenses {
    my ( $args, $metadata ) = @_;
    my $ip = $args->{'ip'};

    local $@;
    my $data = eval { Cpanel::Verify::get_licenses($ip); };
    if ( !defined $data ) {
        Whostmgr::API::1::Utils::set_metadata_not_ok( $metadata, $@ );
        return {};
    }

    Whostmgr::API::1::Utils::set_metadata_ok($metadata);
    return { 'data' => $data };
}

=item B<is_eligible_for_trial>

Parses information from the Verify service to decide if a server is eligible for a trial license.

B<Input>: ip (optional)
    If an ip address is provided, the function will check the license of that
    server.  If no ip is provided it will use the server's own ip.

B<Output>:
    Returns a hash containing the element "is_eligible", which provides a boolean answer.
        is_eligible = B<1> - The server is eligible for a trial license.
        is_eligible = B<0> - The server is not eligible for a trial license.

=cut

sub is_eligible_for_trial {
    my ( $args, $metadata ) = @_;
    my $ip = $args->{'ip'};    #IP address is optional

    # Bypass verify.cpanel.net if no IP is provided (which intends to check the local license)
    # and if a valid license is indicated in cpanel.lisc. Under such a circumstance, the local system
    # should not be eligible for a trial. Lack of presence of a valid license is considered inconclusive.
    if ( !$ip && grep { Cpanel::Server::Type::is_licensed_for_product($_) } qw(cpanel dnsonly dnsnode mailnode databasenode webnode) ) {
        $ip = try { Cpanel::DIp::LicensedIP::get_license_ip() };    # This is really just for cosmetic purposes, so it's OK if it fails.
        Whostmgr::API::1::Utils::set_metadata_ok($metadata);
        return { 'is_eligible' => 0, 'ip' => $ip // '' };
    }

    my $data = Cpanel::Verify::get_licenses($ip);

    my $is_eligible = try {
        Cpanel::Verify::is_eligible_for_trial($data);
    };

    if ( !defined $is_eligible ) {
        Whostmgr::API::1::Utils::set_metadata_not_ok( $metadata, locale()->maketext('Invalid response from [asis,Verify] service.') );
        return {};
    }

    Whostmgr::API::1::Utils::set_metadata_ok($metadata);
    return { 'is_eligible' => $is_eligible, 'ip' => $data->{ip} };
}

=back

=cut

1;
