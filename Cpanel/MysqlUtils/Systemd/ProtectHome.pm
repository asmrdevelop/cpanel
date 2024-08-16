package Cpanel::MysqlUtils::Systemd::ProtectHome;

# cpanel - Cpanel/MysqlUtils/Systemd/ProtectHome.pm
#                                                  Copyright 2022 cPanel, L.L.C.
#                                                           All rights reserved.
# copyright@cpanel.net                                         http://cpanel.net
# This code is subject to the cPanel license. Unauthorized copying is prohibited

use strict;
use warnings;

use Cpanel::Autodie             ();
use Cpanel::Config::LoadCpConf  ();
use Cpanel::FileUtils::Write    ();
use Cpanel::MysqlUtils::Compat  ();
use Cpanel::MysqlUtils::Systemd ();

=encoding utf-8

=head1 NAME

Cpanel::MysqlUtils::Systemd::ProtectHome

=head1 SYNOPSIS

use Cpanel::MysqlUtils::Systemd::ProtectHome ();
Cpanel::MysqlUtils::Systemd::ProtectHome::set_unset_protecthome_if_needed();

=head1 DESCRIPTION

This module is used to enable read-only mode for ProtectHome in the systemd
unit file for either MySQL or MariaDB.

=head1 FUNCTIONS

=cut

use constant TICKS_IN_DAY => 86_400;    # 60**2*24

*_reload_and_restart = *Cpanel::MysqlUtils::Systemd::reload_and_restart;

=head2 set_unset_protecthome_if_needed name( [$cp_conf_ref] )

This function sets or unsets the systemd configuration option 'ProtectHome=read-only'
for the MySQL or MariaDB service. It does so via a configuration file that is
put in the service systemd drop-in path.

=head3 Arguments

=over 4

=item cp_conf_ref    - HASHREF - An optional hashref of the cPanel configuration

=back

=head3 Returns

This function returns 1 if successful, 0 if not needed for the MySQL version, or dies.

=head3 Exceptions

Throws an exception if there is an error writing/removing the file.
Throws an exception if MySQL/MariaDB has problems restarting.

=cut

sub set_unset_protecthome_if_needed {
    my ($cp_conf_ref) = @_;

    return 0 if !Cpanel::MysqlUtils::Compat::apply_limits_to_systemd_unit();

    $cp_conf_ref ||= Cpanel::Config::LoadCpConf::loadcpconf();

    my $drop_in_path = Cpanel::MysqlUtils::Systemd::get_systemd_drop_in_dir();
    my $conf_path    = "$drop_in_path/protecthome.conf";

    my $need_reload_restart;
    if ( $cp_conf_ref->{jailapache} ) {
        $need_reload_restart = _check_conf_and_emit_if_needed($conf_path);
    }
    else {
        $need_reload_restart = Cpanel::Autodie::unlink_if_exists($conf_path);
    }

    if ($need_reload_restart) {
        _reload_and_restart();
    }

    return 1;
}

sub _check_conf_and_emit_if_needed {
    my ($conf_path) = @_;

    # A race is possible here, but unlikely hopefully
    if ( ( -e $conf_path ) && ( my $mtime = ( stat _ )[9] ) ) {

        # Only overwrite the file once a day at most
        return 0 if ( ( _time() - $mtime ) < TICKS_IN_DAY );
    }

    # This does a rename into place
    Cpanel::FileUtils::Write::overwrite( $conf_path, _get_conf_body(), 0644 );

    return 1;
}

# mocked in tests
sub _time {
    return time();
}

# More Info: http://man7.org/linux/man-pages/man5/systemd.exec.5.html
sub _get_conf_body {
    return <<'END';
[Service]
ProtectHome=read-only
END
}

1;
