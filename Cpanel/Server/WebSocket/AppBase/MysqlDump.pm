package Cpanel::Server::WebSocket::AppBase::MysqlDump;

# cpanel - Cpanel/Server/WebSocket/AppBase/MysqlDump.pm
#                                                  Copyright 2022 cPanel, L.L.C.
#                                                           All rights reserved.
# copyright@cpanel.net                                         http://cpanel.net
# This code is subject to the cPanel license. Unauthorized copying is prohibited

use cPstrict;

=encoding utf-8

=head1 NAME

Cpanel::Server::WebSocket::App::MysqlDump

=head1 DESCRIPTION

A cpsrvd WebSocket application that connects the caller with
the C<mysql> admin module’s streaming dump functions.

=head1 PARAMETERS

Given as form parameters in the HTTP query string. All are required:

=over

=item C<dbname> - The name of the MySQL database to dump.

=item C<character_set> - Either C<utf8mb4> or C<utf8>.

This option may, for legacy reasons, be given as C<encoding>. While
UTF-8 is an encoding, not a character set, in the context of MySQL
C<utf8mb4> and C<utf8> actually refer to two different character sets,
so C<character_set> is more proper here.

=item C<include_data> - Either 1 or 0.

=back

=head1 CLOSE STATUS

Normally the server, upon completion of the MySQL dump, will close the
connection with WebSocket status 1000 (success) or 1011 (failure).

If, though, the dump failed due to a MySQL collation error, the server
will close the connection with WebSocket status B<4000>. This is an
instruction to the client to repeat the dump using a different C<character_set>;
the most common use case is, after C<utf8mb4> having failed, to fall back
to C<utf8>.

=cut

#----------------------------------------------------------------------

use Cpanel::Exception                   ();
use Cpanel::HTTP::QueryString           ();
use Cpanel::MysqlUtils::Dump::WebSocket ();

use Whostmgr::Transfers::Systems::Mysql::Stream::Constants ();

use parent qw(
  Cpanel::Server::WebSocket::AppBase::Streamer
);

use constant {
    _FRAME_CLASS => 'Net::WebSocket::Frame::binary',

    # One day should be enough to back up a MySQL DB … right??
    TIMEOUT => 86400,

    _EXIT_CODE_TO_INDICATE_COLLATION_ERR => 100,

    # One of this module’s intended consumers is the transfer system,
    # which ferries the input from this stream directly into MySQL.
    # Sometimes MySQL can take several minutes to process a single
    # statement. When that happens, the receiver often stops accepting
    # new WebSocket frames, even pings.
    #
    _MAX_PINGS => int( Whostmgr::Transfers::Systems::Mysql::Stream::Constants::MYSQL_QUERY_TIMEOUT / __PACKAGE__->_HEARTBEAT_TIMEOUT() ),
};

use constant _charsets => qw( utf8  utf8mb4 );

=head1 METHODS

=head2 I<CLASS>->run( $COURIER )

Instantiates the class. $COURIER is an instance of
L<Cpanel::Server::WebSocket::Courier>.

=cut

sub run {
    my ( $self, $courier ) = @_;

    return $self->SUPER::run(
        $courier,
        get_exit_code_for_error => \&_err2exit,
        @{ $self->{'_streamer_args'} },
    );
}

#----------------------------------------------------------------------

sub _nonexistent_db_error ( $self, $dbname ) {
    return Cpanel::Exception::create_raw( 'cpsrvd::BadRequest', "Unrecognized “dbname” ($dbname)" );
}

sub _verify_and_parse_query_string ($self) {

    # TODO: Refactor existing WebSocket modules so that the handler
    # does this query string parsing, and the modules just receive
    # that parse.
    my $query_hr = Cpanel::HTTP::QueryString::parse_query_string_sr( \$ENV{'QUERY_STRING'} );

    $query_hr->{'character_set'} //= delete $query_hr->{'encoding'};

    my @missing = grep { !length $query_hr->{$_} } qw( dbname character_set include_data );

    if (@missing) {
        die Cpanel::Exception::create_raw( 'cpsrvd::BadRequest', "Missing: @missing" );
    }

    if ( !grep { $_ eq $query_hr->{'character_set'} } _charsets() ) {
        my @can_be = _charsets();
        die Cpanel::Exception::create_raw( 'cpsrvd::BadRequest', "Invalid “character_set” ($query_hr->{'character_set'}); must be one of: @can_be" );
    }

    return $query_hr;
}

sub _CHILD_ERROR_TO_WEBSOCKET_CLOSE {
    my ( $self, $child_err ) = @_;

    my $streamer = $self->get_attr('streamer');
    my $reason   = $streamer->get_error_id();

    my $code;

    if ( ( $child_err >> 8 ) == _EXIT_CODE_TO_INDICATE_COLLATION_ERR() ) {
        $code = Cpanel::MysqlUtils::Dump::WebSocket::COLLATION_ERROR_CLOSE_STATUS();
    }

    return ( $code, $reason );
}

sub _err2exit {
    my ($err) = @_;

    if ( ref($err) && ( ref $err )->isa('Cpanel::Exception::Database::MysqlIllegalCollations') ) {
        return _EXIT_CODE_TO_INDICATE_COLLATION_ERR();
    }

    return undef;
}

1;
