package Install::UninstallCpanelMonitoringPackages;    ## no critic (RequireFilenameMatchesPackage)

# cpanel - install/UninstallCpanelMonitoringPackages.pm         Copyright 2023 cPanel, L.L.C.
#                                                               All rights reserved.
# copyright@cpanel.net                                          http://cpanel.net
# This code is subject to the cPanel license. Unauthorized copying is prohibited

use parent qw( Cpanel::Task );

use Cpanel::ServerTasks ();

use cPstrict;

our $VERSION = '1.0';

=head1 DESCRIPTION

    Remove the 'cpanel-monitoring-*' packages.

=over 1

=item Type: Sanity

=item Frequency: once

=item EOL: never

=back

=cut

exit __PACKAGE__->runtask() unless caller;

sub new {
    my $proto = shift;
    my $self  = $proto->SUPER::new;

    $self->set_internal_name('uninstall_cpanel_monitoring_packages');
    $self->add_dependencies(qw( taskqueue ));

    return $self;
}

sub perform {
    my $self = shift;

    my $ret = $self->do_once(
        version => '114_uninstall_cpanel_monitoring_packages',
        eol     => 'never',
        code    => sub {
            Cpanel::ServerTasks::queue_task( ['MaintenanceTasks'], 'uninstall_cpanel_monitoring_packages' );
            return 1;
        },
    );

    return $ret;
}

1;
