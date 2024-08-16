package Cpanel::Exception::Service::MysqlIsDown;

# cpanel - Cpanel/Exception/Service/MysqlIsDown.pm Copyright 2022 cPanel, L.L.C.
#                                                           All rights reserved.
# copyright@cpanel.net                                         http://cpanel.net
# This code is subject to the cPanel license. Unauthorized copying is prohibited

use strict;
use warnings;

use parent qw( Cpanel::Exception );

use Cpanel::LocaleString ();

#Parameters:
#   none
#
sub _default_phrase {
    my ($self) = @_;

    return Cpanel::LocaleString->new('The [asis,MySQL] service is down.');
}

1;
