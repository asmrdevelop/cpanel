package Cpanel::Fcntl;

# cpanel - Cpanel/Fcntl.pm                         Copyright 2022 cPanel, L.L.C.
#                                                           All rights reserved.
# copyright@cpanel.net                                         http://cpanel.net
# This code is subject to the cPanel license. Unauthorized copying is prohibited

use strict;
use warnings;

use Cpanel::Fcntl::Constants ();

my %CONSTANTS;
my %CACHE;

sub or_flags {
    my (@flags) = @_;
    my $flag_cache_key = join( '|', @flags );
    return $CACHE{$flag_cache_key} if defined $CACHE{$flag_cache_key};
    my $numeric = 0;
    foreach my $o_const (@flags) {
        $numeric |= (
            $CONSTANTS{$o_const} ||= do {
                my $glob     = $Cpanel::Fcntl::Constants::{$o_const};
                my $number_r = $glob && *{$glob}{'SCALAR'};

                #Let this be an untyped exception since it’s very likely a
                #programmer error that an end user should never see.
                die "Missing \$Cpanel::Fcntl::Constants::$o_const! (does it need to be added?)" if !$number_r;

                $$number_r;
            }
        );
    }
    return ( $CACHE{$flag_cache_key} = $numeric );
}

1;
