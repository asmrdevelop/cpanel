package Cpanel::MysqlUtils::Dump::User;

# cpanel - Cpanel/MysqlUtils/Dump/User.pm          Copyright 2022 cPanel, L.L.C.
#                                                           All rights reserved.
# copyright@cpanel.net                                         http://cpanel.net
# This code is subject to the cPanel license. Unauthorized copying is prohibited

use strict;
use warnings;

=encoding utf-8

=head1 NAME

Cpanel::MysqlUtils::Dump::User

=head1 DESCRIPTION

This module implements L<Cpanel::MysqlUtils::Dump::Data>’s interface
for doing MySQL dumps as an unprivileged user.

=cut

#----------------------------------------------------------------------

use parent qw( Cpanel::MysqlUtils::Dump::Data );

use Cpanel::AdminBin::Call ();

#----------------------------------------------------------------------
# This module’s tests verify these functions directly.

sub _stream_utf8mb4 {
    my ( $class, $out_fh, $dbname ) = @_;

    return _stream_admin( 'STREAM_DUMP_DATA_UTF8MB4', $out_fh, $dbname );
}

sub _stream_utf8 {
    my ( $class, $out_fh, $dbname ) = @_;

    return _stream_admin( 'STREAM_DUMP_DATA_UTF8', $out_fh, $dbname );
}

sub _stream_utf8mb4_nodata {
    my ( $class, $out_fh, $dbname ) = @_;

    return _stream_admin( 'STREAM_DUMP_NODATA_UTF8MB4', $out_fh, $dbname );
}

sub _stream_utf8_nodata {
    my ( $class, $out_fh, $dbname ) = @_;

    return _stream_admin( 'STREAM_DUMP_NODATA_UTF8', $out_fh, $dbname );
}

sub _repair {
    my ( $class, $dbname ) = @_;

    Cpanel::AdminBin::Call::call( 'Cpanel', 'mysql', REPAIR_DATABASE => $dbname );

    return;
}

#----------------------------------------------------------------------

sub _stream_admin {
    my ( $fn, $out_fh, $dbname ) = @_;

    Cpanel::AdminBin::Call::stream( $out_fh, 'Cpanel', 'mysql', $fn, $dbname );

    return;
}

1;
