
# cpanel - Cpanel/HttpUtils/ApRestart/BgSafe.pm    Copyright 2022 cPanel, L.L.C.
#                                                           All rights reserved.
# copyright@cpanel.net                                         http://cpanel.net
# This code is subject to the cPanel license. Unauthorized copying is prohibited

package Cpanel::HttpUtils::ApRestart::BgSafe;

use strict;
use warnings;
use Cpanel::ServerTasks        ();
use Cpanel::Debug              ();
use Cpanel::Config::LoadCpConf ();

my $DEFAULT_TIME_TO_WAIT_BETWEEN_AP_RESTART = 10;

=encoding utf-8

=head1 NAME

Cpanel::HttpUtils::ApRestart - Restart and/or rebuild Apache configuration.

=cut

sub restart {

    # Wait 10 seconds to restart so we can collapse all restart requests that
    # come in to avoid multiple restarts in the window.
    # Note: since this is queing a normal restart for later, that restart will be subject to the httpd_deferred_restart_time Tweak Setting
    eval { Cpanel::ServerTasks::schedule_task( ['ApacheTasks'], get_time_between_ap_restarts(), 'apache_restart' ); };
    if ($@) {
        Cpanel::Debug::log_warn("Could not restart apache: $@");
        return 0;
    }
    return 1;
}

sub rebuild {
    eval { Cpanel::ServerTasks::queue_task( ['ApacheTasks'], 'build_apache_conf' ); };
    if ($@) {
        Cpanel::Debug::log_warn("Could not rebuild apache: $@");
        return 0;
    }
    return 1;
}

=head2 get_time_between_ap_restarts()

Returns the time to wait between apache restarts
as configured in Tweak Settings.

=cut

sub get_time_between_ap_restarts {
    my $cpconf_ref = Cpanel::Config::LoadCpConf::loadcpconf_not_copy();
    return $cpconf_ref->{'min_time_between_apache_graceful_restarts'} || $DEFAULT_TIME_TO_WAIT_BETWEEN_AP_RESTART;
}
1;
