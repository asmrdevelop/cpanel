package Whostmgr::API::1::Update;

# cpanel - Whostmgr/API/1/Update.pm                Copyright 2022 cPanel, L.L.C.
#                                                           All rights reserved.
# copyright@cpanel.net                                         http://cpanel.net
# This code is subject to the cPanel license. Unauthorized copying is prohibited

use strict;
use warnings;

use Whostmgr::API::1::Utils ();
use Cpanel::Update::Tiers   ();

use constant NEEDS_ROLE => {
    get_current_lts_expiration_status => undef,
    get_lts_wexpire                   => undef,
    get_update_availability           => undef,
};

sub _tiers {
    return Cpanel::Update::Tiers->new;
}

sub get_update_availability {
    my ( $args, $metadata ) = @_;

    my $ret = _tiers->get_update_availability();
    Whostmgr::API::1::Utils::set_metadata_ok($metadata);
    return $ret;

}

sub get_lts_wexpire {
    my ( $args, $metadata ) = @_;

    my $tiers = _tiers->tiers_hash();

    if ( defined $tiers ) {
        @{$metadata}{qw(result reason)} = ( 1, 'OK' );
        return $tiers;
    }

    @{$metadata}{qw(result reason)} = ( 0, 'Failed to retrieve long term support information.' );
    return;
}

sub get_current_lts_expiration_status {
    my ( $args, $metadata ) = @_;

    my $result = _tiers->get_current_lts_expiration_status();

    if ( !defined $result ) {
        @{$metadata}{qw(result reason)} = ( 0, 'Not a long term support version, or failed to retrieve long term support information.' );
    }
    else {
        @{$metadata}{qw(result reason)} = ( 1, 'OK' );
    }

    return $result;
}

1;
