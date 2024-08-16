package Cpanel::MysqlUtils::DirName;

# cpanel - Cpanel/MysqlUtils/DirName.pm            Copyright 2022 cPanel, L.L.C.
#                                                           All rights reserved.
# copyright@cpanel.net                                         http://cpanel.net
# This code is subject to the cPanel license. Unauthorized copying is prohibited

use strict;
use warnings;

=encoding utf-8

=head1 NAME

Cpanel::MysqlUtils::DirName - Tools for converting database names to directory names and back

=head1 SYNOPSIS

    use Cpanel::MysqlUtils::DirName ();

    my $dir = Cpanel::MysqlUtils::DirName::database_to_dir('blue_wp1-1');
    my $dbname = Cpanel::MysqlUtils::DirName::dir_to_database('blue_wp1@002d1');

=head2 database_to_dir($database)

Convert a database name into the directory name in the MySQL data directory
which contains that database.

This function handles only ASCII names, since we only allow printable ASCII
characters in database names.

=cut

sub database_to_dir {
    my ($database) = @_;
    $database =~ s/(\W)/sprintf "@%04x", ord($1)/ge;
    return $database;
}

=head2 dir_to_database($dir)

Convert the name of a directory in the MySQL data directory to the name of the
database which it contains.

This function handles only ASCII names, since we only allow printable ASCII
characters in database names.

=cut

sub dir_to_database {
    my ($dir) = @_;
    $dir =~ s/@([0-9a-f]{4})/chr(hex($1))/ge;
    return $dir;
}

1;
