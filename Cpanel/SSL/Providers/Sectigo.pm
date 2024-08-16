package Cpanel::SSL::Providers::Sectigo;

# cpanel - Cpanel/SSL/Providers/Sectigo.pm         Copyright 2022 cPanel, L.L.C.
#                                                           All rights reserved.
# copyright@cpanel.net                                         http://cpanel.net
# This code is subject to the cPanel license. Unauthorized copying is prohibited

use strict;
use warnings;

=encoding utf-8

=head1 NAME

Cpanel::SSL::Providers::Sectigo - Sectigo-specific SSL logic

=head1 SYNOPSIS

    my $str = Cpanel::SSL::Providers::Sectigo::get_dcv_string_for_request(
        [ 'example.com', 'www.example.com' ],
        {
            'example.com' => 'http',
            'www.example.com' => 'http',
        },
    );

    my $strings_hr = Cpanel::SSL::Providers::Sectigo::get_dcv_strings_for_csr( $csr_pem );

=cut

use strict;
use warnings;

use constant DCV_METHOD_TO_SECTIGO => {
    http => 'HTTPCSRHASH',
    dns  => 'CNAMECSRHASH',
};

use constant {

    URI_DCV_RELATIVE_PATH => '.well-known/pki-validation',

    # The last bit here doesn’t actually happen; we just want to
    # tag the regexp so that it’s very clear where it came from since
    # otherwise this pattern is somewhat generic.
    REQUEST_URI_DCV_PATH => '^/\\.well-known/pki-validation/[A-F0-9]{32}\\.txt(?: Sectigo DCV)?$',

    URI_DCV_ALLOWED_CHARACTERS     => [ 0 .. 9, 'A' .. 'F' ],
    URI_DCV_RANDOM_CHARACTER_COUNT => 32,
    HTTP_DCV_PATH_EXTENSION        => 'txt',
    HTTP_DCV_USER_AGENT            => 'COMODO DCV',

    #Comodo doesn’t do HTTP redirects.
    HTTP_DCV_MAX_REDIRECTS => 0,
};

# https://support.sectigo.com/Com_KnowledgeDetailPage?Id=kA01N000000zFMO
use constant CAA_STRINGS => (
    'comodoca.com',
    'sectigo.com',
    'usertrust.com',
    'trust-provider.com',
);

=head1 FUNCTIONS

=head2 $string = get_dcv_string_for_request( \@DOMAINS, \%DOMAIN_DCV_METHOD )

Returns the DCV methods string to send to Sectigo for the given (ordered)
@DOMAINS.

%DOMAIN_DCV_METHOD is keyed on the domain name (each key must equal
a @DOMAINS value); the values are either C<http> or C<dns>.

=cut

sub get_dcv_string_for_request {
    my ( $domains_ar, $domain_dcv_method_hr ) = @_;

    die "Empty domains list!" if !@$domains_ar;

    return join( ',', map { DCV_METHOD_TO_SECTIGO()->{ $domain_dcv_method_hr->{$_} || die "No known DCV method for “$_”!" } || die "Invalid DCV method ($domain_dcv_method_hr->{$_}) for “$_”!" } @$domains_ar );
}

=head2 $STRINGS_HR = get_dcv_strings_for_csr( CSR_PEM )

Returns a hash reference that gives the various strings needed for
Sectigo’s DCV:

=over

=item * C<http_filename> (just the filename, exclusive of the directory)

=item * C<http_contents>

=item * C<dns_name> - i.e., the name of the CNAME record that Sectigo looks for.

=item * C<dns_value>

=back

See L<http://secure.comodo.net/api/pdf/latest/Domain%20Control%20Validation.pdf>
for documentation and L<https://secure.comodo.net/utilities/decodeCSR.html>
for an example.

=cut

sub get_dcv_strings_for_csr {
    my ($csr) = @_;

    require Crypt::Format;
    require Digest::MD5;
    require Digest::SHA;

    chomp $csr;

    $csr = Crypt::Format::pem2der($csr);

    my $md5    = Digest::MD5::md5_hex($csr);
    my $sha256 = Digest::SHA::sha256_hex($csr);

    $md5    =~ tr<a-f><A-F>;
    $sha256 =~ tr<A-F><a-f>;

    my $http_filename = "$md5.txt";

    # NB: This used to be SHA-1, but then Sectigo (called “Comodo”
    # at the time) updated it to SHA-256.
    my $http_contents = join( "\n", $sha256, 'comodoca.com' );

    $md5 =~ tr<A-F><a-f>;

    substr( $sha256, length($sha256) / 2, 0, '.' );

    return {
        http_filename => $http_filename,
        http_contents => $http_contents,
        dns_name      => "_$md5",
        dns_value     => "$sha256.comodoca.com",
    };
}

1;
