package Cpanel::FtpUtils::PureFTPd;

# cpanel - Cpanel/FtpUtils/PureFTPd.pm             Copyright 2022 cPanel, L.L.C.
#                                                           All rights reserved.
# copyright@cpanel.net                                         http://cpanel.net
# This code is subject to the cPanel license. Unauthorized copying is prohibited

use strict;
use warnings;

use Cpanel::Config::LoadUserDomains ();
use Cpanel::PwCache::Build          ();
use Cpanel::PwCache                 ();
use Cpanel::FileUtils::Link         ();
use Cpanel::PwCache                 ();
use Cpanel::DIp::Owner              ();
use Cpanel::IP::Configured          ();

our $PURE_FTPD_ROOTS_DIR = '/etc/pure-ftpd';

sub build_pureftpd_roots {

    my %HOMES                 = map { $_->[0] => $_->[7] } @{ Cpanel::PwCache::Build::fetch_pwcache() };
    my $ftphome               = ( Cpanel::PwCache::getpwnam('ftp') )[7] || '/var/ftp';
    my $userdomains_ref       = Cpanel::Config::LoadUserDomains::loaduserdomains( undef, 1 );
    my $dedicated_ips_domains = Cpanel::DIp::Owner::get_all_dedicated_ips();
    my $all_ips               = Cpanel::IP::Configured::getconfiguredips();

    foreach my $ip ( @{$all_ips} ) {
        my $link_target;
        if ( my $domain = $dedicated_ips_domains->{$ip} ) {
            my $user = $userdomains_ref->{$domain};
            next if !$user;
            my $homedir = $HOMES{$user};
            $link_target = "$homedir/public_ftp";
        }
        else {
            $link_target = $ftphome;
        }
        Cpanel::FileUtils::Link::forced_symlink( $link_target, "$PURE_FTPD_ROOTS_DIR/$ip" );
    }

    return ( 1, "Built $PURE_FTPD_ROOTS_DIR" );
}

1;
