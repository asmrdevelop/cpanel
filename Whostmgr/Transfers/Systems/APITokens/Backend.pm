package Whostmgr::Transfers::Systems::APITokens::Backend;

# cpanel - Whostmgr/Transfers/Systems/APITokens/Backend.pm
#                                                  Copyright 2022 cPanel, L.L.C.
#                                                           All rights reserved.
# copyright@cpanel.net                                         http://cpanel.net
# This code is subject to the cPanel license. Unauthorized copying is prohibited

use cPstrict;

=encoding utf-8

=head1 NAME

Whostmgr::Transfers::Systems::APITokens::Backend

=head1 SYNOPSIS

Nothing to see here.

=head1 DESCRIPTION

This module implements backend logic for
L<Whostmgr::Transfers::Systems::APITokens>. It’s not meant to be called
except from that module.

=cut

#----------------------------------------------------------------------

use Cpanel::NameVariant ();

#----------------------------------------------------------------------

=head1 FUNCTIONS

=head2 $name = find_new_name( $TOKENS_OBJ, $MAX_LENGTH, $TOKEN_NAME )

Finds a name variant of $TOKEN_NAME that is a valid API token name
and doesn’t exist in $TOKENS_OBJ (a
L<Cpanel::Security::Authn::APITokens> instance>).

=cut

sub find_new_name ( $tokens_obj, $max_length, $token_name ) {    ## no critic qw(ProhibitManyArgs)

    my $existing_hr = $tokens_obj->read_tokens();

    my @names = map { $_->get_name() } values %$existing_hr;

    return Cpanel::NameVariant::find_name_variant(
        max_length => $max_length,
        name       => $token_name,
        test       => sub ($name_to_try) {
            return !grep { $_ eq $name_to_try } @names;
        },
    );
}

1;
