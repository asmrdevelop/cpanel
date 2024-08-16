# cpanel - Cpanel/Server/Startup.pm                Copyright 2022 cPanel, L.L.C.
#                                                           All rights reserved.
# copyright@cpanel.net                                         http://cpanel.net
# This code is subject to the cPanel license. Unauthorized copying is prohibited
package Cpanel::Server::Startup;

use cPstrict;

use Cpanel::ServerTasks;    # Already loaded so use is ok here

=head1 MODULE

C<Cpanel::Server::Startup>

=head1 DESCRIPTION

C<Cpanel::Server::Startup> is used during early cpsrvd startup. Be careful what you load here since it can
increase the size of cpsrvd and all forked child processes.

=head1 SYNOPSIS

  use Cpanel::Server::Startup();

  # Do this in the early stages of cpsrvd startup.
  Cpanel::Server::Startup::run_tasks();

=head1 FUNCTIONS

=head2 run_tasks

Run the startup tasks.

=cut

sub run_tasks {

    # Refresh the license
    Cpanel::ServerTasks::queue_task( ['Cplisc'], 'refresh' );

    # Run custom code provided by the server owner if available, moved from cpsrvd
    system '/usr/local/cpanel/scripts/post_cpsrvd_start' if -x '/usr/local/cpanel/scripts/post_cpsrvd_start';

    return 1;
}

=head2 run_user_tasks

Run the startup tasks once we fork to the user.

=head3 NOTE

Do not add heavy routines or checks here since this is run each time cpsrvd forks a user process.
Keep the checks very lightweight and perform the quickest checks before any more expensive checks
so that there is little to no impact on the performance for most users.

=cut

sub run_user_tasks {
    my ($user) = @_;

    # When the root user is on a trial we will enable analytics
    # for them by default. We want to preserve this once they
    # convert to any other license type. Only do this if they have
    # not already selected a personal choice.

    # We are intentionally breaking down this
    # logic to only load the minimum number of modules
    # needed since this is call on every page request to
    # cpsrvd and we don't want to needlessly bloat memory
    # for the forked process.
    if ( $< == 0 ) {
        require Cpanel::License::Flags;
        if ( Cpanel::License::Flags::has_flag('trial') ) {
            require Whostmgr::NVData;
            if ( !Whostmgr::NVData::get('analytics') ) {
                Whostmgr::NVData::set( 'analytics', 'on' );
            }
        }
    }

    return 1;
}

1;
