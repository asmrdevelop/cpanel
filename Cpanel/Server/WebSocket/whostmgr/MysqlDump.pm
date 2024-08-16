package Cpanel::Server::WebSocket::whostmgr::MysqlDump;

# cpanel - Cpanel/Server/WebSocket/whostmgr/MysqlDump.pm
#                                                  Copyright 2022 cPanel, L.L.C.
#                                                           All rights reserved.
# copyright@cpanel.net                                         http://cpanel.net
# This code is subject to the cPanel license. Unauthorized copying is prohibited

use cPstrict;

=encoding utf-8

=head1 NAME

Cpanel::Server::WebSocket::whostmgr::MysqlDump

=head1 DESCRIPTION

A L<Cpanel::MysqlUtils::Dump> WebSocket interface for WHM.

This module exposes the same WebSocket interface (i.e., requires the same
parameters) as L<Cpanel::Server::WebSocket::cpanel::MysqlDump>, but unlike
that module, this module requires root-level WHM access, and it will stream
the contents of B<any> MySQL database, even a database that no cPanel user
owns.

(If it’s desirable, functionality could be implemented to allow non-root
resellers to stream their users’ databases, but for now that doesn’t
exist.)

=cut

#----------------------------------------------------------------------

use parent qw(
  Cpanel::Server::WebSocket::AppBase::MysqlDump
  Cpanel::Server::WebSocket::whostmgr
);

use Cpanel::MysqlUtils::Connect ();

use constant {
    _STREAMER => 'Cpanel::Streamer::MysqlDump',
};

use constant _mode => {
    '1 utf8'    => 'stream_database_data_utf8',
    '1 utf8mb4' => 'stream_database_data_utf8mb4',
    ' utf8'     => 'stream_database_nodata_utf8',
    ' utf8mb4'  => 'stream_database_nodata_utf8mb4',
};

#----------------------------------------------------------------------

=head1 METHODS

=head2 I<CLASS>->new( $SERVER_OBJ )

Instantiates the class. $SERVER_OBJ is an instance of
L<Cpanel::Server>.

=cut

sub new ( $class, $server_obj ) {

    my $query_hr = $class->_verify_and_parse_query_string();

    my $dbname = $query_hr->{'dbname'};

    $query_hr->{'include_data'} = !!$query_hr->{'include_data'};

    my $mode = _mode()->{"@{$query_hr}{'include_data', 'character_set'}"};

    my $self = $class->SUPER::new();

    $self->{'_streamer_args'} = [
        dbname => $dbname,
        mode   => $mode,
    ];

    return $self;
}

#----------------------------------------------------------------------

sub _can_access ( $class, $server_obj ) {
    return 0 if !$class->SUPER::_can_access($server_obj);

    my $query_hr = $class->_verify_and_parse_query_string();

    my $dbname = $query_hr->{'dbname'};

    $class->_verify_db_exists($dbname);

    return 1;
}

sub _verify_db_exists ( $class, $dbname ) {
    my $dbh = Cpanel::MysqlUtils::Connect::get_dbi_handle();

    if ( !$dbh->db_exists($dbname) ) {
        die $class->_nonexistent_db_error($dbname);
    }

    return;
}

1;
