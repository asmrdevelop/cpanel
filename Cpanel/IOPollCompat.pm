
# cpanel - Cpanel/IOPollCompat.pm                  Copyright 2022 cPanel, L.L.C.
#                                                           All rights reserved.
# copyright@cpanel.net                                         http://cpanel.net
# This code is subject to the cPanel license. Unauthorized copying is prohibited

package Cpanel::IOPollCompat;

sub IO::Poll::forced_remove {
    my $self = shift;
    my $io   = shift;
    my $fd   = fileno($io);

    delete $self->[0]{$fd}{$io};
    delete $self->[0]{$fd};
    delete $self->[2]{$io};
    delete $self->[1]{$fd};
}

sub IO::Poll::cleanup {
    my $self = shift;
    my $fd;
    my $ev;

    #remove dead references
    while ( ( $fd, $ev ) = each %{ $self->[1] } ) {
        if ( !scalar keys %{ $self->[0]{$fd} } ) {
            delete $self->[0]{$fd};
        }
    }
}

1;
