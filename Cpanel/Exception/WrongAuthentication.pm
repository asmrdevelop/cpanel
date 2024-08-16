package Cpanel::Exception::WrongAuthentication;

# cpanel - Cpanel/Exception/WrongAuthentication.pm Copyright 2022 cPanel, L.L.C.
#                                                           All rights reserved.
# copyright@cpanel.net                                         http://cpanel.net
# This code is subject to the cPanel license. Unauthorized copying is prohibited

use cPstrict;

=encoding utf-8

=head1 NAME

Cpanel::Exception::WrongAuthentication

=head1 SYNOPSIS

    die Cpanel::Exception::create('WrongAuthentication');   ## no extract maketext

=head1 READ THIS FIRST!

B<Don’t> use this if your caller is I<unauthenticated>. Unless
the caller has authenticated, all we want to say is “login failed”,
without indicating I<why> that failure happened. This prevents attackers
from learning details about the system, e.g., how many tries they have
before rate limiting kicks in, whether a username exists, etc.

So, for example, a user who changes their password but mistypes the
old password can receive this error. A user who’s just logging in
B<MUST> B<NOT> receive it.

=head1 DESCRIPTION

This class represents a rejection of inputs that happens because
those inputs are incorrect authentication values.

The most obvious use case is to indicate “wrong password”, but it could also
suit API tokens or other such cases.

B<NOTE:> This is B<NOT> the same as
L<Cpanel::Exception::AuthenticationFailed>, which indicates that the
I<authentication> itself experienced an internal failure, not that the
user’s submitted authentication data is incorrect.

This class extends L<Cpanel::Exception::InvalidParameter>. It neither
provides a default message nor recognizes any parameters.

=cut

#----------------------------------------------------------------------

use parent qw( Cpanel::Exception::InvalidParameter );

1;
