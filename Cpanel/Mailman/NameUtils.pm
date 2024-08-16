package Cpanel::Mailman::NameUtils;

# cpanel - Cpanel/Mailman/NameUtils.pm             Copyright 2022 cPanel, L.L.C.
#                                                           All rights reserved.
# copyright@cpanel.net                                         http://cpanel.net
# This code is subject to the cPanel license. Unauthorized copying is prohibited

use strict;
use warnings;

use Cpanel::Context ();

=head1 NAME

Cpanel::Mailman::NameUtils - utilities for mailing list names

=head1 DESCRIPTION

This module contains functions for munging, parsing, composing and syntax-validating
mailman mailing list names.

=head1 SYNOPSIS

  use Cpanel::Mailman::NameUtils ();

  my $list_name = Cpanel::Mailman::NameUtils::make_name($list, $domain);

  return unless ( Cpanel::Mailman::NameUtils::is_valid_name($list_name) );

  my ($original_list, $original_domain) = Cpanel::Mailman::NameUtils::parse_name($list_name);

  my $normalized_list_name = Cpanel::Mailman::NameUtils::normalize_name($list_name);

=head1 FUNCTIONS

=head2 make_name( $list, $domain )

Returns the mailman list name for this list.

Throws string exceptions if the list or domain arguments are empty

=cut

sub make_name {
    my ( $listname, $domain ) = @_;

    die "Missing list name" if !length $listname;
    die "Missing domain"    if !length $domain;

    return $listname . "_" . $domain;
}

=head2 parse_name( $list_name )

Returns an array with the list name and domain.

Throws string exceptions if the list_name can not be split
into localpart and domain segments.

=cut

sub parse_name {
    my ($list_name) = @_;

    Cpanel::Context::must_be_list();

    my @parts = _parse_name($list_name);

    die "List name “$list_name” is not normalized or was invalid" if !@parts;
    return @parts;
}

sub _parse_name {
    my ($list_name) = @_;

    # min/max length requirements
    # min: 1 localpart + 1 separator + 3 domain
    # max: 255 filesystem limit - 5 for .mbox extension
    return unless ( length($list_name) > 4 && length($list_name) <= 250 );

    #This will split on the rightmost underscore.
    my $separator_position = rindex( $list_name, '_' );
    return unless ( $separator_position > 0 && $separator_position < length($list_name) - 3 );

    return ( substr( $list_name, 0, $separator_position ), substr( $list_name, $separator_position + 1 ) );
}

=head2 normalize_name( $list_name )

Returns an a list name in the canonical mailman form.

This will remove leading path components, switch the domain
separator character, and correct capitalization.

Throws no errors.

=cut

sub normalize_name {
    my ($list_name) = @_;

    if ( length($list_name) ) {

        # strip path component
        substr( $list_name, 0, rindex( $list_name, '/' ) + 1, '' );

        $list_name =~ tr{@}{_};
        $list_name =~ tr{A-Z}{a-z};
    }
    return $list_name;
}

=head2 is_valid_name( $list_name )

Returns 1 or 0 to indicate if the supplied mailman
list name is syntactically valid.

The validation requires a full list name with the
domain part included.

The maximum size of the local part portion of a list name
is constrained by the size of the domain portion.

Throws no errors.

=cut

sub is_valid_name {
    my ( $localpart, $domain ) = _parse_name( $_[0] );

    if ( !defined $localpart || $localpart =~ tr{a-z0-9_.-}{}c ) {
        return 0;
    }

    require Cpanel::Validate::Domain::Tiny;

    return ( scalar( Cpanel::Validate::Domain::Tiny::validdomainname( $domain, 1 ) ) ? 1 : 0 );
}

1;
