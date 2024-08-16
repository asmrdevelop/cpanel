package Cpanel::Server::Response::Source::ReadOnlyString;

# cpanel - Cpanel/Server/Response/Source/ReadOnlyString.pm
#                                                  Copyright 2022 cPanel, L.L.C.
#                                                           All rights reserved.
# copyright@cpanel.net                                         http://cpanel.net
# This code is subject to the cPanel license. Unauthorized copying is prohibited

use strict;
use warnings;

use parent 'Cpanel::Server::Response::Source';

use constant {
    entire_content_is_in_memory => 1,
    buffer_is_read_only         => 1,
    read_size                   => ( 1024**2 * 16 ),
};

1;
