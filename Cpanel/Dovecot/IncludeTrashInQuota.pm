package Cpanel::Dovecot::IncludeTrashInQuota;

# cpanel - Cpanel/Dovecot/IncludeTrashInQuota.pm   Copyright 2022 cPanel, L.L.C.
#                                                           All rights reserved.
# copyright@cpanel.net                                         http://cpanel.net
# This code is subject to the cPanel license. Unauthorized copying is prohibited

use strict;
use warnings;

use Cpanel::Dovecot::Constants ();

use parent qw( Cpanel::Config::TouchFileBase );

use constant _TOUCH_FILE => $Cpanel::Dovecot::Constants::INCLUDE_TRASH_IN_QUOTA_CONFIG_CACHE_FILE;

1;
