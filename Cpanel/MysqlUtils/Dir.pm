package Cpanel::MysqlUtils::Dir;

# cpanel - Cpanel/MysqlUtils/Dir.pm                Copyright 2022 cPanel, L.L.C.
#                                                           All rights reserved.
# copyright@cpanel.net                                         http://cpanel.net
# This code is subject to the cPanel license. Unauthorized copying is prohibited

use strict;
use warnings;

use Cpanel::Debug                    ();
use Cpanel::Mysql::Constants         ();
use Cpanel::MysqlUtils::MyCnf::Basic ();
use Cpanel::MysqlUtils::Variables    ();
use Cpanel::Readlink                 ();
use Try::Tiny;

our $mysqldatadir;    # must stay undefined

# Moved from Cpanel::MysqlUtils to reduce memory

# All STDERR output must be suppressed
# from this function or mysql upgrades
# will fail.
sub getmysqldir {

    # TODO: Deduplicate logic between here and Cpanel::MysqlUtils::TempDir.

    if ( defined $mysqldatadir ) { return $mysqldatadir; }

    if ( $> == 0 ) {
        return if Cpanel::MysqlUtils::MyCnf::Basic::is_remote_mysql();

        # warn() on anything but a connection error.
        $mysqldatadir = try {
            Cpanel::MysqlUtils::Variables::get_mysql_variable('datadir');
        };

        if ( !$mysqldatadir ) {
            require Cpanel::MysqlUtils::MyCnf::Full;

            my $mycnf = Cpanel::MysqlUtils::MyCnf::Full::etc_my_cnf();
            if ( $mycnf->{'mysqld'} ) {
                $mysqldatadir = $mycnf->{'mysqld'}{'datadir'};
            }
        }
    }
    else {
        try {
            require Cpanel::MysqlUtils::TempEnv;
            my ( $host, $user, $pw ) = Cpanel::MysqlUtils::TempEnv::get_parameters();

            require Cpanel::DBI::Mysql;
            my $dbh = Cpanel::DBI::Mysql->connect(
                {
                    host     => $host,
                    Username => $user,
                    Password => $host,
                }
            );

            ($mysqldatadir) = $dbh->selectrow_array('SELECT @@datadir');
        };
    }

    if ( !$mysqldatadir ) {
        if ( -d Cpanel::Mysql::Constants::DEFAULT()->{'datadir'} ) {
            $mysqldatadir = Cpanel::Mysql::Constants::DEFAULT()->{'datadir'};
        }
        elsif ( -d '/var/db/mysql' ) {
            $mysqldatadir = '/var/db/mysql';    # Default for no cost devil mascot
        }
        else {
            require Cpanel::PwCache;
            $mysqldatadir = Cpanel::PwCache::gethomedir('mysql');
        }
        if ( !$mysqldatadir ) {
            Cpanel::Debug::log_warn('Failed to determine MySQL data directory. Please check the MySQL installation.');
            return;
        }
    }

    # Resolve symlinks, if any.
    $mysqldatadir = Cpanel::Readlink::deep($mysqldatadir);

    return $mysqldatadir;
}

1;
