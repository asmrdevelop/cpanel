
# cpanel - Cpanel/Exception/ModSecurity/DuplicateQueueItem.pm
#                                                  Copyright 2022 cPanel, L.L.C.
#                                                           All rights reserved.
# copyright@cpanel.net                                         http://cpanel.net
# This code is subject to the cPanel license. Unauthorized copying is prohibited

package Cpanel::Exception::ModSecurity::DuplicateQueueItem;

use strict;
use warnings;

use parent 'Cpanel::Exception';

use Cpanel::LocaleString ();

sub _default_phrase {
    my ($self) = @_;
    return Cpanel::LocaleString->new('The requested action is a duplicate.');
}

1;
