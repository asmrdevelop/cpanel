
# cpanel - Cpanel/RestartSrv/Help.pm               Copyright 2022 cPanel, L.L.C.
#                                                           All rights reserved.
# copyright@cpanel.net                                         http://cpanel.net
# This code is subject to the cPanel license. Unauthorized copying is prohibited

package Cpanel::RestartSrv::Help;

use strict;
use warnings;

=head1 NAME

Cpanel::RestartSrv::Help

=head1 SYNOPSIS

Module for allowing multiple scripts to include the 'help' text for scripts/restartrsrv,
as there's more than one script for this.

=head1 SUBROUTINES

=head2 usage

Does what you'd expect -- prints usage. Exits 0.

SEE ALSO: scripts/restartsrv, bin/restartsrv_base

=cut

sub usage {
    my ($service) = @_;
    my $script = $0;
    $script =~ s{^/usr/local/cpanel}{};
    $service ||= '[SERVICE]';

    print <<"HELP";
$script - manage service $service

Usage: $script [ACTION] [OPTIONS]

The default action is to restart the $service service.

The script returns 0 in case of success,
and a positive integer in case of an error.

Note: Error output is displayed on STDERR.

Available actions:
   --help           Display this help message.
   --restart        Restart the service (via a soft restart, if available). [default action]
   --hard           Perform a hard restart (skip the soft restart).
                    This is the default action if soft restarts aren't supported for the service.
   --graceful       Attempt a graceful restart of the service, if the service supports this action.
   --reload         Reload the service, if the service supports this action.
   --stop           Stop the service.
   --status         Return the current service status via the exit code.

Available options:
   --notconfigured-ok    Services that are not configured will exit with a non-fatal return code
                             (this does not mean they'll carry out the requested action, ie start)

Sample usages:
# Restart the service (using a "soft" or "graceful" restart when supported)
> $script
> $script --restart
# Stop the service.
> $script --stop
# Perform a hard restart.
> $script --restart --hard

HELP

    return 0;
}

1;
