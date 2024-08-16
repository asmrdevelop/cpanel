package Cpanel::Exception::AutoSSL::DeferFurtherWork;

# cpanel - Cpanel/Exception/AutoSSL/DeferFurtherWork.pm
#                                                  Copyright 2022 cPanel, L.L.C.
#                                                           All rights reserved.
# copyright@cpanel.net                                         http://cpanel.net
# This code is subject to the cPanel license. Unauthorized copying is prohibited

use strict;
use warnings;

=encoding utf-8

=head1 NAME

Cpanel::Exception::AutoSSL::DeferFurtherWork

=head1 DESCRIPTION

This exception is meant to be thrown from within an AutoSSL provider module.
It tells AutoSSL to exit (gracefully) without doing anything further, and
without running the provider’s C<ON_FINISH_CHECK()> method.

This is useful if, e.g., the Certificate Authority imposes rate limits,
à la Let’s Encrypt.

The provider module’s C<CHECK_FREQUENCY()> should
probably indicate more frequent checks than C<daily>. The idea is that,
by the time the next scheduled AutoSSL run happens, some additional activity
will be possible.


=cut

use parent qw( Cpanel::Exception );

1;
