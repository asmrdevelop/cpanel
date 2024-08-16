package Cpanel::Server::WebSocket::cpanel::MysqlDump;

# cpanel - Cpanel/Server/WebSocket/cpanel/MysqlDump.pm
#                                                  Copyright 2022 cPanel, L.L.C.
#                                                           All rights reserved.
# copyright@cpanel.net                                         http://cpanel.net
# This code is subject to the cPanel license. Unauthorized copying is prohibited

use cPstrict;

#----------------------------------------------------------------------

use parent qw(
  Cpanel::Server::WebSocket::AppBase::MysqlDump
  Cpanel::Server::WebSocket::cpanel
);

use Cpanel::DB::Map::Reader ();

use constant {
    _STREAMER => 'Cpanel::Streamer::Admin',
};

use constant _fn => {
    '1 utf8'    => 'STREAM_DUMP_DATA_UTF8',
    '1 utf8mb4' => 'STREAM_DUMP_DATA_UTF8MB4',
    ' utf8'     => 'STREAM_DUMP_NODATA_UTF8',
    ' utf8mb4'  => 'STREAM_DUMP_NODATA_UTF8MB4',
};

use constant _ACCEPTED_FEATURES => ('mysql');

#----------------------------------------------------------------------

=head1 METHODS

=head2 I<CLASS>->new( $SERVER_OBJ )

Instantiates the class. $SERVER_OBJ is an instance of
L<Cpanel::Server>.

=cut

sub new {
    my ( $class, $server_obj ) = @_;

    my $query_hr = $class->_verify_and_parse_query_string();

    my $dbname = $query_hr->{'dbname'};

    $query_hr->{'include_data'} = !!$query_hr->{'include_data'};

    my $fn = _fn()->{"@{$query_hr}{'include_data', 'character_set'}"};

    my $self = $class->SUPER::new();

    $self->{'_streamer_args'} = [
        admin_args => [ 'Cpanel', 'mysql', $fn, $dbname ],
    ];

    return $self;
}

#----------------------------------------------------------------------

sub _can_access ( $class, $server_obj ) {

    return $class->SUPER::_can_access($server_obj) && do {
        my $query_hr = $class->_verify_and_parse_query_string();

        $class->_verify_ownership_of_db( $server_obj, $query_hr->{'dbname'} );

        1;
    };
}

sub _verify_ownership_of_db ( $class, $server_obj, $dbname ) {

    my $rdr = Cpanel::DB::Map::Reader->new(
        cpuser => $server_obj->auth()->get_user(),
        engine => 'mysql',
    );

    if ( !$rdr->database_exists($dbname) ) {
        die $class->_nonexistent_db_error($dbname);
    }

    return;
}

1;
