package Cpanel::Security::Advisor::Assessors::Mysql;

# cpanel - Cpanel/Security/Advisor/Assessors/Mysql.pm
#                                                  Copyright 2022 cPanel, L.L.C.
#                                                           All rights reserved.
# copyright@cpanel.net                                         http://cpanel.net
# This code is subject to the cPanel license. Unauthorized copying is prohibited

use cPstrict;

use Cpanel::Database                 ();
use Cpanel::Hostname                 ();
use Cpanel::IP::Loopback             ();
use Cpanel::IP::Parse                ();
use Cpanel::IPv6::Has                ();
use Cpanel::MysqlUtils               ();
use Cpanel::MysqlUtils::MyCnf::Basic ();
use Cpanel::MysqlUtils::MyCnf::Full  ();
use Cpanel::SafeRun::Errors          ();
use Cpanel::LoadFile                 ();

use Try::Tiny;

eval { local $SIG{__DIE__}; require Cpanel::MysqlUtils::Connect; };

use base 'Cpanel::Security::Advisor::Assessors';

sub generate_advice {
    my ($self) = @_;

    eval { Cpanel::MysqlUtils::Connect::connect(); } if $INC{'Cpanel/MysqlUtils/Connect.pm'};

    if ( !$self->_sqlcmd('SELECT 1;') ) {
        $self->add_bad_advice(
            'key'        => 'Mysql_can_not_connect_to_mysql',
            'text'       => $self->_lh->maketext('Cannot connect to MySQL server.'),
            'suggestion' => $self->_lh->maketext(
                'Enable the [output,url,_1,MySQL database service,_2].',
                $self->base_path('scripts/srvmng'),
                { 'target' => '_blank' },
            ),

        );
        return;
    }

    $self->_check_for_db_test();
    $self->_check_for_anonymous_users();
    $self->_check_for_public_bind_address();
    $self->_check_for_eol_database();

    return 1;
}

sub _sqlcmd {
    my ( $self, $cmd ) = @_;
    return Cpanel::MysqlUtils::sqlcmd( $cmd, { quiet => 1 } );
}

sub _check_for_db_test {

    my $self = shift;

    my $exists = $self->_sqlcmd(qq{show databases like 'test'});

    if ( !$exists ) {
        $self->add_good_advice(
            'key'  => 'Mysql_test_database_does_not_exist',
            'text' => $self->_lh->maketext("[asis,MySQL] test database does not exist.")
        );
    }
    else {
        $self->add_bad_advice(
            'key'        => 'Mysql_test_database_exists',
            'text'       => $self->_lh->maketext("[asis,MySQL] test database exists."),
            'suggestion' => $self->_lh->maketext(
                'Numerous attacks exploit the [asis,MySQL] test database. To remove it, run “[_1]”.',
                "mysql -e 'drop database test'"
            ),
        );

    }

    return 1;
}

sub _check_for_eol_database ($self) {

    return if Cpanel::MysqlUtils::MyCnf::Basic::is_remote_mysql();

    my $is_eol;
    my $pretty_name;
    try {
        my $db = Cpanel::Database->new();
        $is_eol      = $db->is_eol;
        $pretty_name = $db->locale_version;
    }
    catch {
        # If we fail to get a database module, we can still get the database version.
        # These will be old versions like MariaDB 5.5 and will be eol.

        $is_eol = 1;
        my ( $db_type, $db_version ) = Cpanel::Database::get_vendor_and_version();
        if ( $db_type =~ /mysql/i ) {
            require Cpanel::Database::MySQL;
            $pretty_name = Cpanel::Database::MySQL::type();
        }
        elsif ( $db_type =~ /mariadb/i ) {
            require Cpanel::Database::MariaDB;
            $pretty_name = Cpanel::Database::MariaDB::type();
        }

        $pretty_name .= " $db_version";

    };

    if ($is_eol) {
        $self->add_bad_advice(
            'key'        => 'Mysql_using_eol_version',
            'text'       => $self->_lh->maketext( "[_1] reached [output,acronym,EOL,End of Life].", $pretty_name ),
            'suggestion' => "<ul>
                <li>" . $self->_lh->maketext('We strongly recommend that you use a version that is still supported upstream.') . "</li>
                <li>" . $self->_lh->maketext( 'If you continue to use [_1], you will be susceptible to existing bugs or security issues.', $pretty_name ) . "</li>
                </ul>" . $self->_lh->maketext(
                "Visit the [output,url,_1,MySQL/MariaDB Upgrade interface,_2] to upgrade to a supported version.",
                $self->base_path('scripts/mysqlupgrade'),
                { 'target' => '_blank' },
            ),
        );
    }
    else {
        $self->add_good_advice(
            'key'  => 'Mysql_using_eol_version',
            'text' => $self->_lh->maketext("The system is running a supported database."),
        );
    }

    return 1;
}

sub _check_for_anonymous_users {
    my $self = shift;

    my $ok  = 1;
    my $ano = $self->_sqlcmd(qq{select 1 from mysql.user where user="" limit 1});
    if ($ano) {
        $ok = 0;
    }

    for my $h ( 'localhost', Cpanel::Hostname::gethostname() ) {
        eval {
            my $grant = $self->_sqlcmd(qq{SHOW GRANTS FOR ''\@'$h'});
            $ok = 0 if $grant;
        };
    }

    if ($ok) {
        $self->add_good_advice(
            'key'  => 'Mysql_no_anonymous_users',
            'text' => $self->_lh->maketext("[asis,MySQL] check for anonymous users")
        );
    }
    else {
        $self->add_bad_advice(
            'key'        => 'Mysql_found_anonymous_users',
            'text'       => $self->_lh->maketext("You have some anonymous [asis,MySQL] users"),
            'suggestion' => $self->_lh->maketext( 'Remove [asis,MySQL] anonymous [asis,MySQL] users: [_1]', "mysql -e \"DELETE FROM mysql.user WHERE User=''; FLUSH PRIVILEGES;\"" )
        );
    }

    return 1;
}

sub _check_for_public_bind_address {
    my $self = shift;

    my $mycnf        = Cpanel::MysqlUtils::MyCnf::Full::etc_my_cnf();
    my $bind_address = $mycnf->{'mysqld'}->{'bind-address'};
    my $port         = $mycnf->{'mysqld'}->{'port'} || '3306';

    my @deny_rules   = grep { /--dport \Q$port\E/ && /-j (DROP|REJECT)/ } split /\n/, Cpanel::SafeRun::Errors::saferunnoerror( '/sbin/iptables',  '--list-rules' );
    my @deny_rules_6 = grep { /--dport \Q$port\E/ && /-j (DROP|REJECT)/ } split /\n/, Cpanel::SafeRun::Errors::saferunnoerror( '/sbin/ip6tables', '--list-rules' );

    # From: http://dev.mysql.com/doc/refman/5.5/en/server-options.html
    # The server treats different types of addresses as follows:
    #
    # If the address is *, the server accepts TCP/IP connections on all server
    # host IPv6 and IPv4 interfaces if the server host supports IPv6, or accepts
    # TCP/IP connections on all IPv4 addresses otherwise. Use this address to
    # permit both IPv4 and IPv6 connections on all server interfaces. This value
    # is permitted (and is the default) as of MySQL 5.6.6.
    #
    # If the address is 0.0.0.0, the server accepts TCP/IP connections on all
    # server host IPv4 interfaces. This is the default before MySQL 5.6.6.
    #
    # If the address is ::, the server accepts TCP/IP connections on all server
    # host IPv4 and IPv6 interfaces.
    #
    # If the address is an IPv4-mapped address, the server accepts TCP/IP
    # connections for that address, in either IPv4 or IPv6 format. For example,
    # if the server is bound to ::ffff:127.0.0.1, clients can connect using
    # --host=127.0.0.1 or --host=::ffff:127.0.0.1.
    #
    # If the address is a “regular” IPv4 or IPv6 address (such as 127.0.0.1 or
    # ::1), the server accepts TCP/IP connections only for that IPv4 or IPv6
    # address.

    if ( defined($bind_address) ) {
        my $version = ( Cpanel::IP::Parse::parse($bind_address) )[0];

        if ( Cpanel::IP::Loopback::is_loopback($bind_address) ) {
            $self->add_good_advice(
                'key'  => 'Mysql_listening_only_to_local_address',
                'text' => $self->_lh->maketext("MySQL is listening only on a local address.")
            );
        }
        elsif ( ( ( $version == 4 ) && @deny_rules && ( ( $bind_address =~ /ffff/i ) ? @deny_rules_6 : 1 ) ) || ( ( $version == 6 ) && @deny_rules_6 ) || csf_blocks_mysql_port() ) {
            $self->add_good_advice(
                'key'  => 'Mysql_port_blocked_by_firewall_1',
                'text' => $self->_lh->maketext("The MySQL port is blocked by the firewall, effectively allowing only local connections.")
            );
        }
        else {
            $self->add_bad_advice(
                'key'        => 'Mysql_listening_on_public_address',
                'text'       => $self->_lh->maketext( "The MySQL service is currently configured to listen on a public address: (bind-address=[_1])", $bind_address ),
                'suggestion' => $self->_lh->maketext(
                    "Configure bind-address=127.0.0.1 in /etc/my.cnf or use the server’s firewall to restrict access to TCP port “[_1]”.",
                    $port
                ),
            );
        }
    }
    else {
        if ( ( @deny_rules && ( !Cpanel::IPv6::Has::system_has_ipv6() || @deny_rules_6 ) ) || csf_blocks_mysql_port() ) {
            $self->add_good_advice(
                'key'  => 'Mysql_port_blocked_by_firewall_2',
                'text' => $self->_lh->maketext("The MySQL port is blocked by the firewall, effectively allowing only local connections.")
            );
        }
        else {
            $self->add_bad_advice(
                'key'        => 'Mysql_listening_on_all_interfaces',
                'text'       => $self->_lh->maketext('The MySQL service is currently configured to listen on all interfaces: (bind-address=*)'),
                'suggestion' => $self->_lh->maketext(
                    "Configure bind-address=127.0.0.1 in /etc/my.cnf or use the server’s firewall to restrict access to TCP port “[_1]”.",
                    $port
                ),
            );
        }
    }

    return 1;
}

sub csf_blocks_mysql_port {
    my $conf = Cpanel::LoadFile::load_if_exists('/etc/csf/csf.conf');
    return 0 if !$conf;

    my $dbport = Cpanel::MysqlUtils::MyCnf::Basic::getmydbport('root') || 3306;
    foreach my $line ( split( "\n", $conf ) ) {
        next unless $line =~ m{\s*TCP_IN\s*=\s*['"](.+)['"]};
        my %ports = map { ( $_ => 1 ) } split( qr/\s*,\s*/, "$1" );
        return $ports{$dbport} ? 0 : 1;
    }

    return 1;
}

1;
