package Cpanel::UserTasks::ClamScanner;

# cpanel - Cpanel/UserTasks/ClamScanner.pm         Copyright 2022 cPanel, L.L.C.
#                                                           All rights reserved.
# copyright@cpanel.net                                         http://cpanel.net
# This code is subject to the cPanel license. Unauthorized copying is prohibited

use strict;
use warnings;

=head1 FUNCTIONS

=head2 Cpanel::UserTasks::ClamScanner::disinfect()

Start the requested disinfection.

=cut

sub disinfect {
    my ( $class, $args ) = @_;

    require Cpanel::JSON;
    my $actions = Cpanel::JSON::Load( $args->{'actions'} );

    require Cpanel::ClamScanner;
    return Cpanel::ClamScanner::disinfect(%$actions);
}

1;
