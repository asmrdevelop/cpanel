package Cpanel::Exception::RootRequired;

# cpanel - Cpanel/Exception/RootRequired.pm        Copyright 2022 cPanel, L.L.C.
#                                                           All rights reserved.
# copyright@cpanel.net                                         http://cpanel.net
# This code is subject to the cPanel license. Unauthorized copying is prohibited

use strict;
use warnings;

use parent qw( Cpanel::Exception );

use Cpanel::LocaleString ();

sub _default_phrase {
    return Cpanel::LocaleString->new('This code must be run as [asis,root].');
}

1;
