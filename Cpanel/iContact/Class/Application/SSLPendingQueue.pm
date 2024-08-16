package Cpanel::iContact::Class::Application::SSLPendingQueue;

# cpanel - Cpanel/iContact/Class/Application/SSLPendingQueue.pm
#                                                  Copyright 2022 cPanel, L.L.C.
#                                                           All rights reserved.
# copyright@cpanel.net                                         http://cpanel.net
# This code is subject to the cPanel license. Unauthorized copying is prohibited

use strict;
use warnings;

use parent qw(
  Cpanel::iContact::Class::Application
);

#called from test
sub _APPLICATION_NAME { return 'SSL Pending Queue' }

1;
