package Cpanel::Security::Authn::Webmail::Password;

# cpanel - Cpanel/Security/Authn/Webmail/Password.pm
#                                                  Copyright 2022 cPanel, L.L.C.
#                                                           All rights reserved.
# copyright@cpanel.net                                         http://cpanel.net
# This code is subject to the cPanel license. Unauthorized copying is prohibited

use cPstrict;

=encoding utf-8

=head1 NAME

Cpanel::Security::Authn::Webmail::Password - Password logic for Webmail accounts

=head1 SYNOPSIS

    my $pw_string = "$username:$encrypted_pw:$what:$ever:$else";

    # A scalar reference to the result of substr() alters the original string.
    # Weird? Useful? TIMTOWTDI!
    my $after_username_r = \substr( $pw_string, 0, 1 + length $username );

    if ( set_suspended($after_username_r) ) {
        # $pw_string now reflects the suspension
    }
    else {
        # $pw_string already showed the suspension
    }

    unset_suspended($after_username_r);

=head1 DESCRIPTION

This module contains logic for Webmail user account suspension,
as indicated via the account’s encrypted password.

=head1 FUNCTIONS

=head2 $yn = is_suspended( \$ENCRYPTED_PASSWORD )

Returns a boolean that indicates whether $ENCRYPTED_PASSWORD indicates
Webmail account suspension.

=cut

sub is_suspended ($pw_r) {
    return 0 == rindex( $$pw_r, '!', 0 );
}

=head2 $yn = set_suspended( \$ENCRYPTED_PASSWORD )

Alters $ENCRYPTED_PASSWORD, if necessary, to indicate Webmail account
suspension. Returns truthy if a change was made or falsy if not.

=cut

sub set_suspended ($pw_r) {
    return 0 if is_suspended($pw_r);

    substr( $$pw_r, 0, 0, '!!' );
    return 1;
}

=head2 $yn = unset_suspended( \$ENCRYPTED_PASSWORD )

The complement to C<set_suspended()>.

=cut

sub unset_suspended ($pw_r) {
    return 0 if !is_suspended($pw_r);

    substr( $$pw_r, 0, 1, q<> );

    # We’ve been inconsistent historically with whether we suspend
    # with “!!” or just “!”. Account for both:
    substr( $$pw_r, 0, 1, q<> ) if is_suspended($pw_r);

    return 1;
}

1;
