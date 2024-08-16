package Cpanel::License::Cloud;

# cpanel - Cpanel/License/Cloud.pm                 Copyright 2022 cPanel, L.L.C.
#                                                           All rights reserved.
# copyright@cpanel.net                                         http://cpanel.net
# This code is subject to the cPanel license. Unauthorized copying is prohibited

use cPstrict;

=encoding utf-8

=head1 NAME

Cpanel::License::Cloud

=head1 SYNOPSIS

    if (Cpanel::License::Cloud::is_on()) {
        # ...
    }

=head1 DESCRIPTION

This module implements logic that cPanel & WHM can use to determine
if it’s running a cPanel Cloud license.

=head1 STATUS

Right now this is just a stub; its implementation and interface are
almost certain to change as cP-HA’s licensing model takes shape. It might
end up renamed, rolled into some other interface, etc.

=cut

#----------------------------------------------------------------------

=head1 FUNCTIONS

=head2 $yn = is_on()

Returns a boolean that indicates whether the local cPanel & WHM
installation is licensed for cPanel Cloud.

(NB: By design, this doesn’t query for the system’s
I<setup> state. It only cares about how the server is licensed.)

=cut

sub is_on () {

    # XXX: A provisional implementation, NOT for production (as it would
    # allow customers to self-upgrade their license to cP Cloud).
    #
    require Cpanel::Autodie;
    return Cpanel::Autodie::exists('/var/cpanel/cloud_testing');
}

1;
