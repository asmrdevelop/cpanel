package Cpanel::Update::IsCron;

# cpanel - Cpanel/Update/IsCron.pm                 Copyright 2022 cPanel, L.L.C.
#                                                           All rights reserved.
# copyright@cpanel.net                                         http://cpanel.net
# This code is subject to the cPanel license. Unauthorized copying is prohibited

use strict;
use warnings;

=encoding utf-8

=head1 NAME

Cpanel::Update::IsCron - flag to record whether upcp is run from cron

=head1 DISCUSSION

It is sometimes useful for an external process to know whether upcp was
invoked from cron or manually. This flag facilitates that.

Note that this flag’s being unset is indistinguishable from upcp not being
in progress.

=cut

use parent qw( Cpanel::Config::TouchFileBase );

#overridden in tests
our $_PATH = '/var/cpanel/upgrade_is_from_cron';

sub _TOUCH_FILE { return $_PATH }

1;
