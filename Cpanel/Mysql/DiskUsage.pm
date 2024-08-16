package Cpanel::Mysql::DiskUsage;

# cpanel - Cpanel/Mysql/DiskUsage.pm               Copyright 2022 cPanel, L.L.C.
#                                                           All rights reserved.
# copyright@cpanel.net                                         http://cpanel.net
# This code is subject to the cPanel license. Unauthorized copying is prohibited

#----------------------------------------------------------------------
# This abstracts handling of the cache datastore for the mapping of
# DB name to DB disk usage.
#
# NOTE: Because the best way to get fresh data is context-sensitive, this
# module does NOT provide a _LOAD_FRESH() method; therefore, every caller
# that does a load() MUST check for NEED_FRESH errors and accommodate.
#----------------------------------------------------------------------

use strict;
use warnings;

use Cpanel::UserDatastore ();

use parent qw(Cpanel::CacheFile);

sub _PATH {
    my ( $self, $user ) = @_;

    die "Need username!" if !length $user;

    if ( $> == 0 ) {
        require Cpanel::UserDatastore::Init;
        Cpanel::UserDatastore::Init::initialize($user);
    }

    my $dir = Cpanel::UserDatastore::get_path($user);

    return "$dir/mysql-db-usage.json";
}

sub _TTL { return 60 * 60 * 4.5 }    #4.5 hours

#User-readable.
sub _MODE { return 0640 }

sub _OWNER {
    my ( $self, $user ) = @_;
    return 'root', $user;
}

1;
