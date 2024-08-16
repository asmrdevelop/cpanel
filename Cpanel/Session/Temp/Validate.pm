package Cpanel::Session::Temp::Validate;

# cpanel - Cpanel/Session/Temp/Validate.pm         Copyright 2022 cPanel, L.L.C.
#                                                           All rights reserved.
# copyright@cpanel.net                                         http://cpanel.net
# This code is subject to the cPanel license. Unauthorized copying is prohibited

use strict;

sub is_valid_session_user_token {
    my ($token) = @_;

    return ( $token =~ m/^[\@\.A-Za-z0-9_-]+$/ ) ? 1 : 0;
}
1;
