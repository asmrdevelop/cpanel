package Cpanel::IO::FramedFlush;

# cpanel - Cpanel/IO/FramedFlush.pm                Copyright 2022 cPanel, L.L.C.
#                                                           All rights reserved.
# copyright@cpanel.net                                         http://cpanel.net
# This code is subject to the cPanel license. Unauthorized copying is prohibited

use strict;
use warnings;

use IO::SigGuard ();

=encoding utf-8

=head1 NAME

Cpanel::IO::FramedFlush

=head1 SYNOPSIS

    Cpanel::IO::FramedFlush::flush_with_determination( $io_framed_obj );

=head1 DESCRIPTION

This module contains useful logic for flushing an L<IO::Framed::Write>
object.

=head1 FUNCTIONS

=head2 $emptied_yn = flush_with_determination( FRAMED_OBJ )

This will try “very hard” to empty out the contents of FRAMED_OBJ’s
write buffer. If the flush succeeds we return 1; if the flush times out
we return falsey. Otherwise an exception is thrown.

=cut

#overridden in tests
our $_TIMEOUT = 10;

sub flush_with_determination {
    my ($framed_obj) = @_;

    $framed_obj->flush_write_queue();

    vec( my $mask, fileno( $framed_obj->get_write_fh() ), 1 ) = 1;

    while ( $framed_obj->get_write_queue_count() ) {
        my $result = IO::SigGuard::select( undef, my $m = $mask, undef, $_TIMEOUT );

        if ( $result == -1 ) {
            die "select() to flush failed: $!";
        }
        elsif ( $result == 0 ) {
            return undef;
        }

        $framed_obj->flush_write_queue();
    }

    return 1;
}

1;
