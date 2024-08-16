package Whostmgr::API::1::Utils::Domains;

# cpanel - Whostmgr/API/1/Utils/Domains.pm         Copyright 2022 cPanel, L.L.C.
#                                                           All rights reserved.
# copyright@cpanel.net                                         http://cpanel.net
# This code is subject to the cPanel license. Unauthorized copying is prohibited

use strict;
use warnings;

use Try::Tiny;

=encoding utf-8

=head1 NAME

Whostmgr::API::1::Utils::Domains - whmapi1 utils to extract domains from args

my $domains = validate_domains_or_die( $args );

=head1 DESCRIPTION

This module provides utility functions for domains coming from WHM API args.
Each method will look for one or more C<domain> arguments and validate them
against the domains the user controls. If the user attempts to specify any
domains they do not control, these methods will die with an exception.

If the system hostname is specified as a domain, the methods validate that
the calling user has root privileges.

=head2 $domains_to_value_hr = validate_domain_value_pairs_or_die( $args, $value )

Gets a list of key/value pairs where the key is a C<domain> argument and the
value is the next positional argument that matches the specified C<$value>.

If there are not exactly as many C<domain> as there are C<$value> arguments,
this method throws an exception.

=over 2

=item Input

=over 3

=item C<HASHREF>

A hashref of API arguments

=item C<SCALAR>

The argument to pair with the C<domain> argument.

=back

=item Output

=over 3

=item C<HASHREF>

A hashref where the keys are the domains and the values are the arguments that
match the input value.

=back

=back

=cut

sub validate_domain_value_pairs_or_die {

    my ( $args, $value ) = @_;

    die Cpanel::Exception::create_raw( 'MissingParameter', 'A HASHREF of arguments' ) if !$args;
    die Cpanel::Exception::create_raw( 'InvalidParameter', 'A HASHREF object' )       if ref $args ne 'HASH';
    die Cpanel::Exception::create_raw( 'MissingParameter', 'value argument name' )    if !$value;

    require Whostmgr::API::1::Utils;
    my $domains_hr = Whostmgr::API::1::Utils::map_length_required_multiple_to_key_values( $args, "domain", $value );

    _validate_domains_or_die( [ keys %$domains_hr ] );

    return $domains_hr;
}

=head2 $domains_ar = validate_domains_or_die( $args )

Gets a list of domains provided as arguments.

If there are no C<domain> arguments provided, or any of them are empty, this
method throws an exception.

=over 2

=item Input

=over 3

=item C<HASHREF>

A hashref of API arguments

=back

=item Output

=over 3

=item C<ARRAYREF>

An arrayref of the domains provided as arguments.

=back

=back

=cut

sub validate_domains_or_die {

    my ($args) = @_;

    die Cpanel::Exception::create_raw( 'MissingParameter', 'A HASHREF of arguments' ) if !$args;
    die Cpanel::Exception::create_raw( 'InvalidParameter', 'A HASHREF object' )       if ref $args ne 'HASH';

    require Whostmgr::API::1::Utils;
    my @domains = Whostmgr::API::1::Utils::get_length_required_arguments( $args, "domain" );

    _validate_domains_or_die( \@domains );

    return \@domains;
}

sub _validate_domains_or_die {

    my ($domains) = @_;

    require Cpanel::Sys::Hostname;
    my $hostname = Cpanel::Sys::Hostname::gethostname();

    require Whostmgr::Authz;

    my @invalid;
    foreach my $domain ( grep { $_ ne $hostname } @$domains ) {
        try {
            Whostmgr::Authz::verify_domain_access($domain);
        }
        catch {
            push @invalid, $domain;
        };
    }

    if ( grep { $_ eq $hostname } @$domains ) {
        push @invalid, $hostname if !Whostmgr::ACLS::hasroot();    # PPI NO PARSE - will always be loaded in xml-api.pl
    }

    if (@invalid) {
        require Cpanel::Exception;
        die Cpanel::Exception->create( "The account “[_1]” does not control the [list_and_quoted,_2] [numerate,_3,domain,domains].", [ $ENV{'REMOTE_USER'}, \@invalid, scalar @invalid ] );
    }

    return;
}

1;
