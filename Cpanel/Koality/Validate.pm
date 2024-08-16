package Cpanel::Koality::Validate;

# cpanel - Cpanel/Koality/Validate.pm              Copyright 2023 cPanel, L.L.C.
#                                                           All rights reserved.
# copyright@cpanel.net                                         http://cpanel.net
# This code is subject to the cPanel license. Unauthorized copying is prohibited

use cPstrict;
use Cpanel::Imports;

use constant SUPPORTED_GEO_LOCATION_REGIONS => [
    'us_east',
    'de',
    'asia_jp'
];

=head1 MODULE

C<Cpanel::Koality::Validate>

=head1 DESCRIPTION

C<Cpanel::Koality::Validate> provides validation methods for Koality API related inputs.
This module is primarily geared for use in type checking the C<Cpanel::Koality::Base> class' attributes as well as those of related subclasses.

=head1 FUNCTIONS

=head2 valid_api_url( url )

Validate an API URL.

=head3 ARGUMENTS

=over

=item url - string - Required

The API url to validate.

=back

=head3 RETURNS

Returns 1 if the URL is valid and dies if the URL is invalid.

=head3 EXAMPLES

has 'auth_url' => (

...

    isa     => \&Cpanel::Koality::Validate::valid_api_url,

...

);

=cut

sub valid_api_url ($url) {

    # It's ok if url is undefined we may not have one yet.
    return 1 if !defined $url || $url eq '';

    require Cpanel::Validate::URL;
    die locale()->maketext("Invalid URL.")                if !Cpanel::Validate::URL::is_valid_url($url);
    die locale()->maketext("Must start with “https://”.") if $url !~ /^https:\/\//m;
    die locale()->maketext("Must end with a “/”.")        if $url !~ /\/$/m;

    return 1;
}

=head2 valid_api_object( object )

Validate that the input is a C<Cpanel::Plugins::RestApiClient> object.

=head3 ARGUMENTS

=over

=item object - blessed reference - Required

The API object to validate.

=back

=head3 RETURNS

Returns 1 if the object is valid and dies if the object is invalid.

=head3 EXAMPLES

has 'api' => (

...

    isa     => \&Cpanel::Koality::Validate::valid_api_object,

...

);

=cut

sub valid_api_object ($obj) {
    require Scalar::Util;
    die 'Not a blessed perl object.'                       if !Scalar::Util::blessed($obj);
    die 'Must be a Cpanel::Plugins::RestApiClient object.' if !$obj->isa('Cpanel::Plugins::RestApiClient');

    return 1;
}

=head2 valid_token( token )

Validate that the input is a valid token that doesn't include any illegal characters.

=head3 ARGUMENTS

=over

=item token - string - Required

The token to validate.

=back

=head3 RETURNS

Returns 1 if the token is valid and dies if the token is invalid.

=head3 EXAMPLES

has 'app_token' => (

...

    isa     => \&Cpanel::Koality::Validate::valid_token,

...

);

=cut

sub valid_token ($token) {

    # It's ok if token is undefined we may not have one yet.
    return 1 if !defined $token || $token eq '';

    die locale()->maketext('Invalid token.') if $token !~ /^[a-zA-Z0-9-_.]+$/m;
    return 1;
}

=head2 valid_activation_email_locale( locale )

Validate that the input is a valid locale that is supported by Koality.

=head3 ARGUMENTS

=over

=item locale - string - Required

The locale string to validate.

=back

=head3 RETURNS

Dies if the locale is not a two language character code.

=head3 EXAMPLES

    isa => \&Cpanel::Koality::Validate::valid_activation_email_locale,

=cut

sub valid_activation_email_locale ($locale) {

    if ( !$locale || $locale !~ m/^[a-zA-Z]{2}$/ ) {
        die locale()->maketext("The activation email locale must be an ISO 639-1 two character language code.");
    }

    return 1;
}

=head2 valid_geo_location( location )

Validate the koality datacenter location.

The only possible locations are:
us_east
de
asia_jp

=head3 ARGUMENTS

=over

=item location - string - Required

The location to validate.

=back

=head3 RETURNS

Dies if the location is invalid, returns 1 otherwise.

=head3 EXAMPLES

    isa => \&Cpanel::Koality::Validate::valid_geo_location,

=cut

sub valid_geo_location ($location) {

    my @locations = ( 'us_east', 'de', 'asia_jp' );
    if ( !grep { $_ eq $location } SUPPORTED_GEO_LOCATION_REGIONS()->@* ) {
        die locale()->maketext( "Must be one of the following locations: [list_and_quoted,_1].", \@locations );
    }

    return 1;
}

1;
