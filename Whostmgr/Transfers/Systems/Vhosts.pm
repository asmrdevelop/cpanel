package Whostmgr::Transfers::Systems::Vhosts;

# cpanel - Whostmgr/Transfers/Systems/Vhosts.pm    Copyright 2022 cPanel, L.L.C.
#                                                           All rights reserved.
# copyright@cpanel.net                                         http://cpanel.net
# This code is subject to the cPanel license. Unauthorized copying is prohibited

use strict;
use warnings;

use Cpanel::ServerTasks ();

use base qw(
  Whostmgr::Transfers::Systems
);

=encoding utf-8

=head1 NAME

Whostmgr::Transfers::Systems::Vhosts - Install webserver configuration and restart.

=head1 SYNOPSIS

    use Whostmgr::Transfers::Systems::Vhosts;

    # Only called by the transfer restore system.

=head1 DESCRIPTION

This module installs the web server configuration and restarts the web server.
Once all the modules responsible for creating the userdata have run this module
will create the actual vhost entries in the httpd.conf for any additional domains.

Currently the Domain and SSL modules create username for new virtual hosts and rely
on this module to do the creation of the vhost entries in a single call to avoid
multiple update cycles on the apache configuration.

=cut

#----------------------------------------------------------------------

use constant {
    get_prereq => ['LocalConfig'],
};

#----------------------------------------------------------------------

=head1 METHODS

=head2 get_phase()

Phase 70 is done right before ZoneFile

=cut

sub get_phase {
    return 70;
}

=head2 get_summary()

Provide a summary to display in the UI

=cut

sub get_summary {
    my ($self) = @_;
    return [ $self->_locale()->maketext('This module installs the web server configuration and restarts the web server.') ];
}

=head2 get_restricted_available()

Determines if restricted restore mode is available

=cut

sub get_restricted_available {
    return 1;
}

*restricted_restore = \&unrestricted_restore;

=head2 unrestricted_restore()

Only intended to be called by the transfer restore system.

=cut

sub unrestricted_restore {
    my ($self) = @_;

    my $user = $self->newuser();

    $self->start_action('Refreshing vhosts and restarting apache');
    Cpanel::ServerTasks::queue_task( ['ApacheTasks'], 'update_or_create_users_vhosts ' . $user );

    return 1;
}

1;
