package Cpanel::Exception::AuthenticationFailed;

# cpanel - Cpanel/Exception/AuthenticationFailed.pm
#                                                  Copyright 2022 cPanel, L.L.C.
#                                                           All rights reserved.
# copyright@cpanel.net                                         http://cpanel.net
# This code is subject to the cPanel license. Unauthorized copying is prohibited

use cPstrict;

=encoding utf-8

=head1 NAME

Cpanel::Exception::AuthenticationFailed

=head1 DISCUSSION

B<NOTE:> If you want to express “wrong password” or the like:

=over

=item * B<Don’t>, if the caller is unauthenticated.

=item * This isn’t what you want. This class represents an I<internal>
authentication failure. It is I<NOT> for rejection of user input.

For that, use L<Cpanel::Exception::WrongAuthentication> instead.

=back

=cut

#----------------------------------------------------------------------

use parent qw( Cpanel::Exception );

1;
