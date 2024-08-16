package Cpanel::API::PasswdStrength;

# cpanel - Cpanel/API/PasswdStrength.pm            Copyright 2022 cPanel, L.L.C.
#                                                           All rights reserved.
# copyright@cpanel.net                                         http://cpanel.net
# This code is subject to the cPanel license. Unauthorized copying is prohibited

use cPstrict;

use Cpanel::PasswdStrength::Check ();

our %API = (
    get_required_strength => { allow_demo => 1 },
);

sub get_required_strength ( $args, $result ) {
    my $app  = $args->get('app');
    my $data = Cpanel::PasswdStrength::Check::get_required_strength($app);

    return $result->data( { 'strength' => $data } );
}

1;
