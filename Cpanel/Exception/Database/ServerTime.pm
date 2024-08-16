package Cpanel::Exception::Database::ServerTime;

# cpanel - Cpanel/Exception/Database/ServerTime.pm Copyright 2022 cPanel, L.L.C.
#                                                           All rights reserved.
# copyright@cpanel.net                                         http://cpanel.net
# This code is subject to the cPanel license. Unauthorized copying is prohibited

use strict;
use warnings;

use parent qw( Cpanel::Exception );

use Cpanel::LocaleString ();

sub _default_phrase {
    my ($self) = @_;

    return Cpanel::LocaleString->new('The server time and the [asis,MySQL]® time are different.');
}

1;
