package Whostmgr::Mail::Filters;

# cpanel - Whostmgr/Mail/Filters.pm                Copyright 2022 cPanel, L.L.C.
#                                                           All rights reserved.
# copyright@cpanel.net                                         http://cpanel.net
# This code is subject to the cPanel license. Unauthorized copying is prohibited

use strict;
use Cpanel::Dir::Loader ();

our $FILTERS_DIR = '/usr/local/cpanel/etc/exim/sysfilter/options';

sub list_filters_from_disk {
    my %filters;

    my %FILTERS = Cpanel::Dir::Loader::load_dir_as_hash_with_value( $FILTERS_DIR, 1 );
    foreach my $filter ( keys %FILTERS ) {
        $filters{$filter}->{'name'} = $filter;
    }

    return wantarray ? %filters : \%filters;
}

1;
