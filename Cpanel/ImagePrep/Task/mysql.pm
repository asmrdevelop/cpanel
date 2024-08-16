
# cpanel - Cpanel/ImagePrep/Task/mysql.pm          Copyright 2022 cPanel, L.L.C.
#                                                           All rights reserved.
# copyright@cpanel.net                                         http://cpanel.net
# This code is subject to the cPanel license. Unauthorized copying is prohibited

package Cpanel::ImagePrep::Task::mysql;

use cPstrict;

use parent 'Cpanel::ImagePrep::Task';
use Cpanel::Imports;
use Cpanel::Pkgr                ();
use Cpanel::MysqlUtils::Version ();
use Cpanel::JSON                ();
use Cpanel::LoadModule          ();
use Cpanel::Output::Callback    ();

use Try::Tiny;

use constant TEMP_MYSQL_VERSION_FILE => '/var/cpanel/.mysql-version.snapshot';                                                # This name can be changed in the future with no consequences
use constant DELETE_PACKAGES         => qw(mysql-community-server mysql-community-server-core mysql-server MariaDB-server);

=head1 NAME

Cpanel::ImagePrep::Task::mysql - An implementation subclass of Cpanel::ImagePrep::Task. See parent class for interface.

=head1 WARNING

This is a semi-destructive action in that it moves /var/lib/mysql to
a backup location and then reinitializes the database from nothing.
This means it's extremely important for this to remain a 'non-repair only'
task. Although the original data is not deleted, it would be highly
disruptive if it were allowed to run on active servers.

=cut

sub _description {
    return <<EOF;
Prepare MySQL or MariaDB for snapshotting, and restore it when an instance
launches. This replaces the main configuration file and the entire data
directory.
EOF
}

sub _type { return 'non-repair only' }

sub _pre {
    my ($self) = @_;

    my $exception;
    my ( $install_class, $version ) = try {
        _get_install_class_and_version();
    }
    catch {
        $exception = $_;
        ();
    };

    my $dbinfo;
    if ( $self->_check_installed() && $install_class && $version ) {

        $self->loginfo("install_class/version: Detected version. Saving $install_class, $version.");
        Cpanel::JSON::DumpFile( TEMP_MYSQL_VERSION_FILE, { install_class => $install_class, version => $version } );
    }
    elsif (
           -f TEMP_MYSQL_VERSION_FILE
        && ( $dbinfo = try { Cpanel::JSON::LoadFile(TEMP_MYSQL_VERSION_FILE) } )
        && $dbinfo->{install_class}
        && $dbinfo->{version}    #
    ) {
        $self->loginfo("install_class/version: Reusing existing saved info $dbinfo->{install_class}, $dbinfo->{version} from a previous run.");
    }
    else {
        $self->loginfo($exception) if $exception;
        die "install_class/version: Unable to load info.\n";
    }

    $self->common->_systemctl( 'stop', 'tailwatchd' );
    $self->_stop_mysql();

    for my $path (
        '/var/lib/mysql',
        '/root/.my.cnf',
        '/root/.mylogin.cnf',
        '/var/cpanel/mysql/remote_profiles/profiles.json',
    ) {
        $self->common->_rename_to_backup($path);
    }

    for (DELETE_PACKAGES) {
        $self->loginfo("Deleting any existing package named '$_' ...");
        Cpanel::Pkgr::remove_packages_nodeps($_);
    }

    return $self->PRE_POST_OK;
}

sub _post {
    my ($self) = @_;

    my $dbinfo = Cpanel::JSON::LoadFile(TEMP_MYSQL_VERSION_FILE);
    if ( !$dbinfo || !$dbinfo->{install_class} || !$dbinfo->{version} ) {
        die sprintf( "Unable to load MySQL version from %s\n", TEMP_MYSQL_VERSION_FILE );
    }
    $self->loginfo("Using $dbinfo->{install_class} to restore version $dbinfo->{version}. Installing ...");

    local $ENV{CPANEL_BASE_INSTALL} = 1;    # avoid chicken/egg issue with .my.cnf generation
    Cpanel::LoadModule::load_perl_module( $dbinfo->{install_class} );
    my $db_install = $dbinfo->{install_class}->new(
        output_obj => Cpanel::Output::Callback->new(
            on_render => sub {
                my ($msg_hr) = @_;
                my $msg = $msg_hr->{contents};

                # build_mysql_conf's normal mode of operation includes an intermediate error message before
                # configuration is complete, and allowing this to go to the terminal will confuse users of
                # the post_snapshot utility.
                if ( $msg_hr->{contents} =~ m{/usr/local/cpanel/bin/build_mysql_conf} ) {
                    return $self->loginfo('Suppressed output from build_mysql_conf.');
                }
                return $self->loginfo($msg);
            },
        )
    );

    $db_install->install_rpms( $dbinfo->{version} );                                 # Also does debs
    $self->_stop_mysql();
    $self->common->run_command('/usr/local/cpanel/bin/build_mysql_conf');
    $self->common->run_command('/usr/local/cpanel/scripts/mysqlconnectioncheck');    # No need to set need_restart because a service restart already occurs as part of mysqlconnectioncheck.
    $self->common->_unlink(TEMP_MYSQL_VERSION_FILE);

    return $self->PRE_POST_OK;
}

sub _stop_mysql {
    my ($self) = @_;
    my $stop_ok;
    for my $service (qw(mysqld mysql)) {                                             # these names also work for MariaDB
        try {
            $self->common->quiet->_systemctl( 'stop', $service );
            $stop_ok = 1;
        };
        last if $stop_ok;
    }
    $self->loginfo( $stop_ok ? 'Stopped MySQL.' : 'No MySQL service to stop.' );
    return;
}

# Compare to Cpanel::Database::get_vendor_and_version(), which has undesirable MySQL 5.7 fallback behavior
sub _get_install_class_and_version {
    Cpanel::MysqlUtils::Version::uncached_mysqlversion();    # Doesn't give us everything we want, but clears the cache
    my $version_info  = Cpanel::MysqlUtils::Version::current_mysql_version();
    my $install_class = $version_info->{full} =~ /mariadb/i ? 'Cpanel::MariaDB::Install' : 'Cpanel::Mysql::Install';
    my $version       = $version_info->{short};

    return ( $install_class, $version );
}

# For some versions of MariaDB, it's possible to manually uninstall the MariaDB-server package while still leaving
# the server running and answering version queries. We want a missing MySQL/MariaDB server to be a fatal error due to
# the ambiguity it creates about desired version (except in the case where that version has already been saved by a
# previous run of snapshot_prep), so we have to do an extra check here for the existence of mysqld/mariadbd.
sub _check_installed {
    my ($self) = @_;
    for my $daemon (qw(/usr/sbin/mysqld /usr/sbin/mariadbd)) {
        return 1 if $self->common->_exists($daemon);
    }
    $self->loginfo('Neither MySQL nor MariaDB appears to be installed, so we cannot retrieve the version from the server.');
    return 0;
}

1;
