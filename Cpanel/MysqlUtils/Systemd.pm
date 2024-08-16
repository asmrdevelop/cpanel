package Cpanel::MysqlUtils::Systemd;

# cpanel - Cpanel/MysqlUtils/Systemd.pm            Copyright 2022 cPanel, L.L.C.
#                                                           All rights reserved.
# copyright@cpanel.net                                         http://cpanel.net
# This code is subject to the cPanel license. Unauthorized copying is prohibited

use strict;
use warnings;

use Cpanel::LoadModule         ();
use Cpanel::MysqlUtils::Compat ();
use Cpanel::OS                 ();

=encoding utf-8

=head1 NAME

Cpanel::MysqlUtils::Systemd

=head1 SYNOPSIS

use Cpanel::MysqlUtils::Systemd ();
my $drop_in_path = Cpanel::MysqlUtils::Systemd::get_systemd_drop_in_dir();
Cpanel::FileUtils::Write::overwrite("$drop_in_path/custom.conf", $additional_custom_systemd_options, 0600);
Cpanel::MysqlUtils::Systemd::reload_and_restart();

=head1 DESCRIPTION

This module is used to hold some MySQL/MariaDB specific interactions with systemd.

=head1 FUNCTIONS

=cut

our $SYSTEMD_DROPIN_PATH = '/etc/systemd/system';

# convenience
*is_systemd = sub { Cpanel::OS::is_systemd() };

=head2 get_systemd_drop_in_dir ()

This function assembles and returns the path where systemd drop in configuration
files should be placed for the MySQL/MariaDB service.

=head3 Returns

The path of the systemd drop-in configuration files should be placed for the
currently installed MySQL/MariaDB instance.

=cut

sub get_systemd_drop_in_dir {

    # mysql (MySQL < 5.7 & MariaDB 10.0), mariadb (MariaDB 10.1+), or mysqld (MySQL 5.7)
    my $systemd_service_name = Cpanel::MysqlUtils::Compat::get_systemd_service_name();
    return "$SYSTEMD_DROPIN_PATH/$systemd_service_name.service.d";
}

=head2 reload_and_restart()

This function performs a daemon-reload on systemctl and then attempts to
restart the MySQL/MariaDB service.

=head3 Returns

This function returns 1 or dies.

=head3 Exceptions

This function throws a C<Cpanel::Exception::RestartFailed> exception if MySQL fails to restart.

=cut

sub reload_and_restart {

    _reload_systemctl();

    require Cpanel::Services::Restart;

    my $do_not_background = 1;
    Cpanel::Services::Restart::restartservice( 'mysql', $do_not_background ) or do {
        Cpanel::LoadModule::load_perl_module('Cpanel::Exception');
        Cpanel::LoadModule::load_perl_module('Cpanel::Services::Log');
        my ( $log_exists, $log ) = Cpanel::Services::Log::fetch_service_startup_log('mysql');
        die Cpanel::Exception::create(
            'RestartFailed',
            'The system failed to restart [asis,MySQL] because of an error: [_1]',
            [$log]
        );
    };

    return 1;
}

sub _reload_systemctl {
    system( '/usr/bin/systemctl', 'daemon-reload' );
    return;
}

1;
