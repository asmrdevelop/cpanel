package Cpanel::Exception::ForbiddenInDemoMode;

# cpanel - Cpanel/Exception/ForbiddenInDemoMode.pm Copyright 2022 cPanel, L.L.C.
#                                                           All rights reserved.
# copyright@cpanel.net                                         http://cpanel.net
# This code is subject to the cPanel license. Unauthorized copying is prohibited

use strict;
use warnings;

use parent qw(Cpanel::Exception);

use Cpanel::LocaleString ();

#metadata parameters:
#
#(none)
#
sub _default_phrase {
    my ($self) = @_;

    return Cpanel::LocaleString->new('This functionality is not available in demo mode.');
}

1;
