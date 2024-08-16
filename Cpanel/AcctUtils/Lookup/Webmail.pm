package Cpanel::AcctUtils::Lookup::Webmail;

# cpanel - Cpanel/AcctUtils/Lookup/Webmail.pm      Copyright 2022 cPanel, L.L.C.
#                                                           All rights reserved.
# copyright@cpanel.net                                         http://cpanel.net
# This code is subject to the cPanel license. Unauthorized copying is prohibited

=head1 NAME

Cpanel::AcctUtils::Lookup::Webmail

=cut

use strict;
use warnings;

=head2 is_webmail_user($username)

Returns 1 or 0 if the username fits the character constraints to be a virtual account name
in un-normalized form. This form is only acceptable for authentication and must be passed
through normalize_webmail_user() to be converted to canonical form.

The local part and domain may be seperated by +, %, :, or @

=cut

sub is_webmail_user {
    return (
        (
            defined $_[0]                                         # must have some value
              && length( $_[0] ) > 4                              # must be at least 5 characters long (1 localpart, 3 domain, 1 domain separator)
              && 1 == $_[0]             =~ tr{+%:@}{}             # must have 1 domain separator character
              && 1 == $_[0]             =~ tr{a-zA-Z0-9._-}{}c    # the domain separator is the only character present that is not allowed in a localpart or domain
              && substr( $_[0], 0, 1 )  !~ tr{+%:@.}{}            # first character could be a localpart ( no domain separator or . )
              && substr( $_[0], -3, 2 ) !~ tr{+%:@_}{}            # first two of the last three characters could be a domain
              && substr( $_[0], -1, 1 ) !~ tr{+%:@._-}{}          # last character could be a tld
        ) ? 1 : 0
    );
}

=head2 is_strict_webmail_user($username)

Returns 1 or 0 if the username fits the character constraints to be a virtual account name
in the normalized form cPanel & WHM uses for credential storage.

The local part and domain must be seperated by @

The username must be lowercase.

=cut

sub is_strict_webmail_user {
    return (
        (
            defined $_[0]                                      # must have some value
              && length( $_[0] ) > 4                           # must be at least 5 characters long (1 localpart, 3 domain, 1 domain separator)
              && 1 == $_[0]             =~ tr{@}{}             # must contain 1 domain separator character
              && 1 == $_[0]             =~ tr{a-z0-9._-}{}c    # the domain separator is the only character that is not allowed in a localpart or domain
              && substr( $_[0], 0, 1 )  !~ tr{@.}{}            # first character could be a localpart ( no domain separator or . )
              && substr( $_[0], -3, 2 ) !~ tr{@_}{}            # first two of the last three characters could be a domain
              && substr( $_[0], -1, 1 ) !~ tr{@._-}{}          # last character could be a tld
        ) ? 1 : 0
    );
}

=head2 normalize_webmail_user($username)

Converts an authable webmail username into the canonical format.

Returns the full username in scalar context or the localpart and domain in list context.

=cut

sub normalize_webmail_user {
    my ($user) = @_;

    $user =~ tr/A-Z+%:/a-z@/;

    return ( wantarray() ? split( '@', $user, 2 ) : $user );
}

1;
