package Whostmgr::Limits::Resellers;

# cpanel - Whostmgr/Limits/Resellers.pm            Copyright 2022 cPanel, L.L.C.
#                                                           All rights reserved.
# copyright@cpanel.net                                         http://cpanel.net
# This code is subject to the cPanel license. Unauthorized copying is prohibited

use strict;

use Whostmgr::Limits::Config ();
use Cpanel::CachedDataStore  ();

sub load_all_reseller_limits {
    my $lock = shift;

    # Usage is safe as we own /var/cpanel and the dir

    my $data_opts = load_reseller_datastore($lock);
    return ($lock) ? $data_opts : $data_opts->{'data'};
}

sub saveresellerlimits {
    my $opts = shift;

    # Usage is safe as we own /var/cpanel and the dir
    return Cpanel::CachedDataStore::savedatastore( $Whostmgr::Limits::Config::RESELLER_LIMITS_FILE, $opts );
}

## RESTRUCTURE THIS MODULE: there are too many similarly named, similarly functioning modules. There
##   were too many hard-coded calls to loaddatastore, and not all of them had the catch case of
##   empty hash. Make this module like its sister ::PackageLimits.
sub load_reseller_datastore {
    my ($lock) = @_;

    # Usage is safe as we own /var/cpanel and the dir
    my $reseller_limits = Cpanel::CachedDataStore::loaddatastore( $Whostmgr::Limits::Config::RESELLER_LIMITS_FILE, $lock );

    #on a new server we will have no data
    if ( !$reseller_limits->{'data'} ) {
        $reseller_limits->{'data'} = {};
    }

    return $reseller_limits;
}

sub load_resellers_limits {
    my $reseller = shift;
    if ( !$reseller ) { $reseller = $ENV{'REMOTE_USER'}; }
    return unless defined $reseller;
    my $reseller_data = load_all_reseller_limits();
    return $reseller_data->{$reseller} // {};
}

1;
