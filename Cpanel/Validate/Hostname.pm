package Cpanel::Validate::Hostname;

# cpanel - Cpanel/Validate/Hostname.pm             Copyright 2022 cPanel, L.L.C.
#                                                           All rights reserved.
# copyright@cpanel.net                                         http://cpanel.net
# This code is subject to the cPanel license. Unauthorized copying is prohibited

use cPstrict;

our $VERSION = 1.0;

=encoding utf-8

=head1 NAME

Cpanel::Validate::Hostname

=head1 SYNOPSIS

    if ( Cpanel::Validate::Hostname::is_minimally_valid($hostname) ) {
        # ...
    }
    else {
        # ...
    }

=head1 DESCRIPTION

This module implements hostname validation.

=cut

#----------------------------------------------------------------------

=head1 FUNCTIONS

=head2 $yn = is_minimally_valid( $SPECIMEN )

Returns a boolean that indicates validity.

=cut

sub is_minimally_valid ($specimen) {
    return _is_valid( $specimen, 1 );
}

=head2 $yn = is_valid( $SPECIMEN )

Like C<is_minimally_valid()> but requires at least 3 labels in $SPECIMEN.

=cut

sub is_valid ($specimen) {
    return _is_valid( $specimen, 2 );
}

#----------------------------------------------------------------------

sub _is_valid ( $domain, $required_leading_labels ) {

    if ( !defined $domain ) {
        return 0;
    }

    # No blank or space characters
    if ( $domain =~ m/\s+/ ) {
        return 0;
    }

    # No consecutive periods.
    if ( -1 != index( $domain, '..' ) ) {
        return 0;
    }

    # Cannot end with period
    if ( '.' eq substr( $domain, -1 ) ) {
        return 0;
    }

    # Cannot end with minus sign (or have a label that ends so)
    if ( $domain =~ m/[-](?=[.]|\z)/ ) {
        return 0;
    }

    # Must be able to fit in struct utsname
    if ( length $domain > 64 ) {
        return 0;
    }

    # Can't have an all-numeric TLD or be an IP address
    if ( $domain =~ m/\.[0-9]+\z/ ) {
        return 0;
    }

    # Must start with alpha numeric, and must have atleast one 'label' part - i.e., label.domain.tld
    if ( $domain =~ /^(?:[a-z0-9][a-z0-9\-]*\.){$required_leading_labels,}[a-z0-9][a-z0-9\-]*$/i ) {
        return 1;
    }

    return 0;
}

1;
