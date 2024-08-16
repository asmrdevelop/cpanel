package Cpanel::iContact::EventImportance::Legacy;

# cpanel - Cpanel/iContact/EventImportance/Legacy.pm
#                                                  Copyright 2022 cPanel, L.L.C.
#                                                           All rights reserved.
# copyright@cpanel.net                                         http://cpanel.net
# This code is subject to the cPanel license. Unauthorized copying is prohibited

use strict;

use Cpanel::FileUtils::Read ();

our $_legacy_iclevels_file = '/var/cpanel/iclevels.conf';

sub get_data_struct_from_legacy {
    my %legacy;

    if ( -s $_legacy_iclevels_file ) {
        Cpanel::FileUtils::Read::for_each_line(
            $_legacy_iclevels_file,
            sub {
                chomp;
                s/\r//g;
                if (m/^(\S+)\s+(\S+)/) {
                    my $app   = $1;
                    my $level = $2;
                    next if !length $level;

                    $legacy{$app} = $level;
                }
            },
        );
    }

    return \%legacy;
}

1;
