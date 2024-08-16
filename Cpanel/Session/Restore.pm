package Cpanel::Session::Restore;

# cpanel - Cpanel/Session/Restore.pm               Copyright 2022 cPanel, L.L.C.
#                                                           All rights reserved.
# copyright@cpanel.net                                         http://cpanel.net
# This code is subject to the cPanel license. Unauthorized copying is prohibited

use strict;
use warnings;

use Cpanel::Config::Session ();
use Cpanel::Session::Load   ();

=encoding utf-8

=head1 NAME

Cpanel::Session::Restore - Find a session based on $ENV USER and cp_security_token

=head2 restoreSession()

Find a session based on $ENV USER and cp_security_token

Returns the session name and session details from
Cpanel::Session::Load::loadSession if a matching
session is found

=cut

sub restoreSession {

    if ( opendir( my $session_dh, $Cpanel::Config::Session::SESSION_DIR . '/raw' ) ) {

        my $user_string = "$ENV{'REMOTE_USER'}:";

        # Also grepping for empty username is intentional -- this is needed to support HTTP auth sessions
        # where the session filename is already chosen before the username is actually known.
        my @sessions_to_check = grep { index( $_, $user_string ) == 0 && !m{\.lock$} } readdir($session_dh);
        foreach my $session (@sessions_to_check) {
            if ( my $sessionRef = Cpanel::Session::Load::loadSession($session) ) {
                if (
                       $sessionRef->{'cp_security_token'}
                    && $sessionRef->{'cp_security_token'} eq $ENV{'cp_security_token'}

                    # In case this is an HTTP auth session and two users share a security token.
                    # (This actually happens when reseller override is used.)
                    && $sessionRef->{'user'} eq $ENV{'REMOTE_USER'}
                ) {
                    return $session, $sessionRef;
                }
            }
        }
    }

    return undef;
}

1;
