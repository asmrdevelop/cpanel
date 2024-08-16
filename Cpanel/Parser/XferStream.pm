package Cpanel::Parser::XferStream;

# cpanel - Cpanel/Parser/XferStream.pm             Copyright 2022 cPanel, L.L.C.
#                                                           All rights reserved.
# copyright@cpanel.net                                         http://cpanel.net
# This code is subject to the cPanel license. Unauthorized copying is prohibited

use strict;

use base 'Cpanel::Parser::Base';

sub process_line {
    my ( $self, $line ) = @_;

    if ( $line =~ m{^xferstream tag passed} ) {
        $self->output($line);
        $self->{'success'} = 1;
    }
    else {
        $self->output($line);
    }

    return 1;
}

1;
