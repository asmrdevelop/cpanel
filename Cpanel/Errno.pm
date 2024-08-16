package Cpanel::Errno;

# cpanel - Cpanel/Errno.pm                           Copyright 2022 cPanel L.L.C.
#                                                           All rights reserved.
# copyright@cpanel.net                                         http://cpanel.net
# This code is subject to the cPanel license. Unauthorized copying is prohibited

use strict;

my %_err_name_cache;

sub get_name_for_errno_number {
    my ($number) = @_;

    if ( !$INC{'Errno.pm'} ) {
        local ( $@, $! );
        require Errno;
    }

    die 'need number!' if !length $number;

    if ( !%_err_name_cache ) {

        # do not use Errno::TIEHASH, as it s going to be an issue
        #   when using system perl with older versions of Errno
        my $s = scalar keys %Errno::;    # init iterator
        foreach my $k ( sort keys %Errno:: ) {
            if ( Errno->EXISTS($k) ) {
                my $v = 'Errno'->can($k)->();
                $_err_name_cache{$v} = $k;
            }
        }
    }

    return $_err_name_cache{$number};
}

1;
