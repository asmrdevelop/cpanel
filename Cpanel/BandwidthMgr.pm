package Cpanel::BandwidthMgr;

# cpanel - Cpanel/BandwidthMgr.pm                  Copyright 2022 cPanel, L.L.C.
#                                                           All rights reserved.
# copyright@cpanel.net                                         http://cpanel.net
# This code is subject to the cPanel license. Unauthorized copying is prohibited

use strict;
use warnings;
use Cpanel::FileUtils::TouchFile ();
use Cpanel::Config::LoadCpConf   ();
use Cpanel::LoadModule           ();
use Cpanel::ConfigFiles          ();

our $VERSION    = 1.1;
our @BWWARNLVLS = ( 99, 98, 97, 95, 90, 85, 80, 75, 70, 50 );

our $_has_at_least_one_bandwidth_notification_enabled_globally;    # Not intended to be modified externally, for testing only

sub disablebwlimit {    ## no critic qw(ProhibitManyArgs)
    my ( $user, $domain, $bwlimit, $totalthismonth, $notify, $ralldomains ) = @_;
    if ( -f "$Cpanel::ConfigFiles::BANDWIDTH_LIMIT_DIR/$user" ) {
        unlink("$Cpanel::ConfigFiles::BANDWIDTH_LIMIT_DIR/$user");
    }
    foreach my $ddomain ( $domain, @{$ralldomains} ) {
        if ( -f "$Cpanel::ConfigFiles::BANDWIDTH_LIMIT_DIR/$ddomain" ) {
            unlink("$Cpanel::ConfigFiles::BANDWIDTH_LIMIT_DIR/$ddomain");
        }
        if ( -f "$Cpanel::ConfigFiles::BANDWIDTH_LIMIT_DIR/www.$ddomain" ) {
            unlink("$Cpanel::ConfigFiles::BANDWIDTH_LIMIT_DIR/www.$ddomain");
        }
    }
    return;
}

sub enablebwlimit {    ## no critic qw(ProhibitManyArgs)
    my ( $user, $domain, $bwlimit, $totalthismonth, $notify, $ralldomains ) = @_;
    if ( $totalthismonth <= 0 ) { $totalthismonth = 1; }
    if ( $notify && !-e "$Cpanel::ConfigFiles::BANDWIDTH_LIMIT_DIR/$user" ) {
        Cpanel::LoadModule::load_perl_module('Cpanel::SafeRun::BG');
        Cpanel::SafeRun::BG::nooutputsystembg(
            '/usr/local/cpanel/bin/bwlimit_notify',
            $user, $domain, 0, int( ( $bwlimit / $totalthismonth ) * 100 ),
            sprintf( "%.2f", $bwlimit / ( 1024 * 1024 ) ), sprintf( "%.2f", $totalthismonth / ( 1024 * 1024 ) )
        );
    }
    Cpanel::FileUtils::TouchFile::touchfile("$Cpanel::ConfigFiles::BANDWIDTH_LIMIT_DIR/$user");
    foreach my $ddomain ( $domain, @{$ralldomains} ) {
        Cpanel::FileUtils::TouchFile::touchfile("$Cpanel::ConfigFiles::BANDWIDTH_LIMIT_DIR/$ddomain");
        Cpanel::FileUtils::TouchFile::touchfile("$Cpanel::ConfigFiles::BANDWIDTH_LIMIT_DIR/www.$ddomain");
    }
    return;
}

sub has_at_least_one_bandwidth_limit_notification_enabled {
    return $_has_at_least_one_bandwidth_notification_enabled_globally if defined $_has_at_least_one_bandwidth_notification_enabled_globally;

    my $cpconf_ref = Cpanel::Config::LoadCpConf::loadcpconf_not_copy();    # We call this over and over so lets not copy it over and over

    if ( $cpconf_ref->{'skipbwlimitcheck'} || !$cpconf_ref->{'emailusersbandwidthexceed'} ) {
        return ( $_has_at_least_one_bandwidth_notification_enabled_globally = 0 );
    }

    foreach my $bwwarn (@BWWARNLVLS) {
        if ( $cpconf_ref->{ 'emailusersbandwidthexceed' . $bwwarn } ) {
            return ( $_has_at_least_one_bandwidth_notification_enabled_globally = 1 );
        }
    }

    return ( $_has_at_least_one_bandwidth_notification_enabled_globally = 0 );

}

sub user_or_domain_is_bwlimited {
    my ($user_or_domain) = @_;
    return -e "$Cpanel::ConfigFiles::BANDWIDTH_LIMIT_DIR/$user_or_domain";
}

1;
