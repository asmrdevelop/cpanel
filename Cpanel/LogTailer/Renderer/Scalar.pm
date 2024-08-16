package Cpanel::LogTailer::Renderer::Scalar;

# cpanel - Cpanel/LogTailer/Renderer/Scalar.pm     Copyright 2022 cPanel, L.L.C.
#                                                           All rights reserved.
# copyright@cpanel.net                                         http://cpanel.net
# This code is subject to the cPanel license. Unauthorized copying is prohibited

use strict;

sub new {
    my ($class) = @_;

    my $var;
    my $self = \$var;

    return bless $self, $class;
}

sub render_message {
    my ( $self, $message ) = @_;

    $$self .= $message;

    return 1;
}

sub keepalive {
    my ($self) = @_;

    return 1;
}

1;
