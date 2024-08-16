package Whostmgr::API::1::CpUpdate;

# cpanel - Whostmgr/API/1/CpUpdate.pm              Copyright 2022 cPanel, L.L.C.
#                                                           All rights reserved.
# copyright@cpanel.net                                         http://cpanel.net
# This code is subject to the cPanel license. Unauthorized copying is prohibited

use strict;
use warnings;

use Cpanel::Update::Config ();
use Whostmgr::ACLS         ();
use Cpanel::Locale         ();

use constant NEEDS_ROLE => {
    update_updateconf => undef,
};

my $locale;

sub update_updateconf {
    my ( $args, $metadata ) = @_;

    $locale ||= Cpanel::Locale->get_handle();

    # check acls
    if ( !Whostmgr::ACLS::hasroot() ) {
        $metadata->{'result'} = 0;
        $metadata->{'reason'} = $locale->maketext("You do not have permission to edit update configuration.");
        return;
    }

    my $conf       = {};
    my $valid_keys = Cpanel::Update::Config::valid_keys();
    foreach my $key (@$valid_keys) {
        $conf->{$key} = $args->{$key} if exists $args->{$key};
    }

    if ( !scalar keys %$conf ) {
        $metadata->{'result'} = 0;
        $metadata->{'reason'} = $locale->maketext("No key to update.");
        return;
    }

    # always append values to the existing one
    #  we do not support the removal of some
    my $current = Cpanel::Update::Config::load();

    # append new values to current ones
    $conf = { %$current, %$conf };

    if ( Cpanel::Update::Config::save($conf) ) {
        $metadata->{'result'} = 1;
        $metadata->{'reason'} = 'OK';
    }
    else {
        $metadata->{'result'} = 0;
        $metadata->{'reason'} = $locale->maketext( 'The system was unable to update the configuration file: [_1]', 'cpupdate.conf' );
    }

    return;
}

1;
