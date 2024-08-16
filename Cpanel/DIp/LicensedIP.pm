package Cpanel::DIp::LicensedIP;

# cpanel - Cpanel/DIp/LicensedIP.pm                Copyright 2022 cPanel, L.L.C.
#                                                           All rights reserved.
# copyright@cpanel.net                                         http://cpanel.net
# This code is subject to the cPanel license. Unauthorized copying is prohibited

use strict;
use warnings;

use Cpanel::Config::Sources           ();
use Cpanel::HTTP::Tiny::FastSSLVerify ();

=encoding utf-8

=head1 NAME

Cpanel::DIp::LicensedIP - Tools for looking up the ip external license servers
would detect the server as being addressed to.

=head1 SYNOPSIS

    use Cpanel::DIp::LicensedIP;

    my license_ip = Cpanel::DIp::LicensedIP::get_license_ip();

Be aware that the returns for both subroutines in this module cache the result,
so if you want to force refetch these, make sure to undef the package vars
that we cache the values in ( $url & $myip ).

=head2 myip_url

Returns the URL for getting the license IP from.
Defaults to https://myip.cpanel.net/v1.0/ when MYIP is not set in
/etc/cpsources.conf

=over 2

=item Output

=over 3

=item C<SCALAR>

A C<SCALAR> of the URL

=back

=back

=cut

our $url;

sub myip_url {
    return $url if $url;
    return $url = Cpanel::Config::Sources::loadcpsources()->{'MYIP'} || 'https://myip.cpanel.net/v1.0/';
}

=head2 get_license_ip

Returns the IP address that this server appears to be bound to to the "outside
world". As such, this can be normally considered the "licensed" IP, as that's
most certainly what our licensing system will recognize as the machine's IP.

=over 2

=item Input

=over 3

=item C<SCALAR>

A C<SCALAR> of the URL used to get this. Useful if (for some reason) you don't
want to use the default this function uses (see myip_url above).

=back

=back

=over 2

=item Output

=over 3

=item C<SCALAR>

A C<SCALAR> of the IP address

=back

=back

=cut

# Used to be scripts/mainip's 'get_ip_from_remote'
our $myip;

sub get_license_ip {
    my ($myip_url) = @_;

    return $myip if $myip;
    $myip_url ||= myip_url();
    my $ua = Cpanel::HTTP::Tiny::FastSSLVerify->new( 'timeout' => 10 );

    my $tries = 0;
    my $response;
    while ( $tries++ < 3 && ( !defined $response || !$response->{success} ) ) {
        $response = $ua->get($myip_url);
    }
    if ( !$response->{success} ) {

        # Content may often be undefined here, so let's use the status and
        # reason instead (as is the example in HTTP::Tiny's POD).
        die( "Encountered an error while determining the main IP from the myip server ($myip_url):" . ( defined $response ? "\n$response->{status} $response->{reason}\n" : '' ) );
    }
    $myip = $response->{content};
    chomp $myip;
    return $myip;
}

1;
