package Cpanel::Market::Provider::cPStore::Constants;

# cpanel - Cpanel/Market/Provider/cPStore/Constants.pm
#                                                  Copyright 2022 cPanel, L.L.C.
#                                                           All rights reserved.
# copyright@cpanel.net                                         http://cpanel.net
# This code is subject to the cPanel license. Unauthorized copying is prohibited

use strict;
use warnings;

=encoding utf-8

=head1 NAME

Cpanel::Market::Provider::cPStore::Constants

=head1 DESCRIPTION

Constants for the cPStore provider for cPanel Market.

=cut

#----------------------------------------------------------------------

use Cpanel::SSL::Providers::Sectigo ();
use Cpanel::LocaleString            ();
use Cpanel::Regex                   ();

#----------------------------------------------------------------------

=head1 CONSTANTS

=cut

*URI_DCV_RELATIVE_PATH          = \*Cpanel::SSL::Providers::Sectigo::URI_DCV_RELATIVE_PATH;
*REQUEST_URI_DCV_PATH           = \*Cpanel::SSL::Providers::Sectigo::REQUEST_URI_DCV_PATH;
*URI_DCV_ALLOWED_CHARACTERS     = \*Cpanel::SSL::Providers::Sectigo::URI_DCV_ALLOWED_CHARACTERS;
*URI_DCV_RANDOM_CHARACTER_COUNT = \*Cpanel::SSL::Providers::Sectigo::URI_DCV_RANDOM_CHARACTER_COUNT;
*HTTP_DCV_MAX_REDIRECTS         = \*Cpanel::SSL::Providers::Sectigo::HTTP_DCV_MAX_REDIRECTS;

# Note naming discrepancies here:
*EXTENSION      = \*Cpanel::SSL::Providers::Sectigo::HTTP_DCV_PATH_EXTENSION;
*DCV_USER_AGENT = \*Cpanel::SSL::Providers::Sectigo::HTTP_DCV_USER_AGENT;

=head2 FINAL_CPSTORE_CERTIFICATE_ERRORS

A list of cPStore error codes (e.g., C<OrderCanceled>) that indicate we
should stop polling for the given certificate order item ID.

=cut

use constant FINAL_CPSTORE_CERTIFICATE_ERRORS => (

    # “Constructed” errors. See get_certificate_if_available().
    'CA:rejected',
    'CA:revoked',

    # Not much explanation needed here?
    'OrderCanceled',
    'OrderItemCanceled',    #unimplemented in cPStore as of April 2016

    # Unfortunately, two different spellings for this error exist.
    'ItemNotFound',
    'Item::NotFound',
);

our %SSL_SHORT_TO_PRICING = map {
    (
        "cpanel-$_-ssl" => "cp_${_}_ea_domain",
        "comodo-$_-ssl" => "comodo_${_}_ea_domain",
    );
} qw(dv ov ev dv-2yr dv-3yr ev-2yr ev-3yr ov-2yr ov-3yr);

our %SSL_SHORT_TO_WILDCARD_PRICING = map {
    (
        "cpanel-$_-ssl" => "cp_${_}_wc_domain",
        "comodo-$_-ssl" => "comodo_${_}_wc_domain",
    );
} qw(dv ov ev dv-2yr dv-3yr ev-2yr ev-3yr ov-2yr ov-3yr);

#This is a function, not a constant, to ensure that each call returns
#a fresh data structure.
#
#It returns a list of hashes in order to preserve order.
#NOTE: The “_to_csr” attribute is NOT given to the API caller
sub get_ov_identity_verification_data {
    return (
        {
            name    => 'organizationName',
            label   => Cpanel::LocaleString->new('Organization Name'),
            _to_csr => 1,
        },
        {
            name        => 'duns_number',
            is_optional => 1,
            label       => Cpanel::LocaleString->new('Dun [output,amp] Bradstreet [output,acronym,D-U-N-S,Data Universal Numbering System] Number'),
            pattern     => "^$Cpanel::Regex::regex{'DUNS'}\$",
            description => Cpanel::LocaleString->new( '[quant,_1,consecutive digit,consecutive digits] or “[_2]” ([output,url,_3,More information])', 9, '##-###-####', 'https://go.cpanel.net/get_duns' ),
        },
        {
            name    => 'streetAddress',
            label   => Cpanel::LocaleString->new('Street Address'),
            _to_csr => 1,
        },
        {
            name    => 'localityName',
            label   => Cpanel::LocaleString->new('City'),
            _to_csr => 1,
        },
        {
            name    => 'stateOrProvinceName',
            label   => Cpanel::LocaleString->new('State or Province'),
            _to_csr => 1,
        },
        {
            name    => 'postalCode',
            label   => Cpanel::LocaleString->new('Postal Code'),
            _to_csr => 1,
        },
        {
            name    => 'countryName',
            label   => Cpanel::LocaleString->new('Country Code'),
            type    => 'country_code',
            _to_csr => 1,
        },

        {
            name  => 'rep_forename',
            label => Cpanel::LocaleString->new('Representative’s Given (First) Name'),
        },

        {
            name  => 'rep_surname',
            label => Cpanel::LocaleString->new('Representative’s Surname (Last Name)'),
        },

        {
            name  => 'rep_email_address',
            label => Cpanel::LocaleString->new('Representative’s Email Address'),
            type  => 'email',
        },

        {
            name        => 'rep_telephone',
            type        => 'tel',
            is_optional => 1,
            label       => Cpanel::LocaleString->new('Representative’s Telephone Number'),
            description => Cpanel::LocaleString->new('This should be one of the organization’s publicly-listed telephone numbers.'),
        }
    );
}

sub get_ev_identity_verification_data {
    return (
        get_ov_identity_verification_data(),
        {
            name    => 'business_category',
            label   => Cpanel::LocaleString->new('Business Category'),
            type    => 'choose_one',
            options => [

                #Wording as per email from Rich Smith at Comodo on 4 Nov 2016
                [ b => Cpanel::LocaleString->new( 'Incorporated Business (“[_1]”)',     'Private Organization' ) ],
                [ d => Cpanel::LocaleString->new( 'Non-incorporated Business (“[_1]”)', 'Business Entity' ) ],
                [ c => Cpanel::LocaleString->new( 'Government Entity (“[_1]”)',         'Government Entity' ) ],
            ],
            description => Cpanel::LocaleString->new( 'Consult the [output,url,_1,EV SSL Certificate Guidelines] for more information about this field’s options.', 'https://cabforum.org/extended-validation/' ),
        },
        {
            name        => "joi_locality_name",
            is_optional => 1,
            label       => Cpanel::LocaleString->new('City Where Incorporated ([output,abbr,JOI,Jurisdiction of Incorporation])'),
        },
        {
            name        => "joi_state_or_province_name",
            is_optional => 1,
            label       => Cpanel::LocaleString->new('State or Province Where Incorporated ([output,abbr,JOI,Jurisdiction of Incorporation])'),
        },

        #identified as required during work on AA-2700
        {
            name  => "joi_country_name",
            type  => 'country_code',
            label => Cpanel::LocaleString->new('Country Code Where Incorporated ([output,abbr,JOI,Jurisdiction of Incorporation])'),
        },

        {
            name        => "date_of_incorporation",
            is_optional => 1,
            label       => Cpanel::LocaleString->new('Date of Incorporation'),
            type        => 'date',
        },
        {
            name        => "assumed_name",
            is_optional => 1,
            label       => Cpanel::LocaleString->new('Assumed Name ([output,abbr,DBA,Doing Business As])'),
        },
    );
}

=head2 ITEM_IDS

A set of cPStore item IDs for common products.

=cut

our $ITEM_IDS = {
    standard_trial_license => 96,
};

1;
