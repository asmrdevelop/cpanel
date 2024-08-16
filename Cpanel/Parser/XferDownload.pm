package Cpanel::Parser::XferDownload;

# cpanel - Cpanel/Parser/XferDownload.pm           Copyright 2022 cPanel, L.L.C.
#                                                           All rights reserved.
# copyright@cpanel.net                                         http://cpanel.net
# This code is subject to the cPanel license. Unauthorized copying is prohibited

use strict;

use base 'Cpanel::Parser::Base';

sub process_line {
    my ( $self, $line ) = @_;

    if ( $line =~ m{^Done} ) {
        $self->output($line);
        $self->{'success'} = 1;
    }
    else {
        $self->output($line);
    }

    return 1;
}

1;
