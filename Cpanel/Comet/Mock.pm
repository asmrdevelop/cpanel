package Cpanel::Comet::Mock;

# cpanel - Cpanel/Comet/Mock.pm                    Copyright 2022 cPanel, L.L.C.
#                                                           All rights reserved.
# copyright@cpanel.net                                         http://cpanel.net
# This code is subject to the cPanel license. Unauthorized copying is prohibited

use strict;

sub new {
    my ($class) = @_;

    return bless {}, $class;
}

sub add_message {
    my ( $self, $channel, $msg ) = @_;
    push @{ $self->{'msgs'}{$channel} }, $msg;
    return 1;
}

sub get_messages {
    my ( $self, $channel ) = @_;
    return $self->{'msgs'}{$channel};
}

sub purgeclient {
    my ($self) = @_;
    return 1;
}

1;
