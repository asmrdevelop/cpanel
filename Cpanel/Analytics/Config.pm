
# cpanel - Cpanel/Analytics/Config.pm              Copyright 2022 cPanel, L.L.C.
#                                                           All rights reserved.
# copyright@cpanel.net                                         http://cpanel.net
# This code is subject to the cPanel license. Unauthorized copying is prohibited

# Test::Cpanel::Policy - constants

package Cpanel::Analytics::Config;

use strict;
use warnings;

=head1 NAME

Cpanel::Analytics::Config - Constants for cpanalyticsd

=cut

=head1 CONSTANTS

=head2 ANALYTICS_USER

The username under which cpanalyticsd runs

=cut

sub ANALYTICS_USER { return q{cpanelanalytics} }

=head2 ANALYTICS_PID_FILE

The path to the pid file for cpanalyticsd. B<Important note>: With dormant mode,
the daemon needs to rewrite this file after privileges have already been dropped,
so this needs to be under a directory that's writable by ANALYTICS_USER. Having
under /var/run is not an option.

=cut

sub ANALYTICS_PID_FILE { return q{/var/cpanel/analytics/run/cpanalyticsd.pid} }

=head2 ANALYTICS_DIR

The base directory for most files related to analytics

=cut

sub ANALYTICS_DIR { return q{/var/cpanel/analytics} }

=head2 ANALYTICS_DATA_DIR

Where the actual data being gathered is stored

=cut

sub ANALYTICS_DATA_DIR { return ANALYTICS_DIR() . q{/data} }

=head2 ANALYTICS_LOG_DIR

The directory for the cpanalyticsd error log (and any other diagnostic type logs)

=cut

sub ANALYTICS_LOGS_DIR { return ANALYTICS_DIR() . q{/logs} }

=head2 ANALYTICS_RUN_DIR

The directory used by cpanalyticsd for storing pid and lock files

=cut

sub ANALYTICS_RUN_DIR { return ANALYTICS_DIR() . q{/run} }

=head2 ANALYTICS_SOCKET

The path to the unix domain socket used by cpanalyticsd

=cut

sub ANALYTICS_SOCKET { return ANALYTICS_RUN_DIR() . q{/socket} }

=head2 ERROR_LOG

The path to the cpanalyticsd error log

=cut

sub ERROR_LOG { return ANALYTICS_LOGS_DIR() . q{/error.log} }

=head2 OPERATIONS_LOG

The path to the log file containing the actual data gathered by cpanalyticsd.
This might change in the future if cpanalyticsd ends up storing the data in,
for example, a database, or sending it directly to a remote server.

=cut

sub OPERATIONS_LOG {
    my ($facility) = @_;
    $facility //= 'operations';
    return ANALYTICS_DATA_DIR() . qq{/$facility.log};
}

=head2 OPERATIONS_LOG_LOCK

The path to the lock file for OPERATIONS_LOG.

=cut

sub OPERATIONS_LOG_LOCK { return ANALYTICS_RUN_DIR() . q{/operations.log.lock} }

=head2 SYSTEM_ID_NAME

The name of the file that contains the unique system id.

=cut

sub SYSTEM_ID_NAME { return q{system_id} }

=head2 SYSTEM_ID_PATH

The full path to the SYSTEM_ID_NAME file

=cut

sub SYSTEM_ID_PATH { return ANALYTICS_DIR() . '/' . SYSTEM_ID_NAME() }

=head2 FEATURE_TOGGLES_DIR

The directory containing touch files for enabling and disabling certain
features, including analytics.

=cut

sub FEATURE_TOGGLES_DIR { return q{/var/cpanel/feature_toggles} }

=head2 TOUCH_FILE

The full path to the touch file under FEATURE_TOGGLES_DIR for analytics.

=cut

sub TOUCH_FILE { return FEATURE_TOGGLES_DIR() . q{/analytics} }

=head2 SERVICE_MANAGER_TOUCH_FILE

Temporary. We will only rely on this touch file while we are not widely enabling this feature.
Will be removed in LC-8087.

=cut

sub SERVICE_MANAGER_TOUCH_FILE { return FEATURE_TOGGLES_DIR() . q{/analytics_service_manager} }

=head2 UI_INCLUDES_TOUCH_FILE

The full path to the touch file under FEATURE_TOGGLES_DIR for browser-based, client-side analytics that use UI includes.

=cut

sub UI_INCLUDES_TOUCH_FILE { return FEATURE_TOGGLES_DIR() . q{/analytics_ui_includes} }

1;
