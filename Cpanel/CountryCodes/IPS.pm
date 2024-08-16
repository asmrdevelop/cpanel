package Cpanel::CountryCodes::IPS;

# cpanel - Cpanel/CountryCodes/IPS.pm              Copyright 2022 cPanel, L.L.C.
#                                                           All rights reserved.
# copyright@cpanel.net                                         http://cpanel.net
# This code is subject to the cPanel license. Unauthorized copying is prohibited

use strict;
use warnings;

use Cpanel::Autodie    ();
use Cpanel::LoadFile   ();
use Cpanel::Exception  ();
use Cpanel::LoadModule ();

our $DB_PATH      = "/usr/local/cpanel/var/country_ips";
our $CIDR_DB_PATH = "/usr/local/cpanel/var/country_cidrs";

=encoding utf-8

=head1 NAME

Cpanel::CountryCodes::IPS - Tools to fetch IP ranges for a given country code.

=head1 SYNOPSIS

    use Cpanel::CountryCodes::IPS ();

    my @US_ranges = Cpanel::CountryCodes::IPS::get_ipbin16_ranges_for_code('US');
    my @AU_ranges = Cpanel::CountryCodes::IPS::get_ipbin16_ranges_for_code('AU');

    my $valid = Cpanel::CountryCodes::IPS::code_has_entry('US');

    my $invalid = Cpanel::CountryCodes::IPS::code_has_entry('XXdog');

=head1 DESCRIPTION

This module is generally used to provide a list of IP ranges for
a given country code.

It should not be confused with Cpanel::CountryCodes which is
intended to provide a complete list of known country codes
unlike Cpanel::CountryCodes::IPS which only provides data
for country codes that we have in the database.

=head2 get_ipbin16_ranges_for_code($code)

Returns an arrayref of arrayrefs which contain the start and
end ranges of an ip block assigned to the given country code.

The ip addresses are in 16-octet-long binary format.

e.g. "1.2.3.4" => "\0\0\0\0\0\0\0\0\0\0\xff\xff\1\2\3\4"

Example return:

[
  ["\0\0\0\0\0\0\0\0\0\0\xff\xff\1\2\3\4","\0\0\0\0\0\0\0\0\0\0\xff\xff\1\2\3\5"],
  ["\0\0\0\0\0\0\0\0\0\0\xff\xff\1\2\3\8","\0\0\0\0\0\0\0\0\0\0\xff\xff\1\2\3\9"],
]

These strings can be made human readable with
Cpanel::IP::Convert::binip_to_human_readable_ip()

=cut

sub get_ipbin16_ranges_for_code {
    my ($code) = @_;
    if ( !code_has_entry($code) ) {
        die Cpanel::Exception::create( 'InvalidParameter', '“[_1]” is not a known [asis,ISO 3166] country code.', [$code] );
    }
    my @ranges = unpack( "(a16)*", Cpanel::LoadFile::load("$DB_PATH/$code") );
    my @range_group;
    while ( my @range = splice( @ranges, 0, 2 ) ) {
        push @range_group, \@range;
    }
    return \@range_group;
}

=head2 get_cidr_ranges_for_code($code)

Get the output from C<get_ipbin16_ranges_for_code> and translates the binary format
to CIDR format.

=over

=item Input

=over

=item $code - String

The country code to get the IP ranges for.

The country code must be a valid ISO 3166 country code and correspond to a file
in the C</usr/local/cpanel/var/country_ips> directory.

=back

=item Output

=over

Returns an arrayref of IP ranges in human-readable CIDR notation.

=back

=back

=cut

sub get_cidr_ranges_for_code {
    my ($code) = @_;
    if ( !_looks_like_country_code($code) ) {
        die Cpanel::Exception::create( 'InvalidParameter', '“[_1]” is not a known [asis,ISO 3166] country code.', [$code] );
    }
    return [ split( m{\n}, _get_cidr_db_file("$CIDR_DB_PATH/$code") ) ];
}

sub _get_cidr_db_file {
    my ($file) = @_;
    return Cpanel::LoadFile::load($file);
}

=head2 code_has_entry($code)

If the CountryCode IPS database has an entry for the given country
code this returns 1.

If the CountryCode IPS database does not have an entry for the given
country code this returns 0.

=cut

sub code_has_entry {
    return ( _looks_like_country_code( $_[0] ) && Cpanel::Autodie::exists("$DB_PATH/$_[0]") );
}

=head2 get_countries_with_known_ip_ranges

Get a list of Country Codes for which we have IP Ranges

=over 2

=item Output

=over 3

=item C<ARRAYREF>

    returns a list of country codes for which we have ip ranges and their territory names

    [
        {code:"AA", name:"Aruba"}
    ]

=back

=back

=cut

sub get_countries_with_known_ip_ranges {
    Cpanel::LoadModule::load_perl_module("Cpanel::FileUtils::Dir");
    my $locales_obj       = _locale()->get_locales_obj();
    my $nodes             = Cpanel::FileUtils::Dir::get_directory_nodes_if_exists($DB_PATH);
    my @valid_nodes       = grep { _looks_like_country_code($_) } @{$nodes};
    my $other_territories = {
        'SS' => 'South Sudan',
        'SX' => 'Sint Maarten',
        'CW' => 'Curaçao'
    };
    my @countries = map {
        {
            "code" => $_,
            "name" => $locales_obj->get_territory_from_code($_) || $other_territories->{$_} || $_
        }
    } @valid_nodes;

    return \@countries;
}

my $_locale;

sub _locale {
    Cpanel::LoadModule::load_perl_module("Cpanel::Locale");
    return $_locale ||= Cpanel::Locale->get_handle();
}

sub _looks_like_country_code {
    return length $_[0] == 2 && $_[0] !~ tr{A-Z}{}c ? 1 : 0;
}

1;
