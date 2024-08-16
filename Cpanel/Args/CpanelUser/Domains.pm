package Cpanel::Args::CpanelUser::Domains;

# cpanel - Cpanel/Args/CpanelUser/Domains.pm       Copyright 2022 cPanel, L.L.C.
#                                                           All rights reserved.
# copyright@cpanel.net                                         http://cpanel.net
# This code is subject to the cPanel license. Unauthorized copying is prohibited

use strict;
use warnings;

=encoding utf-8

=head1 NAME

Cpanel::Args::CpanelUser::Domains - Utility functions for processing arguments for cPanel user domains

=head1 SYNOPSIS

    use Cpanel::Args::CpanelUser::Domains;

    my $domain_to_arg_hashref = validate_domain_pairs_or_die( $args, $value );
    my $domains = validate_domains_or_die( $args );

=head1 DESCRIPTION

This module provides utility functions for handling cPanel user domains coming
from C<Cpanel::Args> objects. Each method will look for one or more C<domain>
arguments and validate them against the list of domains the cPanel user
controls. If the user attempts to specify any domains they do not control,
these methods will die with an exception.

=head2 $domains_to_value_hr = validate_domain_value_pairs_or_die( $args, $value )

Gets a list of key/value pairs where the key is a C<domain> argument and the
value is the next positional argument that matches the specified C<$value>.

If there are not exactly as many C<domain> as there are C<$value> arguments,
this method throws an exception.

=over 2

=item Input

=over 3

=item C<SCALAR>

A C<Cpanel::Args> object

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

    die Cpanel::Exception::create_raw( 'MissingParameter', 'A Cpanel::Args object' ) if !$args;
    die Cpanel::Exception::create_raw( 'InvalidParameter', 'A Cpanel::Args object' ) if !ref $args || ref $args ne 'Cpanel::Args';
    die Cpanel::Exception::create_raw( 'MissingParameter', 'value argument name' )   if !$value;

    my $domains_hr = $args->map_length_required_multiple_to_key_values( 'domain', $value );
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

=item C<SCALAR>

A C<Cpanel::Args> object

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

    die Cpanel::Exception::create_raw( 'MissingParameter', 'A Cpanel::Args object' ) if !$args;
    die Cpanel::Exception::create_raw( 'InvalidParameter', 'A Cpanel::Args object' ) if !ref $args || ref $args ne 'Cpanel::Args';

    my @domains = $args->get_length_required_multiple('domain');
    _validate_domains_or_die( \@domains );

    return \@domains;
}

sub _validate_domains_or_die {

    my ($domains) = @_;

    require Cpanel::Set;
    my @invalid = Cpanel::Set::difference(
        $domains,
        _domains(),
    );

    if (@invalid) {
        require Cpanel::Exception;
        die Cpanel::Exception->create( "You do not control the [list_and_quoted,_1] [numerate,_2,domain,domains].", [ \@invalid, scalar @invalid ] );
    }

    return;
}

# Overidden in tests
sub _domains {
    return [ $Cpanel::CPDATA{'DOMAIN'}, @{ $Cpanel::CPDATA{'DOMAINS'} } ];
}

1;
