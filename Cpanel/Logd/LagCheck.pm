package Cpanel::Logd::LagCheck;

# cpanel - Cpanel/Logd/LagCheck.pm                 Copyright 2022 cPanel, L.L.C.
#                                                           All rights reserved.
# copyright@cpanel.net                                         http://cpanel.net
# This code is subject to the cPanel license. Unauthorized copying is prohibited

use strict;

use Cpanel::Config::LoadCpConf      ();
use Cpanel::PwCache::PwEnt          ();
use Cpanel::Config::LoadUserDomains ();
use Cpanel::Context                 ();

#exposed for testing
our $_LASTRUN_DIR = '/var/cpanel/lastrun';

#exposed for testing
sub _get_user_lookup {
    return scalar Cpanel::Config::LoadUserDomains::loadtrueuserdomains( {}, 1 );
}

sub _get_cycle_seconds {
    return 60 * 60 * Cpanel::Config::LoadCpConf::loadcpconf()->{'cycle_hours'};
}

sub _get_time { return time }

#Returns a list of: (
#   username    =>  lag time (seconds),
#   username2   =>  lag time 2,
#   ...
#)
sub get_lagging_stats_users_and_lag_times {
    Cpanel::Context::must_be_list();

    my %LAGGED;
    my $now            = _get_time();
    my $cycleseconds   = _get_cycle_seconds();
    my $user_lookup_hr = _get_user_lookup();

    local $!;

    Cpanel::PwCache::PwEnt::setpwent() or do {
        die "I/O error while resetting PW datastore: $!" if $!;
    };

    my $two_cycles = 2 * $cycleseconds;

    while ( my $user = Cpanel::PwCache::PwEnt::getpwent() ) {
        next if !exists $user_lookup_hr->{$user};
        next if !-e "$_LASTRUN_DIR/$user/stats";

        my $lastruntime_plus_2_cycles = $two_cycles + ( stat _ )[9];

        if ( $lastruntime_plus_2_cycles < $now ) {
            $LAGGED{$user} = ( $now - $lastruntime_plus_2_cycles );
        }
    }

    if ($!) {
        die "I/O error while reading PW datastore: $!" if $!;
    }

    Cpanel::PwCache::PwEnt::endpwent() or do {
        die "I/O error while closing PW datastore: $!" if $!;
    };

    return %LAGGED;
}

1;
