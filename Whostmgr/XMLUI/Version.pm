package Whostmgr::XMLUI::Version;

# cpanel - Whostmgr/XMLUI/Version.pm               Copyright 2022 cPanel, L.L.C.
#                                                           All rights reserved.
# copyright@cpanel.net                                         http://cpanel.net
# This code is subject to the cPanel license. Unauthorized copying is prohibited

use strict;
use warnings;

use Cpanel::LoadModule    ();
use Cpanel::Version::Full ();
use Whostmgr::ApiHandler  ();

sub show {
    return Whostmgr::ApiHandler::out( { 'version' => scalar Cpanel::Version::Full::getversion() }, RootName => 'version', NoAttr => 1 );
}

sub set_tier {
    my %OPTS = @_;

    Cpanel::LoadModule::load_perl_module('Cpanel::Update');

    $OPTS{'tier'} = '' if ( !defined $OPTS{'tier'} );
    my $new_tier = Cpanel::Update::set_tier( $OPTS{'tier'} ) || '';

    if ( $new_tier ne $OPTS{'tier'} ) {
        return Whostmgr::ApiHandler::out(
            {
                'status'    => 0,
                'statusmsg' => 'Error: "' . $OPTS{'tier'} . '" is an invalid tier. Tier is set to ' . $new_tier,
            },
            RootName => 'set_tier',
            NoAttr   => 1
        );
    }

    return Whostmgr::ApiHandler::out(
        {
            'tier'      => $new_tier,
            'status'    => 1,
            'statusmsg' => 'Update tier successfully changed to ' . $new_tier,
        },
        RootName => 'set_tier',
        NoAttr   => 1
    );

}

sub set_cpanel_updates {
    my %OPTS = @_;

    Cpanel::LoadModule::load_perl_module('Cpanel::Update');
    my $updates     = $OPTS{'updates'} || '';
    my $update_type = Cpanel::Update::set_update_type($updates);

    if ( $update_type ne $updates ) {
        return Whostmgr::ApiHandler::out(
            {
                'status'    => 0,
                'statusmsg' => 'Error: ' . $updates . ' is an unsupported update frequency (daily/manual/never). Frequency is now ' . $update_type,
            },
            RootName => 'set_cpanel_updates',
            NoAttr   => 1
        );
    }

    return Whostmgr::ApiHandler::out(
        {
            'updates'   => $update_type,
            'status'    => 1,
            'statusmsg' => 'Cpanel update frequency set to ' . $update_type,
        },
        RootName => 'set_cpanel_updates',
        NoAttr   => 1
    );
}

sub get_available_tiers {

    require Cpanel::Update::Tiers;
    my $tiers = eval { Cpanel::Update::Tiers->new->get_flattened_hash };
    if ($@) {
        return Whostmgr::ApiHandler::out(
            {
                'status'    => 0,
                'statusmsg' => 'Error: could not determine available tiers for upgrade: ' . $@,
            },
            RootName => 'get_available_tiers',
            NoAttr   => 1
        );
    }

    return Whostmgr::ApiHandler::out(
        {
            'tiers'     => $tiers,
            'status'    => 1,
            'statusmsg' => 'Got tiers list',
        },
        RootName => 'get_available_tiers',
        NoAttr   => 1
    );

}

1;
