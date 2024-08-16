package Cpanel::Passwd::Check;

# cpanel - Cpanel/Passwd/Check.pm                  Copyright 2022 cPanel, L.L.C.
#                                                           All rights reserved.
# copyright@cpanel.net                                         http://cpanel.net
# This code is subject to the cPanel license. Unauthorized copying is prohibited

use cPstrict;

=encoding utf-8

=head1 NAME

Cpanel::Passwd::Check

=head1 SYNOPSIS

    if ( Cpanel::Passwd::Check::is_correct($password) ) {
        # … password is valid
    }
    else {
        die "Incorrect password given!";
    }

=head1 DESCRIPTION

This module exposes a simple password-check function that unprivileged
code can call on behalf of the current cPanel user.

=cut

#----------------------------------------------------------------------

use Cpanel::Wrap         ();
use Cpanel::Wrap::Config ();

#----------------------------------------------------------------------

=head1 FUNCTIONS

=head2 $yn = is_correct( $PASSWORD )

Returns a boolean that indicates whether the given $PASSWORD is correct
for the current cPanel user.

An exception is thrown if we fail to determine whether $PASSWORD is correct.

=cut

sub is_correct ($password) {

    # sanity check to reject calls as root:
    die "non-root only!" if !$>;

    my $result = Cpanel::Wrap::send_cpwrapd_request_no_cperror(
        'namespace' => 'Cpanel',
        'module'    => 'security',
        'function'  => 'VALIDATE',
        'data'      => { 'current_password' => $password },
        'env'       => Cpanel::Wrap::Config::safe_hashref_of_allowed_env(),
    );

    my $err;

    if ( !$result->{'status'} || !ref $result->{'data'} ) {
        $err = $result->{'statusmsg'};
    }
    elsif ( !$result->{'data'}{'status'} ) {
        $err = $result->{'data'}{'statusmsg'};
    }
    else {
        return $result->{'data'}->{'current_password_valid'} || 0;
    }

    $err ||= 'Unknown error';

    die "Failed to validate password: $err\n";
}

1;
