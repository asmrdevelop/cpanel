package Cpanel::Quota::Cache::QuotasBroken;

# cpanel - Cpanel/Quota/Cache/QuotasBroken.pm      Copyright 2022 cPanel, L.L.C.
#                                                           All rights reserved.
# copyright@cpanel.net                                         http://cpanel.net
# This code is subject to the cPanel license. Unauthorized copying is prohibited

use strict;
use warnings;

=head1 NAME

Cpanel::Quota::Cache::QuotasBroken

=head1 SYNOPSIS

    my $is_on = Cpanel::Quota::Cache::QuotasBroken->is_on();
    Cpanel::Quota::Cache::QuotasBroken->set_off() if $is_on;
    Cpanel::Quota::Cache::QuotasBroken->set_on() if $some_condition;

=cut

use Cpanel::Quota::Cache::Constants ();

use parent qw( Cpanel::Config::TouchFileBase );

sub _TOUCH_FILE { return $Cpanel::Quota::Cache::Constants::QUOTAS_BROKEN_FLAG_FILE; }

1;
