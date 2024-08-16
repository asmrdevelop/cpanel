package Whostmgr::Exim::BlockedCountries;

# cpanel - Whostmgr/Exim/BlockedCountries.pm       Copyright 2022 cPanel, L.L.C.
#                                                           All rights reserved.
# copyright@cpanel.net                                         http://cpanel.net
# This code is subject to the cPanel license. Unauthorized copying is prohibited

use cPstrict;

=encoding utf-8

=head1 NAME

Whostmgr::Exim::BlockedCountries - Functions to manage the countries blocked by Exim

=head1 SYNOPSIS

    use Whostmgr::Exim::BlockedCountries ();

    Whostmgr::Exim::BlockedCountries::modify_blocked_incoming_email_countries( "block", [ "AR" ] );
    Whostmgr::Exim::BlockedCountries::modify_blocked_incoming_email_countries( "unblock", [ "AR" ] );
    my $countries_ar = Whostmgr::Exim::BlockedCountries::list_blocked_incoming_email_countries();

=head1 DESCRIPTION

This module provides functions for managing the countries that are blocked from sending mail to
this server by Exim.

Countries are blocked or unblocked using their ISO 3166 codes and the codes are used to build a
list of IP address ranges that Exim will reject incoming mail from.

=head1 FUNCTIONS

=cut

our $_BLOCKED_COUNTRIES_FILE   = '/etc/blocked_incoming_email_countries';
our $_BLOCKED_COUNTRY_IPS_FILE = '/etc/blocked_incoming_email_country_ips';

=head2 modify_blocked_incoming_email_countries( $action, $country_codes_ar )

Blocks or unblocks the specified countries from sending mail to the server.

=over

=item Input

=over

=item $action - STRING

The action to perform.

The action argument must be either “block” or “unblock” to indicate whether the
specified country code should be added to or removed from the list of blocked
countries.

=item $country_codes_ar - STRING

An ARRAYREF of the country codes to perform the action for.

The country codes must be valid ISO 3166 country code and correspond to a file
in the C</usr/local/cpanel/var/country_ips> directory.

=back

=item Output

=over

This function returns 1 if the database was update, 0 if no changes were required,
undef on failure.

=back

=back

=cut

sub modify_blocked_incoming_email_countries ( $action, $country_codes_ar ) {

    if ( $action ne 'block' && $action ne 'unblock' ) {
        require Cpanel::Exception;
        die Cpanel::Exception::create( 'InvalidParameter', "The parameter “[_1]” must be [list_or_quoted,_2].", [ "action", [ "block", "unblock" ] ] );
    }

    require Cpanel::CountryCodes::IPS;

    my @invalid_codes = grep { !Cpanel::CountryCodes::IPS::code_has_entry($_) } @$country_codes_ar;

    if (@invalid_codes) {
        require Cpanel::Exception;
        die Cpanel::Exception::create( 'InvalidParameter', '[list_and_quoted,_1] [numerate,_2,is not a valid,are not valid] “[_3]” [numerate,_2,value,values].', [ \@invalid_codes, scalar @invalid_codes, 'country_code' ] );
    }

    require Cpanel::StringFunc::File;
    require Cpanel::CommandQueue;

    my $cq = Cpanel::CommandQueue->new();

    my $did_something;
    if ( $action eq 'block' ) {
        $cq->add(
            sub { $did_something = Cpanel::StringFunc::File::addlinefile( $_BLOCKED_COUNTRIES_FILE, $country_codes_ar ) },
            sub {
                Cpanel::StringFunc::File::remlinefile( $_BLOCKED_COUNTRIES_FILE, $country_codes_ar, 'full' );
                $did_something = 0;
            },
        );
    }
    else {
        $cq->add(
            sub { $did_something = Cpanel::StringFunc::File::remlinefile( $_BLOCKED_COUNTRIES_FILE, $country_codes_ar, 'full' ) },
            sub {
                Cpanel::StringFunc::File::addlinefile( $_BLOCKED_COUNTRIES_FILE, $country_codes_ar );
                $did_something = 0;
            },
        );
    }

    $cq->add( sub { _rebuild_blocked_country_ips() if $did_something } );

    $cq->run();

    return $did_something;
}

=head2 list_blocked_incoming_email_countries

Lists the country codes that are blocked from sending mail to the server

=over

=item Input

=over

None

=back

=item Output

=over

This function returns an ARRAYREF of the ISO 3166 country codes blocked by Exim.

=back

=back

=cut

sub list_blocked_incoming_email_countries {
    require Cpanel::LoadFile;
    my @countries = split( m{\n}, Cpanel::LoadFile::load_if_exists($_BLOCKED_COUNTRIES_FILE) // '' );
    return \@countries;
}

my %_never_block_cidrs = (
    '127.0.0.0/8'    => 1,
    '10.0.0.0/8'     => 1,
    '192.168.0.0/16' => 1,
    '172.16.0.0/12'  => 1,
);

sub _rebuild_blocked_country_ips {

    require Cpanel::CountryCodes::IPS;
    require Cpanel::LoadFile;
    require Cpanel::FileUtils::Write;

    my @cidrs;
    foreach my $country_code ( split( m{\n}, Cpanel::LoadFile::load_if_exists($_BLOCKED_COUNTRIES_FILE) // '' ) ) {
        if ( my $ranges = eval { Cpanel::CountryCodes::IPS::get_cidr_ranges_for_code($country_code) } ) {
            if ( $country_code eq 'ZZ' ) {
                push @cidrs, grep { !$_never_block_cidrs{$_} } @$ranges;
            }
            else {
                push @cidrs, @$ranges;

            }
        }
        else {
            my $err = $@;
            require Cpanel::Debug;
            Cpanel::Debug::log_warn("Invalid country code “$country_code” found when rebuilding blocked IPs database: $err");
        }
    }

    Cpanel::FileUtils::Write::overwrite( $_BLOCKED_COUNTRY_IPS_FILE, join( "\n", @cidrs ), 0644 );

    return;
}

1;
