package Cpanel::API::Resellers;

# cpanel - Cpanel/API/Resellers.pm                 Copyright 2022 cPanel, L.L.C.
#                                                           All rights reserved.
# copyright@cpanel.net                                         http://cpanel.net
# This code is subject to the cPanel license. Unauthorized copying is prohibited

use strict;
## no critic qw(TestingAndDebugging::RequireUseWarnings) -- not fully vetted for warnings

use Cpanel::AdminBin                 ();
use Cpanel::Reseller::Override       ();
use Cpanel::ResellerFunctions::Privs ();

sub list_accounts {
    ## no args
    my ( $args, $result ) = @_;
    if ( exists $Cpanel::CONF{'account_login_access'} && $Cpanel::CONF{'account_login_access'} eq 'user' ) {
        $result->data( [ { user => $Cpanel::user, domain => $Cpanel::CPDATA{'DNS'}, select => 1 } ] );
        return 1;
    }

    # TODO : Need better tests to separate out root and reseller here.
    my $reseller = ( Cpanel::Reseller::Override::is_overriding() ? Cpanel::Reseller::Override::is_overriding_from() : $Cpanel::user );    #TEMP_SESSION_SAFE
    if ( $reseller ne $Cpanel::user && !Cpanel::ResellerFunctions::Privs::hasresellerpriv( $Cpanel::user, 'all' ) ) {
        $Cpanel::AdminBin::safecaching = 1;
    }

    my $users_ref = Cpanel::AdminBin::adminfetch( 'reseller', [ '/etc/trueuserdomains', '/var/cpanel/resellers' ], 'SORTEDRESELLERSUSERS', 'storable', $reseller );
    $Cpanel::AdminBin::safecaching = 0;
    return 1 if ref $users_ref ne 'ARRAY';

    $result->data( [ map { { user => $_->[0], domain => $_->[1], select => $_->[0] eq $Cpanel::user }, } @$users_ref ] );
    return 1;
}

our %API = (
    list_accounts => { allow_demo => 1 },
);

1;
