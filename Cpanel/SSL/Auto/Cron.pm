package Cpanel::SSL::Auto::Cron;

# cpanel - Cpanel/SSL/Auto/Cron.pm                 Copyright 2022 cPanel, L.L.C.
#                                                           All rights reserved.
# copyright@cpanel.net                                         http://cpanel.net
# This code is subject to the cPanel license. Unauthorized copying is prohibited

#TODO: Reduce duplication between this and Cpanel::SSL::PendingQueue::Cron.

=encoding utf-8

=head1 NAME

Cpanel::SSL::Auto::Cron - Logic to manage the cron job for AutoSSL runs

=head1 DESCRIPTION

This module handles root’s cron entry to make AutoSSL work either ensuring that it does exist or ensuring
that it doesn’t exist.

This module is a concrete implementation of C<Cpanel::Crontab::Entry::Base>. See that module for
implementation details.

=cut

use strict;
use warnings;

use parent qw(
  Cpanel::Crontab::Entry::Base
);

use Cpanel::SSL::Auto::Check        ();
use Cpanel::SSL::Auto::Config::Read ();
use Cpanel::SSL::Auto::Loader       ();
use Cpanel::Update::Crontab         ();

#referenced from tests
our $COMMAND = "$Cpanel::SSL::Auto::Check::COMMAND --all";

our $CRON_FILE = '/etc/cron.d/cpanel_autossl';

sub _COMMAND {
    return $COMMAND;
}

sub _CRON_FILE {
    return $CRON_FILE;
}

# stubbed in tests
sub _get_provider_frequency {
    my $conf_obj      = Cpanel::SSL::Auto::Config::Read->new();
    my $provider_name = $conf_obj->get_provider();
    my $provider_obj  = Cpanel::SSL::Auto::Loader::get_and_load($provider_name)->new();

    return $provider_obj->CHECK_FREQUENCY();
}

sub _get_crontab_hour_minute_opts {
    my ( $hour, $minute ) = Cpanel::Update::Crontab::get_random_hr_and_min();

    my $frequency = _get_provider_frequency();

    if ( $frequency eq '3hours' ) {
        $hour %= 3;

        my $hh = $hour;

        while (1) {
            $hh += 3;

            last if $hh > 23;

            $hour .= ",$hh";
        }
    }
    elsif ( $frequency ne 'daily' ) {
        die "Active AutoSSL provider has an invalid CHECK_FREQUENCY ($frequency)!";
    }

    return ( -minute => $minute, -hour => $hour );
}

1;
