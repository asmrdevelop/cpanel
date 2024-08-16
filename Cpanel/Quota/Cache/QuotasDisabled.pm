package Cpanel::Quota::Cache::QuotasDisabled;

# cpanel - Cpanel/Quota/Cache/QuotasDisabled.pm    Copyright 2022 cPanel, L.L.C.
#                                                           All rights reserved.
# copyright@cpanel.net                                         http://cpanel.net
# This code is subject to the cPanel license. Unauthorized copying is prohibited

use strict;
use warnings;

use Cpanel::Quota::Cache::Constants ();

use parent qw( Cpanel::Config::TouchFileBase );

sub _TOUCH_FILE { return $Cpanel::Quota::Cache::Constants::QUOTAS_DISABLED_FLAG_FILE; }

1;
