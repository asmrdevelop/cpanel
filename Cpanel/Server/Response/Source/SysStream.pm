package Cpanel::Server::Response::Source::SysStream;

# cpanel - Cpanel/Server/Response/Source/SysStream.pm
#                                                  Copyright 2022 cPanel, L.L.C.
#                                                           All rights reserved.
# copyright@cpanel.net                                         http://cpanel.net
# This code is subject to the cPanel license. Unauthorized copying is prohibited

use strict;
use warnings;

use parent 'Cpanel::Server::Response::Source::Stream';

sub input_handle_read_function_name { return 'sysread'; }

1;
__END__
