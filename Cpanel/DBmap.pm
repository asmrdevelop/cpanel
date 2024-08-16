package Cpanel::DBmap;

# cpanel - Cpanel/DBmap.pm                         Copyright 2022 cPanel, L.L.C.
#                                                           All rights reserved.
# copyright@cpanel.net                                         http://cpanel.net
# This code is subject to the cPanel license. Unauthorized copying is prohibited

use strict;

use Cpanel::DB::Prefix::Conf ();
use Cpanel::LoadFile         ();

sub DBmap_init {

}

sub api2_status {

    my @RSD;
    my $prefix = Cpanel::DB::Prefix::Conf::use_prefix();

    push @RSD, { prefix => $prefix };

    return @RSD;
}

sub api2_version {

    my $local_version = Cpanel::LoadFile::loadfile('/usr/local/cpanel/version');
    ($local_version) = ( split( '-', $local_version,, 2 ) )[0];

    return ( { version => $local_version } );
}

my $allow_demo = { allow_demo => 1 };

our %API = (
    status  => $allow_demo,
    version => $allow_demo,
);

sub api2 {
    my ($func) = @_;
    return { %{ $API{$func} } } if $API{$func};
    return;
}

1;
