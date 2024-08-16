package Cpanel::MysqlUtils::TempDir;

# cpanel - Cpanel/MysqlUtils/TempDir.pm            Copyright 2022 cPanel, L.L.C.
#                                                           All rights reserved.
# copyright@cpanel.net                                         http://cpanel.net
# This code is subject to the cPanel license. Unauthorized copying is prohibited

use strict;
use warnings;

use Cpanel::MysqlUtils::MyCnf::Basic ();
use Cpanel::MysqlUtils::Variables    ();
use Try::Tiny;

our $mysqltmpdir;    # must stay undefined

=encoding utf-8

=head1 NAME

Cpanel::MysqlUtils::TempDir - Obtain mysql's temp directory location

=head1 SYNOPSIS

    use Cpanel::MysqlUtils::TempDir;

    my $tmpdir = Cpanel::MysqlUtils::TempDir::get_mysql_tmp_dir();

=head2 get_mysql_tmp_dir()

Returns the temp directory that mysql/maria is using to
write temporary files.  If mysql is down, the system will
read the /etc/my.cnf or return the default value of /tmp.
Its important that this always return the best guess as we
use this to block upgrades when the temp directory is not
writable by mysql or full.

=cut

# All STDERR output must be suppressed
# from this function or mysql upgrades
# will fail.

sub get_mysql_tmp_dir {

    # TODO: Deduplicate logic between here and Cpanel::MysqlUtils::Dir.

    if ( defined $mysqltmpdir ) { return $mysqltmpdir; }

    return if Cpanel::MysqlUtils::MyCnf::Basic::is_remote_mysql();

    # warn() on anything but a connection error.
    $mysqltmpdir = try {
        Cpanel::MysqlUtils::Variables::get_mysql_variable('tmpdir');
    };

    if ( !$mysqltmpdir ) {
        require Cpanel::MysqlUtils::MyCnf::Full;
        my $mycnf = Cpanel::MysqlUtils::MyCnf::Full::etc_my_cnf();
        if ( $mycnf->{'mysqld'} ) {
            $mysqltmpdir = $mycnf->{'mysqld'}{'tmpdir'};
        }
    }

    $mysqltmpdir ||= '/tmp';

    # Resolve symlinks
    while ( -l $mysqltmpdir ) {
        require Cpanel::Readlink;
        $mysqltmpdir = Cpanel::Readlink::deep($mysqltmpdir);
    }

    return $mysqltmpdir;
}

1;
