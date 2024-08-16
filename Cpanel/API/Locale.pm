package Cpanel::API::Locale;

# cpanel - Cpanel/API/Locale.pm                    Copyright 2022 cPanel, L.L.C.
#                                                           All rights reserved.
# copyright@cpanel.net                                         http://cpanel.net
# This code is subject to the cPanel license. Unauthorized copying is prohibited

use strict;
use warnings;

use Cpanel::Locale ();

my $lh;

=encoding utf8

=head1 NAME

Cpanel::API::Locale

=head1 DESCRIPTION

This module contains UAPI methods related to Locales. Some methods
are specific to the current user and some provide access to all the
available locales on the system.

=head1 FUNCTIONS

=head2 get_attributes

Retrieve the various attributes associated with the users current
Cpanel::Locale. This method will return the most commonly used
attributes if no specific attributes are requested.

=head3 ARGUMENTS

If you do not request any specific attributes, the most commonly used attributes are returned:
locale, encoding, and direction.

An optional CSV string "attributes" may be used to request specific attributes.

=over

=item attributes - string

A string of CSV attributes to return.
Valid values are name, locale, encoding, and direction

=back

=head3 RETURNS

Depending on what properties are requested the returned data is a HashRef with
one or more of the the following properties.

=over

=item locale - String

The ISO 3166 locale code for the users current locale. May also include the region code.

    Example    | Description
    -------------------------------------------
    en         | English
    nb         | Norwegian Bokmål
    es         | Spanish
    es_es      | Spanish as spoken in Spain.
    vi         | Vietnamese

=item name - String

The name of the locale in the users current locale. So if the locale is 'en', then this field will be 'English'.

=item encoding - String

The encoding used with the locale. For the 'en' locale, the encoding be 'utf8'.

=item direction - String

The text direction used by the locale. One of the following: 'ltr' or 'rtl'.
For the 'en' locale, the direction will be 'ltr'.

=back

=head3 EXAMPLES

=head4 Requesting the common attributes (Template Toolkit)

    SET attributes = execute('Locale', 'get_attributes', {});

Will return the following in the data field:

    {
       'locale'    => 'en',
       'encoding'  => 'utf-8',
       'direction' => 'ltr',
    }

=head4 Requesting a specific attribute (Template Toolkit)

    SET attributes = execute('Locale', 'get_attributes', {
        'attributes' => 'locale'
    } );

Will return the following in the data field:

    {
       'locale'    => 'en',
    }

=head4 Requesting multiple specific attributes (Template Toolkit)

    SET attributes = execute('Locale', 'get_attributes', {
        'attributes' => 'locale,name'
    } );

Will return the following in the data field:

    {
       'locale'    => 'en',
       'name'      => 'English'
    }

=cut

sub get_attributes {
    my ( $args, $result ) = @_;

    $lh ||= Cpanel::Locale::lh();

    my @IGNORE    = qw (api.version cpanel_jsonapi_module cpanel_jsonapi_func cpanel_jsonapi_apiversion);
    my @DEFAULTS  = qw (locale encoding direction);
    my $SUPPORTED = {
        'locale'    => 'get_user_locale',
        'name'      => 'get_user_locale_name',
        'encoding'  => 'encoding',
        'direction' => 'get_html_dir_attr',
    };

    my $csv = $args->get('attributes') // '';
    my @requested_attributes;
    for my $attribute ( split( ',', $csv ) ) {
        next if grep { $attribute eq $_ } @IGNORE;
        push @requested_attributes, $attribute;
    }

    # Use the default list. Note we do not fetch the name by default, but you can still request it if you want.
    if ( !@requested_attributes ) {
        @requested_attributes = (@DEFAULTS);
    }

    my $data = {};
    foreach my $attribute (@requested_attributes) {
        next if grep { $attribute eq $_ } @IGNORE;
        if ( my $func = $SUPPORTED->{$attribute} ) {
            $data->{$attribute} = $lh->$func();
        }
        else {
            $result->raw_warning( $lh->maketext( 'Unknown attribute: [_1]', $attribute ) );
        }
    }

    $result->data($data);

    return 1;
}

=head2 set_locale

Set the locale for the current user to the requested locale.

=head3 ARGUMENTS

=over

=item locale - String

ISO 3166 locale code to set as the current users locale. May also include country or region code.

    Example    | Description
    -------------------------------------------
    en         | English
    nb         | Norwegian Bokmål
    es         | Spanish
    es_es      | Spanish as spoken in Spain.
    vi         | Vietnamese

It should be from the list of available locales returned by L<Cpanel::API::Locales::list_locales>

=back

=head3 RETURNS

Boolean - 1 if the users locale is set, 0 otherwise

=cut

sub set_locale {
    my ( $args, $result ) = @_;
    $lh ||= Cpanel::Locale::lh();
    my ($country_code) = $args->get_required('locale');
    $lh->set_user_locale($country_code);    # will throw on error
    return 1;
}

=head2 list_locales

Get a list of the locales available.

=head3 RETURNS

An array with one or more available locale structures
each with the following fields:

=over

=item locale_name - String

short name for the locale

=item direction - String

one of 'ltr' or 'rtl'

=item locale - String

The ISO 3166 locale code. May also include the country or region code.

    Example    | Description
    -------------------------------------------
    en         | English
    nb         | Norwegian Bokmål
    es         | Spanish
    es_es      | Spanish as spoken in Spain.
    vi         | Vietnamese

=item name - String

The name of language in the current locale.

=back

=head3 EXAMPLES

=head4 Requesting the available locales (Template Toolkit)

    SET locales = execute('Locale', 'list_locales', {});

Will return something like the following in the data field:

    [
        {
           "local_name" : "suomi",
           "direction" : "ltr",
           "locale" : "fi",
           "name" : "Finnish"
        },
        ...
        {
            "name" : "English",
            "local_name" : "English",
            "locale" : "en",
            "direction" : "ltr"
        },
        ...
        {
            "name" : "Chinese (Taiwan)",
            "direction" : "ltr",
            "locale" : "zh_tw",
            "local_name" : "中文（台湾）"
        }
    ]
=cut

sub list_locales {
    my ( $args, $result ) = @_;

    $lh ||= Cpanel::Locale::lh();
    $result->data( $lh->get_locales() );

    return 1;
}

our %API = (
    get_attributes => { allow_demo => 1 },
    list_locales   => { allow_demo => 1 },
);

1;
