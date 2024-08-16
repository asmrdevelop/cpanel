package Cpanel::Sync::Stream::Client;

# cpanel - Cpanel/Sync/Stream/Client.pm            Copyright 2022 cPanel, L.L.C.
#                                                           All rights reserved.
# copyright@cpanel.net                                         http://cpanel.net
# This code is subject to the cPanel license. Unauthorized copying is prohibited

use strict;

use base 'Cpanel::Sync::Stream::UnguardedClient';
use Try::Tiny;

my $MAX_ATTEMPTS = 5;

sub send_start_rsync { shift->_autoreconnect_op( 'send_start_rsync', @_ ); }

sub _autoreconnect_op {
    my $self = shift;
    my $func = shift;

    my $ret;
    for my $attempt ( 1 .. $MAX_ATTEMPTS ) {

        # Not using try {} here because we need to
        # preserve @_
        local $@;
        eval {
            $self->_build_sync_stream_connection() if !$self->{'_socket'};
            $ret = $self->can("SUPER::$func")->( $self, @_ );
        };
        if ($@) {
            die if ( $attempt == $MAX_ATTEMPTS );
            delete $self->{'_socket'};
            next;
        }
        return $ret;
    }

    # Should not be reached because we should die above (this is just here as a refactoring safety)
    die "The system to failed to execute the “$func” call after “$MAX_ATTEMPTS” attempts.";
}

sub _build_sync_stream_connection {
    my ($self) = @_;
    if ( $self->{'_socket'} ) {
        try { $self->{'_socket'}->close(); };
    }
    $self->{'_socket'} = $self->{'_client'}->connect_syncstream();
    return $self->post_connect_helo();
}

1;
