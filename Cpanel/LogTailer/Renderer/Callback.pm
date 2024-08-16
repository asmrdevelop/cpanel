package Cpanel::LogTailer::Renderer::Callback;

# cpanel - Cpanel/LogTailer/Renderer/Callback.pm   Copyright 2022 cPanel, L.L.C.
#                                                           All rights reserved.
# copyright@cpanel.net                                         http://cpanel.net
# This code is subject to the cPanel license. Unauthorized copying is prohibited

use strict;

sub new {
    my ( $class, %OPTS ) = @_;

    my $self = { 'callback' => $OPTS{'callback'} };

    return bless $self, $class;
}

sub render_message {
    my ( $self, $message, $logfile ) = @_;

    return $self->{'callback'}->( $message, $logfile );
}

sub keepalive {
    my ($self) = @_;

    return 1;
}

1;
