#!/usr/local/cpanel/3rdparty/bin/perl

# cpanel - Cpanel/Admin/Modules/Cpanel/bandwidth_call.pm
#                                                  Copyright 2022 cPanel, L.L.C.
#                                                           All rights reserved.
# copyright@cpanel.net                                         http://cpanel.net
# This code is subject to the cPanel license. Unauthorized copying is prohibited

package Cpanel::Admin::Modules::Cpanel::bandwidth_call;

use strict;
use warnings;

use parent qw( Cpanel::Admin::Base );

sub _actions {
    return (
        'CREATE_DATABASE',
        'UPDATE_USER_CACHE',
    );
}

sub _demo_actions {
    return ('UPDATE_USER_CACHE');
}

sub CREATE_DATABASE {
    my ($self) = @_;

    require Cpanel::BandwidthDB;

    #This does a migration.
    Cpanel::BandwidthDB::get_reader_for_root( $self->get_caller_username() );

    return 1;
}

sub UPDATE_USER_CACHE {
    my ($self) = @_;

    require Cpanel::Time;
    my ( $mo, $yr ) = ( Cpanel::Time::localtime() )[ 4, 5 ];

    $mo = sprintf( '%02d', $mo );

    require Cpanel::BandwidthDB;
    my $bwrd = Cpanel::BandwidthDB::get_reader_for_root( $self->get_caller_username() );

    my $bwtotal_ar = $bwrd->get_bytes_totals_as_array(
        grouping => [],
        start    => "$yr-$mo",
        end      => "$yr-$mo",
    );

    require Cpanel::BandwidthDB::UserCache;
    Cpanel::BandwidthDB::UserCache::write(
        $self->get_caller_username(),
        $bwtotal_ar->[0][0] || 0,
    );

    return 1;
}

1;
