package Cpanel::Exception::NotImplemented;

# cpanel - Cpanel/Exception/NotImplemented.pm      Copyright 2022 cPanel, L.L.C.
#                                                           All rights reserved.
# copyright@cpanel.net                                         http://cpanel.net
# This code is subject to the cPanel license. Unauthorized copying is prohibited

use strict;
use warnings;

use parent qw( Cpanel::Exception );

=head1 MODULE

C<Cpanel::Exception::NotImplemented>

=head1 DESCRIPTION

C<Cpanel::Exception::NotImplemented> provides a named exception class for features that have
been included in an interface, but do not yet have a specific implementation. These exceptions
should be used for features that are expected to be implemented at some point in the future,
but due to timing, release schedules, the way project work is segmented for development, have
not yet made it into the feature.

=cut

1;
