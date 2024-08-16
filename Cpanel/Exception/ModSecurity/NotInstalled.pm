
# cpanel - Cpanel/Exception/ModSecurity/NotInstalled.pm
#                                                  Copyright 2022 cPanel, L.L.C.
#                                                           All rights reserved.
# copyright@cpanel.net                                         http://cpanel.net
# This code is subject to the cPanel license. Unauthorized copying is prohibited

package Cpanel::Exception::ModSecurity::NotInstalled;

use strict;
use warnings;

use parent 'Cpanel::Exception';

use Cpanel::LocaleString ();

sub _default_phrase {
    my ($self) = @_;
    return Cpanel::LocaleString->new('You must install [asis,ModSecurity™] before queueing this action.');
}

1;
