package Cpanel::Update;

# cpanel - Cpanel/Update.pm                        Copyright 2022 cPanel, L.L.C.
#                                                           All rights reserved.
# copyright@cpanel.net                                         http://cpanel.net
# This code is subject to the cPanel license. Unauthorized copying is prohibited

use strict;
use warnings;

use Cpanel::Logger           ();
use Cpanel::Config::Services ();
use Cpanel::Update::Config   ();

our $VERSION = '3.0';

sub init_UP_update {
    my ($update_name) = @_;

    my ( $status, $disabled_name ) = Cpanel::Config::Services::service_enabled($update_name);

    if ( !$status ) {
        print "Updates for \xE2\x80\x9C$update_name\xE2\x80\x9D are disabled because \xE2\x80\x9C$disabled_name\xE2\x80\x9D exists.\n";
        exit;
    }
    ( $status, $disabled_name ) = Cpanel::Config::Services::service_enabled( $update_name . 'up' );
    if ( !$status ) {
        print "Updates for \xE2\x80\x9C$update_name\xE2\x80\x9D are disabled because \xE2\x80\x9C$disabled_name\xE2\x80\x9D exists.\n";
        exit;
    }
}

sub set_tier {
    my $tier = shift || '';
    $tier =~ tr/A-Z/a-z/;
    my $rUPCONF  = Cpanel::Update::Config::load();
    my $old_tier = $rUPCONF->{'CPANEL'};

    # No change in tier.
    return $old_tier if ( !$tier || $old_tier eq $tier );

    # Determine if the tier exists in TIERS.json.
    require Cpanel::Update::Tiers;
    my $remote_tier_version = Cpanel::Update::Tiers->new( 'logger' => 'disabled' )->get_remote_version_for_tier($tier);
    return $old_tier if ( !$remote_tier_version );

    $rUPCONF->{'CPANEL'} = $tier;

    if ( Cpanel::Update::Config::save($rUPCONF) ) {

        # Save succeeded and could have altered the value
        return Cpanel::Update::Config::load()->{CPANEL};
    }
    else {

        # Save failed
        Cpanel::Logger->new()->warn( 'Unable to Cpanel::Update::Config::save() with ' . $tier );
        return $old_tier;
    }
}

sub set_update_type {
    my ($update_type) = @_;

    my $rUPCONF = Cpanel::Update::Config::load();
    $update_type || return $rUPCONF->{'UPDATES'};

    $update_type =~ tr/A-Z/a-z/;
    $update_type =~ m/^(daily|manual|never)$/ or return $rUPCONF->{'UPDATES'};

    # Set designated value
    $rUPCONF->{'UPDATES'} = $update_type;

    # Update config file
    Cpanel::Update::Config::save($rUPCONF);

    # Return what it was set to.
    return $rUPCONF->{'UPDATES'};
}

sub get_transfers_sync_tier {
    return -f '/var/cpanel/transfers_devel' ? 'DEVEL' : 'PUBLIC';
}

1;
