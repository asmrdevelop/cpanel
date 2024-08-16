package Cpanel::MysqlUtils::Logs;

# cpanel - Cpanel/MysqlUtils/Logs.pm               Copyright 2022 cPanel, L.L.C.
#                                                           All rights reserved.
# copyright@cpanel.net                                         http://cpanel.net
# This code is subject to the cPanel license. Unauthorized copying is prohibited

use strict;
use warnings;

use Cpanel::LoadModule      ();
use Cpanel::MysqlUtils::Dir ();
use Cpanel::Sys::Hostname   ();

sub get_mysql_error_log_file {
    Cpanel::LoadModule::load_perl_module('Cpanel::MysqlUtils::MyCnf::Full');
    my $mycnf = Cpanel::MysqlUtils::MyCnf::Full::etc_my_cnf();
    if ( $mycnf->{'mysqld'} ) {
        if ( $mycnf->{'mysqld'}{'log-error'} ) {
            return $mycnf->{'mysqld'}{'log-error'};
        }
        elsif ( $mycnf->{'mysqld'}{'log_error'} ) {
            return $mycnf->{'mysqld'}{'log_error'};
        }
    }

    my $datadir = Cpanel::MysqlUtils::Dir::getmysqldir() || '';
    $datadir =~ s/\/$//;

    my $hostname      = Cpanel::Sys::Hostname::gethostname();
    my $shorthostname = Cpanel::Sys::Hostname::shorthostname();
    my %logs;

    foreach my $candidate ( "$datadir/$hostname.err", "$datadir/$shorthostname.err" ) {
        if ( my $mtime = ( stat($candidate) )[9] ) {
            $logs{$candidate} = $mtime;
        }
    }

    # If there are multiple logfile, return the newest one
    if ( scalar keys %logs ) {
        return ( sort { $logs{$b} <=> $logs{$a} } keys %logs )[0];
    }

    #cf. https://dev.mysql.com/doc/refman/5.5/en/error-log.html
    return "$datadir/$hostname.err";
}

1;
