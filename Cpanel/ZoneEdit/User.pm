package Cpanel::ZoneEdit::User;

# cpanel - Cpanel/ZoneEdit/User.pm                 Copyright 2022 cPanel, L.L.C.
#                                                           All rights reserved.
# copyright@cpanel.net                                         http://cpanel.net
# This code is subject to the cPanel license. Unauthorized copying is prohibited

use cPstrict;

=encoding utf-8

=head1 NAME

Cpanel::ZoneEdit::User

=head1 SYNOPSIS

N/A (for now)

=head1 DESCRIPTION

This module contains logic specific to zone editing as a cPanel user.

=cut

#----------------------------------------------------------------------

use Cpanel::Context ();

#----------------------------------------------------------------------

# Internal-use constants:

use constant _ALLOWED_RECORD_TYPES__SIMPLE => (
    'A',
    'CNAME',
);

use constant _ALLOWED_RECORD_TYPES__ADVANCED => (
    _ALLOWED_RECORD_TYPES__SIMPLE,
    'AAAA',
    'CAA',
    'SRV',
    'TXT',
);

use constant _EXTRA_ALLOWED_RECORD_TYPES__CHANGEMX => (
    'MX',
);

#----------------------------------------------------------------------

=head1 FUNCTIONS

=head2 @types = get_allowed_record_types( $HAS_FEATURE_CR )

Returns a list of the allowed record types for a user. $HAS_FEATURE_CR
is a callback that takes a feature name and returns a boolean that indicates
whether the user in question can access that feature.

=cut

sub get_allowed_record_types ($has_feature_cr) {
    Cpanel::Context::must_be_list();

    my @accepted_rr_types;

    if ( $has_feature_cr->('zoneedit') ) {
        @accepted_rr_types = _ALLOWED_RECORD_TYPES__ADVANCED;
    }
    elsif ( $has_feature_cr->('simplezoneedit') ) {
        @accepted_rr_types = _ALLOWED_RECORD_TYPES__SIMPLE;
    }

    if ( $has_feature_cr->('changemx') ) {
        push @accepted_rr_types, _EXTRA_ALLOWED_RECORD_TYPES__CHANGEMX;
    }

    return @accepted_rr_types;
}

#----------------------------------------------------------------------

1;
