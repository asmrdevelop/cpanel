package Cpanel::IO;

# cpanel - Cpanel/IO.pm                            Copyright 2022 cPanel, L.L.C.
#                                                           All rights reserved.
# copyright@cpanel.net                                         http://cpanel.net
# This code is subject to the cPanel license. Unauthorized copying is prohibited

use strict;

#Read a chunk such that:
#   If there are > $$read_size_r bytes left, we'll get $$read_size_r bytes plus
#   whatever takes us to the end of the next line.
#   If there are <= $$read_size_r bytes left, we get the rest of the stream.
#
#Parameters:
#   0) The file handle reference
#   1) The max length to read
sub read_bytes_to_end_of_line {    ##no critic qw(RequireArgUnpacking)
                                   # $_[0]: fh
                                   # $_[1]: max_read_size
    my $buffer;
    if ( read( $_[0], $buffer, $_[1] || 32768 ) ) {
        my $next = readline( $_[0] );
        $next = '' unless defined $next;
        return $buffer . $next;
    }

    return undef;
}

1;
