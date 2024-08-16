package Cpanel::Hulk::Utils;

# cpanel - Cpanel/Hulk/Utils.pm                    Copyright 2022 cPanel, L.L.C.
#                                                           All rights reserved.
# copyright@cpanel.net                                         http://cpanel.net
# This code is subject to the cPanel license. Unauthorized copying is prohibited

use strict;
use warnings;

use Cpanel::Hulk::Constants ();

###########################################################################
#
# Method:
#   hash_authtoken
#
# Description:
#   Takes a authtoken (password) along with the logintime, username,
#   and IP Address in order to generate a hash that that changes
#   every (Cpanel::Hulk::Constants::TIME_BASE).  We use this hash
#   to compare login attempts to see if the user is trying different
#   passwords.
#
sub hash_authtoken {
    my ( $authtoken, $logintime, $user, $ip ) = @_;

    die "authtoken is required for hash_authtoken"                         if !length $authtoken;
    die "logintime is required for hash_authtoken"                         if !length $logintime;
    die "logintime must be newer than $Cpanel::Hulk::Constants::TIME_BASE" if $logintime < $Cpanel::Hulk::Constants::TIME_BASE;
    die "user is required for hash_authtoken"                              if !length $user;

    # ip is not required
    $ip ||= '(null)';    # to match pam_hulk.c

    # must match pam_hulk.c
    my $salt = substr(
        join(
            '',
            $Cpanel::Hulk::Constants::TOKEN_SALT_BASE,
            _get_scaled_tick_from_base($logintime),
            $user,
            $ip
        ),
        0,
        $Cpanel::Hulk::Constants::SALT_LENGTH
    );
    return Crypt::Passwd::XS::crypt( $authtoken, $salt ) if $INC{'Crypt/Passwd/XS.pm'};
    return crypt( $authtoken, $salt );
}

sub _get_scaled_tick_from_base {
    my ($logintime)                   = @_;
    my $seconds_past_six_hour_tick    = $logintime % $Cpanel::Hulk::Constants::SIX_HOURS_IN_SECONDS;
    my $last_six_hour_tick_from_epoch = $logintime - $seconds_past_six_hour_tick;
    my $last_tick_from_base           = $last_six_hour_tick_from_epoch - $Cpanel::Hulk::Constants::TIME_BASE;
    return $last_tick_from_base / 100;
}

###########################################################################
#
# Method:
#   token_is_hashed
#
# Description:
#   This function determines if a token is the hashed version
#   of the token.
#
sub token_is_hashed {
    my ($token_that_may_be_hashed) = @_;

    return $token_that_may_be_hashed =~ m{^\$[^\$]+\$[^\$]+\$} ? 1 : 0;
}

###########################################################################
#
# Method:
#   strip_salt_from_hashed_token
#
# Description:
#   This function removes the salt that was used to generate the
#   hash from the token for storage in the hulk database.
#

sub strip_salt_from_hashed_token {
    my ($salted_token) = @_;

    $salted_token =~ s/^\$[^\$]+\$[^\$]+\$//;

    return $salted_token;    # now salt free
}

1;
