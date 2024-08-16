package Cpanel::MysqlUtils::Dump::Root;

# cpanel - Cpanel/MysqlUtils/Dump/Root.pm          Copyright 2022 cPanel, L.L.C.
#                                                           All rights reserved.
# copyright@cpanel.net                                         http://cpanel.net
# This code is subject to the cPanel license. Unauthorized copying is prohibited

use strict;
use warnings;

=encoding utf-8

=head1 NAME

Cpanel::MysqlUtils::Dump::Root

=head1 DESCRIPTION

This module implements L<Cpanel::MysqlUtils::Dump::Data>’s interface
for doing MySQL dumps as root.

=cut

#----------------------------------------------------------------------

use parent qw( Cpanel::MysqlUtils::Dump::Data );

use Cpanel::MysqlUtils::Dump ();

#----------------------------------------------------------------------

sub _stream_utf8mb4 {
    my ( $class, $out_fh, $dbname ) = @_;

    Cpanel::MysqlUtils::Dump::stream_database_data_utf8mb4( $out_fh, $dbname );

    return;
}

sub _stream_utf8 {
    my ( $class, $out_fh, $dbname ) = @_;

    Cpanel::MysqlUtils::Dump::stream_database_data_utf8( $out_fh, $dbname );

    return;
}

sub _stream_utf8mb4_nodata {
    my ( $class, $out_fh, $dbname ) = @_;

    Cpanel::MysqlUtils::Dump::stream_database_nodata_utf8mb4( $out_fh, $dbname );

    return;
}

sub _stream_utf8_nodata {
    my ( $class, $out_fh, $dbname ) = @_;

    Cpanel::MysqlUtils::Dump::stream_database_nodata_utf8( $out_fh, $dbname );

    return;
}

sub _repair {
    my ( $class, $dbname ) = @_;

    require Cpanel::Mysql;
    my $mysql = Cpanel::Mysql->new(
        { ERRORS_TO_STDOUT => 0 },
    );

    $mysql->repair_database($dbname);

    return;
}

1;
