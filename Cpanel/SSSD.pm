package Cpanel::SSSD;

# cpanel - Cpanel/SSSD.pm                          Copyright 2022 cPanel, L.L.C.
#                                                           All rights reserved.
# copyright@cpanel.net                                         http://cpanel.net
# This code is subject to the cPanel license. Unauthorized copying is prohibited

use strict;
use warnings;

use Cpanel::CachedCommand   ();
use Cpanel::FindBin         ();
use Cpanel::SafeRun::Object ();

use Try::Tiny;

my $sssd_binary_missing = 0;
my $sssd_binary;

# XXX Apparently clearing the cache doesn't clear the cache.
# Restarting the service is also necessary. BIG oof
sub clear_cache {
    return unless ( -x '/bin/systemctl' );
    $sssd_binary = _get_sssd_binary_path() or return;

    my $sssd_status = Cpanel::CachedCommand::cachedcommand(qw{/bin/systemctl is-active sssd});
    chomp($sssd_status);
    return if $sssd_status ne 'active';

    my $err;
    try {
        require Cpanel::SafeRun::Object;
        Cpanel::SafeRun::Object->new_or_die(
            program => $sssd_binary,
            args    => ['-EUG'],
        );
    }
    catch {
        $err = $_;
        local $@ = $err;
        warn;
    };

    return 0 if $err;
    return 1;
}

sub _get_sssd_binary_path {
    if ( !$sssd_binary ) {
        return if $sssd_binary_missing;

        $sssd_binary = Cpanel::FindBin::findbin( 'sss_cache', 'path' => [ '/usr/sbin', '/usr/local/sbin', '/usr/bin', '/usr/local/bin' ] );
        if ( !$sssd_binary ) {
            $sssd_binary_missing = 1;
            return;
        }
    }
    return $sssd_binary;
}

1;
