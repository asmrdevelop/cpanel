package Cpanel::Net::Accept;

# cpanel - Cpanel/Net/Accept.pm                    Copyright 2022 cPanel, L.L.C.
#                                                           All rights reserved.
# copyright@cpanel.net                                         http://cpanel.net
# This code is subject to the cPanel license. Unauthorized copying is prohibited

use strict;
use warnings;

=encoding utf-8

=head1 NAME

Cpanel::Net::Accept - safely C<accept()> connections

=head1 SYNOPSIS

    my $addr = Cpanel::Net::Accept::accept( $new_skt, $generic_skt );

=cut

#----------------------------------------------------------------------

use Cpanel::FHUtils::Blocking ();

#----------------------------------------------------------------------

=head1 FUNCTIONS

=head2 $addr = accept( $NEWSOCKET, $GENERICSOCKET )

A drop-in replacement for Perl’s C<accept()> built-in that guarantees that
the socket is set to non-blocking mode when it accepts the connection. It
does not permanently alter the socket’s blocking mode.

C<$!> is set to the value that C<accept()> set for it, and the return value
is also C<accept()>’s.

Servers that listen on multiple sockets concurrently need to do non-blocking
C<accept()> to avoid a potential race condition where, e.g., a TCP connection
shows as ready (which would cause multiplexing calls like C<select()> to
indicate that the file handle is ready to read), then the server receives a
TCP RST prior to the server’s C<accept()> call. If this happens, C<accept()>
on a blocking file handle may block.

For an in-depth discussion, see Stevens et al., “Unix Network Programming”,
3rd ed., vol. 1, section 16.6.

Note that, as of this writing, there is no proof of concept of the bug that
this addresses. It’s possible that Linux now guards against the problem,
or perhaps the RST has to arrive at a very specific time in order for
C<accept()> to block. Nonetheless, it’s best to use this method to avoid
any potential problem.

=cut

sub accept {    ## no critic qw(RequireArgUnpacking)
    my $was_blocking = Cpanel::FHUtils::Blocking::is_set_to_block( $_[1] );
    Cpanel::FHUtils::Blocking::set_non_blocking( $_[1] );

    my $peer;
    if ( $_[1]->can('accept') ) {
        my $new;
        ( $new, $peer ) = $_[1]->accept();
        if ( $new && $new->isa('IO::Socket') ) {
            ${*$new}{'io_socket_peername'} = $peer;
            $_[0] = $new;
        }
    }
    else {
        $peer = accept( $_[0], $_[1] );
    }

    Cpanel::FHUtils::Blocking::set_blocking( $_[1] ) if $was_blocking;

    return $peer;
}

1;
