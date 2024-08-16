package Cpanel::Buffer;

# cpanel - Cpanel/Buffer.pm                        Copyright 2022 cPanel, L.L.C.
#                                                           All rights reserved.
# copyright@cpanel.net                                         http://cpanel.net
# This code is subject to the cPanel license. Unauthorized copying is prohibited

use strict;

our $DEFAULT_READ_SIZE = 65536;    # 2**17 is faster, but it makes upload progress updates too infrequent.

sub move_bytes_from_buffer_ref_to_buffer_ref {    ## no critic qw(RequireArgUnpacking)

    # $_[0]   # SOURCE BUFFER REFERENCE
    # $_[1]   # TARGET BUFFER REFERENCE
    # $_[2]   # NUMBER OF BYTES TO MOVE
    # $_[3]   # TARGET BUFFER OFFSET

    # This splices $BYTES_TO_READ ($_[2]) bytes out of
    # _stdout_buffer into $BUFFER ($_[1]) at $BUFFER_OFFSET $_[3]
    return substr(
        ${ $_[1] },    # TARGET BUFFER
        $_[3] || 0,    # TARGET BUFFER OFFSET
        $_[2],         # NUMBER OF BYTES TO MOVE
        substr(
            ${ $_[0] },    # SOURCE BUFFER
            0,             # OFFSET TO START ON SOURCE BUFFER
            $_[2],         # NUMBER OF BYTES TO MOVE
            ''             # REMOVE THESE BYTES FROM SOURCE BUFFER
        )
    );
}

1;
