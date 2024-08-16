package Cpanel::API::LastLogin;

# cpanel - Cpanel/API/LastLogin.pm                 Copyright 2022 cPanel, L.L.C.
#                                                           All rights reserved.
# copyright@cpanel.net                                         http://cpanel.net
# This code is subject to the cPanel license. Unauthorized copying is prohibited

use strict;
## no critic qw(TestingAndDebugging::RequireUseWarnings) -- not fully vetted for warnings

use Cpanel::LastLogin::Tiny ();

=head1 NAME

Cpanel::API::LastLogin

=head1 DESCRIPTION

UAPI functions related to login history

=cut

=head2 get_last_or_current_logged_in_ip()

=head3 Purpose

Returns the last with the authenticated ip or the current ip
if there is no previous authenticated ip

AKA

get_previous_login_ip_unless_there_is_not_one_then_return_current_ip_as_to_not_break_securitypolicy

=head3 Arguments

    None

=head3 Output

    The last authenticated IP address or the current IP
    address if there was no previous IP.

    get_last_or_current_logged_in_ip will be an empty
    string if get_last_or_current_logged_in_ip fails for
    any reason or there is no previous IP address or
    current IP address found in the enviorment.

=cut

sub get_last_or_current_logged_in_ip {
    my ( $args, $result ) = @_;

    $result->data( Cpanel::LastLogin::Tiny::lastlogin() );

    return 1;
}

our %API = (
    get_last_or_current_logged_in_ip => { allow_demo => 1 },
);

1;
