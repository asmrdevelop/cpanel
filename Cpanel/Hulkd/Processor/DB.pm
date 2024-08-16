package Cpanel::Hulkd::Processor::DB;

# cpanel - Cpanel/Hulkd/Processor/DB.pm            Copyright 2022 cPanel, L.L.C.
#                                                           All rights reserved.
# copyright@cpanel.net                                         http://cpanel.net
# This code is subject to the cPanel license. Unauthorized copying is prohibited

use strict;
use warnings;

=head1 NAME

Cpanel::Hulkd::Processor::DB - Handle database interactions for the cPHulk daemon.

=head1 SYNOPSIS

    use Cpanel::Hulk                 ();
    use Cpanel::Hulkd                ();
    use Cpanel::ForkAsync            ();

    my $hulk     = Cpanel::Hulkd->new();
    my $dbsocket = $hulk->_init_db_socket();

    # Start the db processor in a child processor.
    Cpanel::ForkAsync::do_in_child(
        sub {
            require Cpanel::Hulkd::Processor::DB;
            my $db_proc = Cpanel::Hulkd::Processor::DB->new($hulk);
            return $db_proc->run_loop($dbsocket);
        }
    );

    # Talk to the processor over the dbsocket
    my $client = Cpanel::Hulk->new();

    # Purge old logins
    $client->db_connect();
    $client->dbpurge_old_logins();

    # Write to the DB
    # DB operations are 'one-per-connection' so have to reconnect to the socket for each call
    $client->db_connect();
    $client->dbwrite($opts_hr);

    # Read from the DB
    # DB operations are 'one-per-connection' so have to reconnect to the socket for each call
    $client->db_connect();
    my $data = $client->dbread($opts_hr);

=head1 DESCRIPTION

This module encapsulates the logic to interact with the cPHulkd database via a unix socket.

=cut

use Try::Tiny;

use IO::Select          ();
use Cpanel::JSON        ();
use Cpanel::Exception   ();
use Cpanel::IP::Convert ();
use Cpanel::Net::Accept ();
use Socket              ();

use constant _MSG_NOSIGNAL => Socket::MSG_NOSIGNAL();

=head1 CLASS METHODS

=head2 new($hulkd_object)

Constructor.

=over 3

=item C<$hulkd_object> [in, required]

The C<Cpanel::Hulkd> object to associate the DB processor with.

=back

B<Returns>: On failure, throws an exception. On success, returns the new constructed object.

=cut

sub new {
    my ( $class, $hulkd_object ) = @_;

    die 'new requires a Cpanel::Hulkd object.' if !UNIVERSAL::isa( $hulkd_object, 'Cpanel::Hulkd' );

    return bless { 'hulkd' => $hulkd_object }, $class;
}

=head1 OBJECT METHODS

=head2 run_loop($dbsocket)

Initiates the run loop of the DB proccessor. Binds to the socket specified, and processes the requests.

=over 3

=item C<$dbsocket> [in, required]

The C<IO::Socket::UNIX> socket object to associate the DB processor with. Recognizes the following
commands:

=over 5

=item C<DBWRITE $JSON_STRING>

Write to the database using the parameters passed in the C<$JSON_STRING>. See C<_send_dbwrite_cmd> calls
in C<Cpanel::Hulkd::Processor> for examples.

=item C<DBREAD $JSON_STRING>

Read from the database using the parameters passed in the C<$JSON_STRING>. See C<_send_dbread_cmd> calls
in C<Cpanel::Hulkd::Processor> for examples.

=item C<PURGEOLDLOGINS>

Purge expired logins from the C<login_track> table in the database.

=back

Any unknown command will get an 'INVALID OP' response

=back

B<Returns>: Response from the operation invoked.

=cut

sub run_loop {
    my ( $self, $dbsocket ) = @_;

    local $SIG{'TERM'} = sub {
        $self->{'hulkd'}->mainlog("DB processor shutdown via SIGTERM with pid $$");
        exit 0;
    };
    local $SIG{'INT'} = 'IGNORE';
    local $SIG{'HUP'} = 'IGNORE';

    $self->_build_dbh();
    my $selector = IO::Select->new($dbsocket);

    while (1) {
        if ( my @ready_sockets = $selector->can_read( $self->{'hulkd'}->{'dormant_mode'}->idle_timeout() ) ) {
            foreach my $ready_socket (@ready_sockets) {

                # Prevent a single client from blocking all requests by doing a non-blocking accept()
                if ( Cpanel::Net::Accept::accept( $self->{'socket'}, $ready_socket ) ) {
                    try {
                        $self->_process_request();
                    }
                    catch {
                        my $err = Cpanel::Exception::get_string_no_id($_);
                        $self->{'hulkd'}->warn($err);
                    };
                }
            }
        }
    }
    return 1;
}

sub _build_dbh {
    my $self = shift;

    return 1 if $self->{'dbh'};

    require Cpanel::Hulk::Admin::DB;
    require DBD::SQLite;

    my ( $dbh, $err );
    try {
        $dbh = Cpanel::Hulk::Admin::DB::get_dbh(
            {
                'RaiseError'  => 0,
                'HandleError' => sub { $self->{'hulkd'}->warn(@_) },
            }
        );
    }
    catch {
        $err = Cpanel::Exception::get_string_no_id($_);
    };

    if ( $err || !$dbh ) {
        die Cpanel::Exception::create_raw( 'Database::ConnectError', "Failed to connect to cPHulk DB: $err" );
    }

    return $self->{'dbh'} = $dbh;
}

sub _process_request {
    my $self = shift;

    local $SIG{'ALRM'} = sub {
        die Cpanel::Exception::create_raw( 'Timeout', 'Timeout while serving DB request' );
    };
    $self->{'socket'}->send( qq{220 cPHulkd DB Ready.\r\n}, 0 );

    alarm 10;
    $self->{'hulkd'}->debug("processing DB request");
    while ( my $line = readline $self->{'socket'} ) {
        chomp($line);
        $self->{'hulkd'}->debug("Input Request: [$line]");
        if ( $line =~ m/^DBWRITE/ ) {
            $self->_handle_dbwrite( ( split( m{ }, $line, 2 ) )[-1] );
        }
        elsif ( $line =~ m/^DBREAD/ ) {
            $self->_handle_dbread( ( split( m{ }, $line, 2 ) )[-1] );
        }
        elsif ( $line =~ m/^PURGEOLDLOGINS/ ) {
            $self->_handle_purge_old_logins();
        }
        else {
            $self->_send_response_and_close( 300, 'INVALID DB OP' );
        }
        last;
    }
    alarm 0;

    return 1;
}

sub _handle_dbread {
    my ( $self, $dbread_json ) = @_;

    $self->{'hulkd'}->debug("handle dbread");
    my ( $input, $error_reason );
    try {
        $input = Cpanel::JSON::Load($dbread_json);
    }
    catch {
        $error_reason = "Failed to decode JSON data";
    };

    if ($error_reason) {
        $self->_send_response_and_close( 400, "Unable to decode json: $error_reason." );
        die "Unable to decode json: $error_reason";
    }
    elsif ( ref $input ne 'HASH' ) {
        $self->_send_response_and_close( 400, "Invalid json data." );
        die "Invalid json data.";
    }

    my $select_func = delete $input->{'select_func'};
    if ( $select_func !~ m/^(?:selectall_arrayref|selectcol_arrayref)$/ ) {
        $self->_send_response_and_close( 400, "Invalid DB operation specified." );
        die 'Invalid DB operation specified';
    }

    $self->{'hulkd'}->debug( "query: [$input->{'query'}] - params: [" . join( ' ', @{ $input->{'query_parameters'} } ) . "]" );
    _process_db_query_parameters( $input->{'query_parameters'} );

    my $data = $self->{'dbh'}->$select_func(
        $input->{'query'}, $input->{'extra_attr'},
        @{ $input->{'query_parameters'} },
    );

    $self->_send_response_and_close( 200, Cpanel::JSON::Dump($data) );

    return 1;
}

sub _handle_dbwrite {
    my ( $self, $dbwrite_json ) = @_;

    $self->{'hulkd'}->debug("handle dbwrite");
    my ( $input, $error_reason );
    try {
        $input = Cpanel::JSON::Load($dbwrite_json);
    }
    catch {
        $error_reason = "Failed to decode JSON data";
    };

    if ($error_reason) {
        $self->_send_response_and_close( 400, "Unable to decode json: $error_reason." );
        die "Unable to decode json: $error_reason";
    }
    elsif ( ref $input ne 'HASH' ) {
        $self->_send_response_and_close( 400, 'Invalid json data.' );
        die "Invalid json data.";
    }

    $self->{'hulkd'}->debug( "query: [$input->{'query'}] - params: [" . join( ' ', grep { defined } @{ $input->{'query_parameters'} } ) . "]" );

    _process_db_query_parameters( $input->{'query_parameters'} );

    $self->{'dbh'}->do(
        $input->{'query'}, {},
        @{ $input->{'query_parameters'} },
    );

    local $self->{'_ignore_write_failure'} = 1;
    $self->_send_response_and_close( 200, 'OK' );

    return 1;
}

sub _handle_purge_old_logins {
    my $self = shift;

    $self->{'hulkd'}->debug("handle dbpurge_old_logins");
    $self->{'dbh'}->do("DELETE FROM login_track WHERE EXPTIME <= DATETIME('now', 'localtime') /*purge_old_logins*/;");

    local $self->{'_ignore_write_failure'} = 1;
    $self->_send_response_and_close( 200, 'OK' );

    return 1;
}

# IP fields are sent in ARRAYREFs, and require additional processing,
# in order to convert the binary strings, which are JSON friendly,
# in to binary data for the DB queries
sub _process_db_query_parameters {
    my $query_parameters_ar = shift;

    foreach my $param ( @{$query_parameters_ar} ) {
        next if !ref $param;
        my $unpack = $param->[1] == 6 ? 'B128' : 'B32';
        $param = Cpanel::IP::Convert::ip2bin16( Cpanel::IP::Convert::binip_to_human_readable_ip( pack( $unpack, $param->[0] ) ) );
    }

    return 1;
}

sub _send_response_and_close {
    my ( $self, $code, $response ) = @_;

    $self->{'hulkd'}->debug("Response: $code $response");
    $self->_write( "$code $response\n", _MSG_NOSIGNAL );
    $self->{'socket'}->close;

    return 1;
}

sub _write {
    my ( $self, $msg, $flags ) = @_;

    $flags ||= 0;

    die "Refuse to send empty message!" if !length $msg;

    return send( $self->{'socket'}, $msg, $flags ) || do {
        if ( !$self->{'_ignore_write_failure'} ) {
            die Cpanel::Exception::create_raw( 'IO::SocketWriteError', "Failed to write to socket: $!" );
        }
    };
}

1;
