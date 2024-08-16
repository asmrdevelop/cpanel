package Cpanel::WildcardDomain::Tiny;

# cpanel - Cpanel/WildcardDomain/Tiny.pm           Copyright 2022 cPanel, L.L.C.
#                                                           All rights reserved.
# copyright@cpanel.net                                         http://cpanel.net
# This code is subject to the cPanel license. Unauthorized copying is prohibited

use strict;
use warnings;

=encoding utf-8

=head1 NAME

Cpanel::WildcardDomain::Tiny - Determine if a string is a wildcard domain

=head1 SYNOPSIS

    use Cpanel::WildcardDomain::Tiny ();

    if( Cpanel::WildcardDomain::Tiny::is_wildcard_domain( $domain ) ) {
         ...
    }

=head1 DESCRIPTION

This module is used to determine if a passed in string is a wildcard domain.
Please note that this is a Tiny module, so please don't add a lot of code to
it.

=cut

=head2 is_wildcard_domain

This function determines if the passed in string is a wildcard domain.

=head3 Input

=over 3

=item C<SCALAR> $domain

    The domain that will be checked to see if it is a wildcard domain.

=back

=head3 Output

=over 3

=item C<SCALAR>

    This function returns 1 if the passed in domain is a wildcard; 0 if it is not.

=back

=head3 Exceptions

None.

=cut

sub is_wildcard_domain {
    return ( index( $_[0], '*.' ) == 0 ? 1 : 0 );
}

=head2 contains_wildcard_domain

This function determines if the passed in domain contains a wildcard.

=head3 Input

=over 3

=item C<SCALAR> $domain

    The domain that will be checked to see if it contains a wildcard.

=back

=head3 Output

=over 3

=item C<SCALAR>

    This function returns 1 if the passed in domain contains a wildcard; 0 if it does not.

=back

=head3 Exceptions

None.

=cut

sub contains_wildcard_domain {
    return ( index( $_[0], '*' ) > -1 ? 1 : 0 );
}

1;    # Magic true value required at end of module
