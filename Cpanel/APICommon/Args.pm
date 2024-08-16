package Cpanel::APICommon::Args;

# cpanel - Cpanel/APICommon/Args.pm                Copyright 2022 cPanel, L.L.C.
#                                                           All rights reserved.
# copyright@cpanel.net                                         http://cpanel.net
# This code is subject to the cPanel license. Unauthorized copying is prohibited

use strict;
use warnings;

=encoding utf-8

=head1 NAME

Cpanel::APICommon::Args

=head1 SYNOPSIS

    my $args_hr = { foo => [1, 2, 3] };
    Cpanel::APICommon::Args::expand_array_refs($args_hr);

=head1 DESCRIPTION

This module houses arguments logic that pertains to multiple cPanel & WHM
API versions.

=cut

#----------------------------------------------------------------------

# To defeat HTML escaping in Legacy.pm:
use Cpanel::IxHash ();

#----------------------------------------------------------------------

=head1 FUNCTIONS

=head2 expand_array_refs( \%ARGS )

This takes in a hashref and “unrolls” any array references found
as values into multiple hash values, as though the multiple values
had come from an HTML form submission and C<Cpanel::Form> had parsed the
submission. An API call can thus “reassemble” the array using
C<Cpanel::Args::get_length_required_multiple()> or a similar function.

This returns either a new hashref (with arrays expanded) if there was
need, or the passed-in hashref if there was no need.

NB: Empty arrayrefs in %ARGS are omitted from the returned hashref.

=cut

sub expand_array_refs {
    my ($args_hr) = @_;

    local ( $@, $! );

    my $duplicated;

    for my $key ( keys %$args_hr ) {
        next                                                 if !ref $args_hr->{$key};
        die "Unknown “$key” argument type: $args_hr->{$key}" if 'ARRAY' ne ref $args_hr->{$key};

        $args_hr    = {%$args_hr} if !$duplicated;
        $duplicated = 1;

        if ( !@{ $args_hr->{$key} } ) {
            delete $args_hr->{$key};
            next;
        }

        require Cpanel::HTTP::QueryString;
        require Cpanel::HTTP::QueryString::Legacy;

        my $query_string_sr = Cpanel::HTTP::QueryString::make_query_string_sr( $key => $args_hr->{$key} );

        local $Cpanel::IxHash::Modify = 'none';

        my $new_hr = Cpanel::HTTP::QueryString::Legacy::legacy_parse_query_string_sr($query_string_sr);
        @{$args_hr}{ keys %$new_hr } = values %$new_hr;
    }

    return $args_hr;
}

1;
