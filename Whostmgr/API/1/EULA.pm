package Whostmgr::API::1::EULA;

# cpanel - Whostmgr/API/1/EULA.pm                  Copyright 2022 cPanel, L.L.C.
#                                                           All rights reserved.
# copyright@cpanel.net                                         http://cpanel.net
# This code is subject to the cPanel license. Unauthorized copying is prohibited

use cPstrict;

use constant NEEDS_ROLE => {
    accept_eula => undef,
};

=encoding utf-8

=head1 NAME

Whostmgr::API::1::EULA - WHM API functions to manage user license agreements.

=head1 SUBROUTINES

=over 4

=item accept_eula()

See OpenAPI doc.

=cut

sub accept_eula {
    my ( undef, $metadata ) = @_;

    require Whostmgr::Setup::EULA;
    Whostmgr::Setup::EULA::set_accepted();

    $metadata->{'result'} = 1;
    $metadata->{'reason'} = 'OK';

    return;
}

=back

=cut

1;
