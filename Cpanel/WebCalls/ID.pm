package Cpanel::WebCalls::ID;

# cpanel - Cpanel/WebCalls/ID.pm                   Copyright 2022 cPanel, L.L.C.
#                                                           All rights reserved.
# copyright@cpanel.net                                         http://cpanel.net
# This code is subject to the cPanel license. Unauthorized copying is prohibited

use cPstrict;

=encoding utf-8

=head1 NAME

Cpanel::WebCalls::ID

=head1 SYNOPSIS

    if ( Cpanel::WebCalls::ID::is_valid($specimen) ) {
        # …
    }

    my $new_index = Cpanel::WebCalls::ID::create();

=head1 DESCRIPTION

This module contains logic for dealing with cPanel webcall IDs.

=cut

#----------------------------------------------------------------------

=head1 GLOBAL VARIABLES

=head2 $LENGTH

The proper length of an ID.

=cut

our $LENGTH;

BEGIN {
    our $LENGTH = 32;
}

#----------------------------------------------------------------------

=head1 FUNCTIONS

=head2 $new_id = create()

Creates a new index.

=cut

sub create () {
    local ( $@, $! );
    require Cpanel::Rand::Get;

    return Cpanel::Rand::Get::getranddata(
        $LENGTH,
        [ 'a' .. 'z' ],
    );
}

#----------------------------------------------------------------------

=head2 $yn = is_valid($specimen)

Returns a boolean that indicates validity (1) or invalidity (0).

=cut

sub is_valid ($specimen) {
    return 0 if $LENGTH != length $specimen;

    return 0 if $specimen =~ tr<a-z><>c;

    return 1;
}

1;
