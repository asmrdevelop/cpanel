package Cpanel::CleanINC;

# cpanel - Cpanel/CleanINC.pm                      Copyright 2022 cPanel, L.L.C.
#                                                           All rights reserved.
# copyright@cpanel.net                                         http://cpanel.net
# This code is subject to the cPanel license. Unauthorized copying is prohibited

use strict;

our $test_load_order;

BEGIN {
    if ( $test_load_order && !$INC{'Cpanel/BinCheck.pm'} ) {
        my @unsafe_loads;
        foreach my $loaded_module ( keys %INC ) {
            push @unsafe_loads, $loaded_module unless ( $loaded_module =~ m{^(?:strict|lib|warnings|INCCheck|Cpanel/CleanINC)\.pm$} );
        }
        die "Found unsafe module loads of (@unsafe_loads)... load Cpanel::CleanINC first." if scalar @unsafe_loads;
    }

    my %seen_inc;
    @INC = grep { !/(?:^\.|\.\.|\/\.+)/ && !$seen_inc{$_}++ } @INC;
    undef %seen_inc;
}

1;
