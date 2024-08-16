package Whostmgr::Backup::Pkgacct::Parser;

# cpanel - Whostmgr/Backup/Pkgacct/Parser.pm       Copyright 2022 cPanel, L.L.C.
#                                                           All rights reserved.
# copyright@cpanel.net                                         http://cpanel.net
# This code is subject to the cPanel license. Unauthorized copying is prohibited

use strict;

use parent qw( Cpanel::Parser::Base Whostmgr::Remote::Parser::Pkgacct );

sub process_line {
    my ( $self, $line ) = @_;

    $self->_parse_data_line($line) if length $line;

    return 1;
}

1;
