package Cpanel::Autodie;

# cpanel - Cpanel/Autodie/CORE/read.pm             Copyright 2022 cPanel, L.L.C.
#                                                           All rights reserved.
# copyright@cpanel.net                                         http://cpanel.net
# This code is subject to the cPanel license. Unauthorized copying is prohibited

use strict;
use warnings;

=head1 FUNCTIONS

=head2 read( .. )

cf. L<perlfunc/read>

=cut

#NOTE: read() and sysread() implementations are exactly the same except
#for the CORE:: function call.  Alas, Perl's prototyping stuff seems to
#make it impossible not to duplicate code here.
sub read {    ## no critic(RequireArgUnpacking)
              # $_[1]: buffer
    my ( $fh, @length_offset ) = ( $_[0], @_[ 2 .. $#_ ] );

    my ( $length, $offset ) = @length_offset;

    local ( $!, $^E );

    #NOTE: Perl's prototypes can throw errors on things like:
    #(@length_offset > 1) ? $offset : ()
    #...so the following writes out the two forms of read():

    my $ret;
    if ( @length_offset > 1 ) {
        $ret = CORE::read( $fh, $_[1], $length, $offset );
    }
    else {
        $ret = CORE::read( $fh, $_[1], $length );
    }

    #XXX: TODO: Accommodate negative $offset

    if ( !defined $ret ) {
        my $err = $!;
        {
            local ( $!, $@ );
            require Cpanel::Exception;
        }
        die Cpanel::Exception::create( 'IO::ReadError', [ error => $err, length => $length ] );
    }

    return $ret;
}

1;
