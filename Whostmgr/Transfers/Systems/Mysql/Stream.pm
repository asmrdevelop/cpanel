package Whostmgr::Transfers::Systems::Mysql::Stream;

# cpanel - Whostmgr/Transfers/Systems/Mysql/Stream.pm
#                                                  Copyright 2022 cPanel, L.L.C.
#                                                           All rights reserved.
# copyright@cpanel.net                                         http://cpanel.net
# This code is subject to the cPanel license. Unauthorized copying is prohibited

use cPstrict;

=encoding utf-8

=head1 NAME

Whostmgr::Transfers::Systems::Mysql::Stream - streaming for MySQL restores

=head1 DESCRIPTION

This module implements the bulk of the logic for restoring a MySQL database
via WebSocket streaming.

=head1 TODO

Deduplicate some of the logic between this module and
L<Cpanel::Server::WebSocket::AppBase::Streamer>.

=cut

#----------------------------------------------------------------------

use Cpanel::Imports;

use Mojo::IOLoop         ();
use Mojo::IOLoop::Stream ();
use Mojo::UserAgent      ();
use Mojo::WebSocket      ();

use Cpanel::Finally                     ();
use Cpanel::FHUtils::Blocking           ();
use Cpanel::HTTP::QueryString           ();
use Cpanel::MysqlUtils::Dump::WebSocket ();
use Cpanel::Services::Ports             ();
use Cpanel::Time::Split                 ();

use Whostmgr::Transfers::Systems::Mysql::Stream::Constants ();

use constant {
    DEBUG => 0,

    _PRINT_STATUS_INTERVAL => 15,

    # Sometimes MySQL takes several minutes to execute a single statement.
    # When that happens our read buffer fills up, which prevents us from
    # reading anything off the WebSocket connection. When that happens,
    # Mojolicious’s inactivity timeout can kick in.
    _INACTIVITY_TIMEOUT => Whostmgr::Transfers::Systems::Mysql::Stream::Constants::MYSQL_QUERY_TIMEOUT,

    _KEEPALIVE_TIMEOUT => 60,
};

# This has to be small enough that we don’t block the WebSocket connection
# for long enough that the sender will have sent enough unanswered pings to
# drop the connection.
our $_WRITE_BUFFER_LIMIT = 5 * 1024 * 1024;

my $_MAX_ATTEMPTS = 2;

# For testing
our $ON_BACKPRESSURE;

our $TEST_MOJO_APP;

#----------------------------------------------------------------------

=head1 FUNCTIONS

=head2 restore_plain( %OPTS )

Restores the MySQL data via the “plain” method. (As of this writing, that’s
the only method.) This implements logic to examine the WebSocket close
status of each MySQL dump and handle errors, including collation fallback.

%OPTS are:

=over

=item * C<host> - The hostname or IP address from which to stream the
MySQL dump.

=item * C<api_token> - The API token to use.

=item * C<api_token_username> - The username to send with the API token.

=item * C<api_token_application> - The application (C<cpanel> or C<whm>)
to send with the API token.

=item * C<old_db_name> - The name of the MySQL database to stream.

=item * C<output_obj> - A L<Cpanel::Output> instance that will receive
messages during the stream.

=item * C<import_cr> - A callback that implements the MySQL import.
It receives the following named parameters:

=over

=item * C<sql_fh> - The filehandle from which to read the MySQL dump.

=item * C<stream_cr> - A callback that populates the buffer from which
C<sql_fh> reads. It receives no arguments.

=item * C<before_read_cr> - A callback that runs prior to reading from
C<sql_fh>. It receives no arguments.

=back

The C<import_cr> callback should return two scalars: a boolean to indicate
success/failure, and the reason (if any) for failure.

B<IMPORTANT:> C<stream_cr> expects to run in the current process, which
is a different one from the logic that reads C<sql_fh> (and runs
C<before_read_cr>). That could change theoretically, but for now this is
how it works.

=back

=cut

sub restore_plain (%opts) {
    _validate_restore_plain_opts( \%opts );

    my $api_token     = $opts{'api_token'};
    my $old_username  = $opts{'api_token_username'};
    my $api_token_app = $opts{'api_token_application'};

    my @at_end;

    my $cpsrvd_port = _get_restore_plain_url_port( \%opts );

    my $authty = "$opts{'host'}:$cpsrvd_port";
    my $url    = "wss://$authty/websocket/MysqlDump";

    my @charsets_left = qw( utf8mb4  utf8 );

    my $final_error;

    my $output_obj = $opts{'output_obj'};
    _validate_output_obj_interface($output_obj);

  ENCODING:
    while ( my $charset = shift @charsets_left ) {
        my %config = (
            dbname        => $opts{'old_db_name'},
            character_set => $charset,
            include_data  => 1,
        );

        my $query = Cpanel::HTTP::QueryString::make_query_string( \%config );

        my $full_url = "$url?$query";

        # Ends of a pipe. We recreate the pipe on each attempt. (See below.)
        my ( $sql_r, $sql_w );

        my $try_next_charset;

        my $websocket_cr = sub {
            close $sql_r;

            my @at_end = Cpanel::Finally->new( sub { close $sql_w } );

            my $ua = _create_and_configure_mojo_useragent();

            my $stream_to_sql = _create_and_configure_sql_stream($sql_w);

            $stream_to_sql->on(
                error => sub ( $self, $error ) {
                    $final_error = "Failed to write to DBI subprocess: $error";
                    Mojo::IOLoop->stop();
                },
            );

            my $bytes_received_count = 0;

            my $on_binary = _create_binary_handler( $ua, $stream_to_sql, \$bytes_received_count );

            $ua->websocket(
                $full_url,
                {
                    Authorization              => "$api_token_app $old_username:$api_token",
                    'Sec-WebSocket-Extensions' => 'permessage-deflate',
                },
                sub ( $ua, $tx ) {

                    $stream_to_sql->start();

                    if ( $tx->is_websocket ) {

                        $output_obj->out( locale()->maketext( 'The [asis,WebSocket] handshake succeeded: [_1]', $full_url ) );

                        my $keepalive_timer_id = _start_keepalive_timer($tx);

                        my $progress_timer_sr = _start_progress_timer( $output_obj, \$bytes_received_count );

                        $tx->on(
                            finish => sub ( $tx, $code, $reason = undef ) {
                                Mojo::IOLoop->remove($$progress_timer_sr);
                                Mojo::IOLoop->remove($keepalive_timer_id);

                                if ( $code == 1000 ) {
                                    $output_obj->out( locale()->maketext('The remote [asis,MySQL] dump ended successfully.') );
                                    $stream_to_sql->close_gracefully();
                                }
                                else {
                                    if ( ( $code == Cpanel::MysqlUtils::Dump::WebSocket::COLLATION_ERROR_CLOSE_STATUS() ) && @charsets_left ) {
                                        $output_obj->warn( locale()->maketext( 'The remote [asis,MySQL] dump failed because of a collation error. The system will retry with the “[_1]” character set.', $charsets_left[0] ) );

                                        $try_next_charset = 1;
                                    }
                                    else {
                                        my $txt = "WebSocket $code";
                                        $txt .= ", $reason" if length $reason;

                                        $final_error = locale()->maketext( 'The remote [asis,MySQL] dump failed because of an error ([_1]).', $txt );
                                    }

                                    $stream_to_sql->close();
                                }
                            }
                        );

                        $tx->on(
                            text => sub {
                                die "Payload must be binary, not text!";
                            }
                        );

                        $tx->on( binary => $on_binary );
                    }
                    else {
                        $final_error = _handle_ws_handshake_failure( $output_obj, $full_url, $tx );

                        $stream_to_sql->close();
                    }
                },
            );

            Mojo::IOLoop->start();

            close $sql_w or warn "close write: $!";
        };

        # If we get an unexpected error, retry the import.
        my $cur_encoding_attempts = 0;

        while ( $cur_encoding_attempts < $_MAX_ATTEMPTS ) {
            pipe( $sql_r, $sql_w ) or die "pipe(): $!";

            Cpanel::FHUtils::Blocking::set_non_blocking($_) for ( $sql_r, $sql_w );

            $cur_encoding_attempts++;

            if ( $cur_encoding_attempts > 1 ) {
                $output_obj->out( locale()->maketext('Retrying …') );
            }

            my ( $ok, $err ) = $opts{'import_cr'}->(
                sql_fh         => $sql_r,
                stream_cr      => $websocket_cr,
                before_read_cr => sub {
                    close $sql_w;
                },
            );

            # The only “expected” error, for now, is a collation error.
            # If that happens we *don’t* want to retry the current charset.
            next ENCODING if $try_next_charset;

            if ( !$ok ) {
                my $err_phrase = locale()->maketext( 'The system failed to restore the “[_1]” database because of an error: [_2]', $opts{'old_db_name'}, $err );

                if ( $cur_encoding_attempts < $_MAX_ATTEMPTS ) {
                    $output_obj->warn($err_phrase);
                }
                else {
                    $output_obj->error($err_phrase);
                }

                next;
            }

            # If there’s no error and no need to try another charset,
            # then we’re done!
            last if !$final_error;
        }

        # At this point we’ve either failed or succeeded.
        # There’s no need to try another encoding.
        last ENCODING;
    }

    return $final_error ? ( 0, $final_error ) : 1;
}

# Previously we sent in an output_obj that lacked an error() method.
# This prevents a recurrence of that.
#
sub _validate_output_obj_interface ($output_obj) {
    my @needs = ( 'out', 'warn', 'error' );
    my @lack  = grep { !$output_obj->can($_) } @needs;

    die "Output obj lacks: @lack" if @lack;

    return;
}

sub _handle_ws_handshake_failure ( $output_obj, $full_url, $tx ) {
    $output_obj->warn( $tx->res()->to_string() );

    if ( my $err = $tx->error() ) {
        return locale()->maketext( 'The [asis,WebSocket] handshake failed because of an error: [_1]', $err->{'message'} );
    }

    # This really shouldn’t happen; it means
    # we got a normal HTTP handshake rather than
    # WebSocket.
    return "Unexpected non-error response ($full_url)!";
}

sub _create_and_configure_mojo_useragent() {
    my $ua = Mojo::UserAgent->new();
    $ua->inactivity_timeout( _INACTIVITY_TIMEOUT() );

    if ($TEST_MOJO_APP) {
        $ua->server->app($TEST_MOJO_APP);
    }

    # For now assume that invalid TLS is OK.
    $ua->insecure(1);

    $ua->on(
        error => sub ( $ua, $err ) {
            warn "Mojo::UserAgent ERROR: $err";
        }
    );

    return $ua;
}

sub _create_and_configure_sql_stream ($sql_w) {

    # This has to exist outside of the WebSocket logic
    # so that its DESTROY doesn’t preempt a close_gracefully().
    my $stream_to_sql = Mojo::IOLoop::Stream->new($sql_w);

    # M::I::Stream’s default timeout is 15s, which means if the
    # write buffer fills up we only give MySQL 15 seconds to
    # clear it out. Let’s just disable this timeout.
    $stream_to_sql->timeout(0);

    $stream_to_sql->on(
        close => sub ($self) {
            DEBUG && print "=== WS closed; stopping I/O loop\n";
            Mojo::IOLoop->stop();
        }
    );

    return $stream_to_sql;
}

sub _validate_restore_plain_opts ($opts_hr) {
    my @missing = sort grep { !$opts_hr->{$_} } (
        'api_token',
        'api_token_username',
        'api_token_application',
        'host',
        'old_db_name',
        'output_obj',
        'import_cr',
    );
    die "missing: @missing" if @missing;

    return;
}

sub _get_restore_plain_url_port ($opts_hr) {
    my $api_token_app = $opts_hr->{'api_token_application'};

    if ( $api_token_app eq 'whm' ) {
        return $Cpanel::Services::Ports::SERVICE{'whostmgrs'};
    }
    elsif ( $api_token_app eq 'cpanel' ) {
        return $Cpanel::Services::Ports::SERVICE{'cpanels'};
    }

    die "Bad API token application: “$api_token_app”";
}

sub _start_progress_timer ( $output_obj, $bytes_restored_sr ) {
    my $start_time = time();
    my $next_at    = $start_time;

    my $id;

    my $print_status_cr = sub {
        if ( my $elapsed = $next_at - $start_time ) {
            my $elapsed_str = Cpanel::Time::Split::seconds_to_elapsed($elapsed);

            $output_obj->out( locale()->maketext( '[format_bytes,_1] received ([_2])', $$bytes_restored_sr, $elapsed_str ) );
        }

        $next_at += _PRINT_STATUS_INTERVAL();

        $id = Mojo::IOLoop->timer( $next_at - time(), __SUB__ );
    };

    $print_status_cr->();

    return \$id;
}

sub _start_keepalive_timer ($tx) {

    # MySQL sometimes takes quite a while--an hour or more--to create
    # indexes. During this time there generally is no traffic across the
    # TCP connection, which can cause some routers to drop the connection.
    # To avoid that, we send a WebSocket PONG frame periodically. Thus,
    # there will be traffic across the wire, and (unlike with TCP
    # keep-alive) the router won’t know that the traffic is a keep-alive,
    # so it’ll have no incentive to consider the connection to be stale.
    # Thus, we avoid the dropped connections.
    #
    return Mojo::IOLoop->recurring(
        _KEEPALIVE_TIMEOUT() => sub {
            $tx->send( [ 1, 0, 0, 0, Mojo::WebSocket::WS_PONG, 'keep-alive' ] );
        },
    );
}

sub _create_binary_handler ( $ua, $stream_to_sql, $bytes_received_sr ) {    ## no critic qw(ManyArgs)
    return sub ( $tx, $buffer ) {
        $$bytes_received_sr += length $buffer;

        $stream_to_sql->write($buffer);

        # Keep an eye on the write buffer. If we receive WebSocket
        # messages faster than the “import_cr” callback can
        # consume them, we could spool indefinitely and eventually
        # run out of memory. To prevent that, if the write buffer
        # exceeds a set limit, then stop reading WebSocket messages
        # long enough to allow “import_cr” to empty out the buffer.
        if ( $stream_to_sql->bytes_waiting() > $_WRITE_BUFFER_LIMIT ) {

            DEBUG && print STDERR "=== write buffer full; turning off WS reads\n";
            $ON_BACKPRESSURE->() if $ON_BACKPRESSURE;

            my $id        = $tx->connection();
            my $ws_stream = Mojo::IOLoop->stream($id);

            $ws_stream->stop();

            # Disable the WebSocket inactivity timeout
            # since we’re waiting on our MySQL restore logic,
            # which may take a bit.
            my $saved_timeout = $ua->inactivity_timeout();
            $ua->inactivity_timeout(0);

            $stream_to_sql->once(
                drain => sub {

                    DEBUG && print STDERR "=== write buffer empty; resuming WS reads\n";

                    $ws_stream->start();
                    $ua->inactivity_timeout($saved_timeout);
                }
            );
        }
    };
}

1;
