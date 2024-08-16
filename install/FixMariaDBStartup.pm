package Install::FixMariaDBStartup;

# cpanel - install/FixMariaDBStartup.pm            Copyright 2022 cPanel, L.L.C.
#                                                           All rights reserved.
# copyright@cpanel.net                                         http://cpanel.net
# This code is subject to the cPanel license. Unauthorized copying is prohibited

use parent qw( Cpanel::Task );

use strict;
use warnings;

use Cpanel::OS                      ();
use Cpanel::MysqlUtils::ServiceName ();
use Cpanel::RestartSrv::Systemd     ();
use Cpanel::Services::Enabled       ();

our $VERSION = '1.0';

=head1 DESCRIPTION

    This task runs if it is detected that MariaDB has
    been started from a SysV style init script instead
    of via a systemd service.

=over 1

=item Type: Sanity

=item Frequency: always

=item EOL: never

=back

=cut

exit __PACKAGE__->runtask() unless caller;

sub new {
    my $proto = shift;
    my $self  = $proto->SUPER::new;

    $self->set_internal_name('fixmariadbstartup');

    return $self;
}

sub perform {
    my $self = shift;

    # Do not attempt to fix any issues here during initial system installation
    return 1 if $ENV{'CPANEL_BASE_INSTALL'};

    # The LSB init file exists when the issue observed in UPS-118 a.k.a MariaDB MDEV-10797 issue is present.
    # Though /etc/init.d is usually a symlink to /etc/init.d, the following path is where the MariaDB-server RPM installs the file.
    # Should cover the unlikely case where mariadb was installed without the symlink in place.
    # Previous attempts to use systemd service status to determine when this has been used has proven to be unreliable.
    return 1 unless -e '/etc/init.d/mysql';

    # Skip if system is not using systemd.
    return 1 unless Cpanel::OS::is_systemd();

    # Skip if the service has been intentionally disabled.
    return 1 unless Cpanel::Services::Enabled::is_enabled('mysql');

    # Skip if not explicitly using mariadb.
    return 1 unless Cpanel::MysqlUtils::ServiceName::get_installed_version_service_name() eq 'mariadb';

    # Skip unless the mariadb service state inidicates it is failed or stopped (not active, activating, or deactivating)
    my $mariadb_status = Cpanel::RestartSrv::Systemd::get_service_info_via_systemd('mariadb');
    return 1 unless ( $mariadb_status->{ActiveState} eq 'failed' || $mariadb_status->{ActiveState} eq 'inactive' );

    # MariaDB is either not running at all, or not correctly started.
    # Try a full shutdown and then restart it.
    print "Systemd is reporting that the MariaDB service is failed or inactive.\n";
    print "It may have been incorrectly started via /etc/init.d/mysql or /etc/init.d/mysql previously.\n";
    print "It is possible for systemd to get into a state where it believes the process to be inactive\n";
    print "when it is actually running.  If the process is killed or merely exits, systemd will crash.\n";
    print "If this is the case, running a systemd restart on the service will get systemd out of this state,\n";
    print "but it will appear that the systemd restart has failed.\n";
    print "Attempting restart via systemd in order to release running process without crashing systemd.\n";
    require Cpanel::SafeRun::Object;
    my $run = Cpanel::SafeRun::Object->new(
        'program'      => '/usr/bin/systemctl',
        'args'         => [ 'restart', 'mariadb.service' ],
        'timeout'      => 300,
        'read_timeout' => 300,
        stdout         => \*STDOUT,
        stderr         => \*STDERR,
    );
    warn $run->autopsy() if $run->CHILD_ERROR();
    print "Doing a safe MariaDB shutdown.\n";
    require Cpanel::MysqlUtils::Service;
    require Cpanel::Services::Restart;
    Cpanel::MysqlUtils::Service::safe_shutdown_local_mysql();
    print "Doing a MariaDB restart.\n";
    Cpanel::Services::Restart::restartservice('mysql');

    return 1;
}

1;

__END__
