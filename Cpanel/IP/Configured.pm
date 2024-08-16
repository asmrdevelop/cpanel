package Cpanel::IP::Configured;

# cpanel - Cpanel/IP/Configured.pm                 Copyright 2022 cPanel, L.L.C.
#                                                           All rights reserved.
# copyright@cpanel.net                                         http://cpanel.net
# This code is subject to the cPanel license. Unauthorized copying is prohibited

use strict;
use warnings;

use Cpanel::Exception                    ();
use Cpanel::CachedCommand::Utils         ();
use Cpanel::FileUtils::TouchFile         ();
use Cpanel::JSON::FailOK                 ();
use Cpanel::FileUtils::Write::JSON::Lazy ();
use Cpanel::PwCache                      ();
use Try::Tiny;

our $VERSION = '1.7';

my $PRODUCT_CONF_DIR = '/var/cpanel';
my $SYSTEM_CONF_DIR  = '/etc';
my $SYSTEM_SBIN_DIR  = '/sbin';
my $DB_FILE          = 'all_iplist.db';

my $configuredips;

sub clear_configured_ips_cache {
    Cpanel::FileUtils::TouchFile::touchfile("$SYSTEM_CONF_DIR/ips");    # Reset mtime
    Cpanel::CachedCommand::Utils::destroy( 'name' => $DB_FILE );
    $configuredips = undef;
    return 1;
}

sub getconfiguredips {
    if ($configuredips) {
        return wantarray ? @$configuredips : $configuredips;
    }

    my $iplist_cachefile = Cpanel::CachedCommand::Utils::get_datastore_filename($DB_FILE);
    my $now              = time();
    my $iplist_cache_age = $now - ( ( stat $iplist_cachefile )[9] || 0 );

    my $use_cache = 1;
    if ( $iplist_cache_age < 0 || $iplist_cache_age > 300 ) {
        $use_cache = 0;
    }
    else {
        my $ips_age         = $now - ( ( stat "$SYSTEM_CONF_DIR/ips" )[9]          || 0 );
        my $wwwacctconf_age = $now - ( ( stat "$SYSTEM_CONF_DIR/wwwacct.conf" )[9] || 0 );

        # If the user has been fiddling with IP addresses recently, we need fresh data
        if ( $iplist_cache_age > $ips_age || $iplist_cache_age > $wwwacctconf_age ) {
            $use_cache = 0;
        }
    }

    if ($use_cache) {
        $configuredips = Cpanel::JSON::FailOK::LoadFile($iplist_cachefile);
    }

    if ( !$configuredips || !@$configuredips ) {
        require Cpanel::Linux::RtNetlink;
        require Cpanel::IP::Loopback;
        my $ips = Cpanel::Linux::RtNetlink::get_interface_addresses('AF_INET');
        @$configuredips = map { $_->{'ip'} } grep { !Cpanel::IP::Loopback::is_loopback( $_->{'ip'} ) } @$ips;

        # We cannot write to the cache if we are running as "nobody"
        # That account does not have a homedirectory (under which the cache would reside)
        if ( Cpanel::PwCache::getusername() ne 'nobody' ) {
            try {
                Cpanel::FileUtils::Write::JSON::Lazy::write_file( $iplist_cachefile, $configuredips, 0644 );
            }
            catch {
                # Logger it but do not throw into the UI
                # If the above returns true we know its a Cpanel::Exception
                _logger()->warn( Cpanel::Exception::get_string($_) );
            };

        }
    }

    $configuredips = [] unless ( defined $configuredips );

    return wantarray ? @$configuredips : $configuredips;
}

sub clearcache {
    $configuredips = undef;
    return 1;
}

# Data mocking routine
sub default_product_dir {
    $PRODUCT_CONF_DIR = shift if @_;
    return $PRODUCT_CONF_DIR;
}

sub default_conf_dir {
    $SYSTEM_CONF_DIR = shift if @_;
    return $SYSTEM_CONF_DIR;
}

sub default_sbin_dir {
    $SYSTEM_SBIN_DIR = shift if @_;
    return $SYSTEM_SBIN_DIR;
}

my $logger;

sub _logger {
    return $logger if $logger;
    require Cpanel::Logger;
    return ( $logger = Cpanel::Logger->new() );
}

1;
