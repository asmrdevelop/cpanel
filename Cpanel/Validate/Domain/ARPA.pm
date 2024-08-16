package Cpanel::Validate::Domain::ARPA;

# cpanel - Cpanel/Validate/Domain/ARPA.pm          Copyright 2022 cPanel, L.L.C.
#                                                           All rights reserved.
# copyright@cpanel.net                                         http://cpanel.net
# This code is subject to the cPanel license. Unauthorized copying is prohibited

use cPstrict;

=encoding utf-8

=head1 NAME

Cpanel::Validate::Domain::ARPA

=head1 SYNOPSIS

    if ( Cpanel::Validate::Domain::ARPA::is_valid($specimen) ) {
        # ...
    }
    else {
        require Carp;
        croak "“$specimen” is not a valid domain.";
    }

=head1 DESCRIPTION

This module validates C<*.arpa> domains, which require specific
forms to be valid. Some things don’t care about validity—for example,
DNS resolvers will happily look up C<www.hahahah.arpa>—but others (e.g.,
a CA deciding whether to issue SSL) do.

=cut

#----------------------------------------------------------------------

my $RE_IPv4 = qr<
    \A
    (?:
        (?:
            [0-9]
            | [1-9][0-9]
            | 1[0-9][0-9]
            | 2[0-4][0-9]
            | 25[0-5]
        )
        \.
    ){4}
    in-addr
    \.arpa
    \z
>x;

my $RE_IPv6 = qr<
    \A
    (?: [0-9a-f] \. ){32}
    ip6
    \.arpa
    \z
>x;

#----------------------------------------------------------------------

=head1 FUNCTIONS

=head2 $yn = is_valid( $SPECIMEN )

Returns a boolean that indicates whether $SPECIMEN is a valid C<*.arpa> domain.

=cut

sub is_valid ($specimen) {
    return 1 if $specimen =~ $RE_IPv4;
    return 1 if $specimen =~ $RE_IPv6;
    return 0;
}

1;
