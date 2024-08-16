package Cpanel::Server::Response::Source::ReadOnlyStream;

# cpanel - Cpanel/Server/Response/Source/ReadOnlyStream.pm
#                                                  Copyright 2022 cPanel, L.L.C.
#                                                           All rights reserved.
# copyright@cpanel.net                                         http://cpanel.net
# This code is subject to the cPanel license. Unauthorized copying is prohibited

use strict;
use warnings;

use parent 'Cpanel::Server::Response::Source::Stream';

sub buffer_is_read_only { return 1; }

sub read_size { return 1024**2 * 16; }

1;
__END__
