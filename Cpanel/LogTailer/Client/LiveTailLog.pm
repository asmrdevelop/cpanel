package Cpanel::LogTailer::Client::LiveTailLog;

# cpanel - Cpanel/LogTailer/Client/LiveTailLog.pm  Copyright 2022 cPanel, L.L.C.
#                                                           All rights reserved.
# copyright@cpanel.net                                         http://cpanel.net
# This code is subject to the cPanel license. Unauthorized copying is prohibited

use strict;

use Cpanel::Exception         ();
use Cpanel::Rand::Get         ();
use Cpanel::HTTP::QueryString ();
use Cpanel::Services::Ports   ();

use Whostmgr::Authz::Header ();

use parent qw( Cpanel::LogTailer::Client );

use Try::Tiny;

our $TIME_TO_SLEEP_BETWEEN_RETRY = 5;

# our for tests
our @required_args = qw(
  session_id system_id log_file_data max_concurrent_stream_failures use_ssl host output_obj http_client whmuser
);

=head1 NAME

Cpanel::LogTailer::Client::LiveTailLog

=head1 DESCRIPTION

A client class used for streaming and processing data from the LiveTailLog cgi module.

=head1 METHODS

=head2 new

=head3 Purpose

    Creates a Cpanel::LogTailer::Client::LiveTailLog object.

=head3 Arguments

    session_id    - The ID of the session to be streamed by LiveTailLog
    system_id     - The ID of the system which the log was generated from. Currently can be 'pkgacct' and 'transfers'.
    log_file_data - A hashref of log file data used to track the current position in the log stream. It looks like:
                    {
                        filename => {
                            file_number   => An integer number used to associate the log position with the file name
                                             on the query string to the live tail log cgi.
                            file_position => An integer value of the summed bytes of each message payload length. This
                                             is used to track the stream's current position in the log file.
                        }
                    }
    use_ssl       - A boolean value indicating if the client should use SSL to connect to the live tail log cgi.
    host          - The domain name of the server to connect to to stream the log from.
    whmuser       - The WHM username to use when authenticating to the remote cpsrvd to stream the log.
    output_obj    - An object of type Cpanel::Output used to output information and errors to.
    http_client   - An object of type HTTP::Tiny used to connect to the remote server to stream the log.
    whmpass       - An optional argument used to authenticate to the remote cpsrvd to stream the log.
                    If this value is not present then accesshash_pass must be specified.
    accesshash_pass - An optional argument used to authenticate to the remote cpsrvd to stream the log.
                      If this value is not present then whmpass must be specified.

    max_concurrent_stream_failures - The maximum amount of concurrent stream failures before the stream module stops
                                     trying to get data from the remote machine.
    max_total_stream_failures      - Optional. The maximum amount of total failures before the stream module stops trying to get
                                     data from the remote machine. A value of 0 is unlimited and is the default if not passed.

=head3 Exceptions

    Cpanel::Exception::MissingParameter - Thrown if any of the required parameters (or neither of the optional ones) are supplied.

=head3 Returns

    A Cpanel::LogTailer::Client::LiveTailLog object

=cut

sub new {
    my ( $class, %OPTS ) = @_;

    my $self = bless {}, $class;

    for my $arg (@required_args) {
        die Cpanel::Exception::create( 'MissingParameter', [ name => $arg ] ) if !defined $OPTS{$arg};
        $self->{$arg} = $OPTS{$arg};
    }

    $self->{authz_header} = Whostmgr::Authz::Header::get_authorization_header(%OPTS);

    $self->{max_total_stream_failures} = defined $OPTS{max_total_stream_failures} ? $OPTS{max_total_stream_failures} : 0;

    $self->{_line_separator}        = "\n";
    $self->{_line_separator_offset} = length( $self->{_line_separator} );

    return $self;
}

=head2 read_log_stream

=head3 Purpose

    Reads and processes the log stream from the remote machine's live tail log cgi.

=head3 Arguments

    message_processor_cr - A coderef called on every validly formatted line in the streamed log data.
                           This receives an array of args:
                               The filename that contained the current log data.
                               The length in bytes of the JSON payload.
                               The JSON payload
    log_parser_cr        - A coderef called on every invalidly-formatted line that is not the termination
                           sequence. This function just receives the entire invalidly-formatted line.
                           If you would like to call the log_parser_cr on every line, call it from your
                           message_processor_cr as well.

=head3 Exceptions

    Cpanel::Exception::MissingParameter - Thrown if any of the parameters are missing.

=head3 Returns

    1 - if the stream ended via termination sequence parsing
    0 - if the stream ended via an error or the max concurrent stream failures was hit

=cut

sub read_log_stream {
    my ( $self, %OPTS ) = @_;

    for my $arg (qw( log_parser_cr message_processor_cr )) {
        die Cpanel::Exception::create( 'MissingParameter', [ name => $arg ] ) if !$OPTS{$arg};
    }

    my $termination_integer = _get_termination_integer();
    my $sentinel_data       = {
        termination_sequence           => $self->_get_termination_sequence($termination_integer),
        termination_seen               => 0,
        concurrent_log_stream_failures => 0,
        total_log_stream_failures      => 0,
    };

    $self->set_sentinel_data($sentinel_data);

    my $response;

    # We want to keep going until we see the termination from live_tail_log, our process gets killed by the transfer session processor,
    # we get too many concurrent failures in a row (Server might have gone down), or we hit the total number of allowed failures if set.
    # The concurrent failures will be reset if we get good data.
    #
    # Note: The remote system will send the termination sequence twice to work around an IE bug.  We only need to look for it once
    # since we are not IE
    while ( !$sentinel_data->{termination_seen} && !$self->_hit_max_failures() ) {

        my $url = $self->_get_request_url($termination_integer);

        $response = $self->{http_client}->request(
            'GET', $url,
            {
                headers => {
                    Authorization => $self->{authz_header},
                },
                data_callback => sub {
                    my ( $content_chunk, $chunk_response ) = @_;

                    $self->_process_chunked_response(
                        {
                            content_chunk  => $content_chunk,
                            chunk_response => $chunk_response,
                            ( map { $_ => $OPTS{$_} } qw( log_parser_cr message_processor_cr ) ),
                        }
                    );

                    return;
                },
            },
        );

        if ( defined $response->{status} && $response->{status} >= 200 && $response->{status} < 300 ) {

            $sentinel_data->{concurrent_log_stream_failures} = 0;
        }
        else {
            if ( $response->{status} == 599 && _content_has_remote_exception( $response->{content} ) ) {
                return 0;    # Abort or Skip
            }
            $self->{output_obj}->error( _format_message_for_output_obj( $response->{content} ) ) if defined $response->{content};
            $self->{output_obj}->warn( _format_message_for_output_obj( $self->_locale()->maketext(q{The system encountered a problem as it attempted to stream the log data from the remote server. It will try again …}) ) );
            $sentinel_data->{concurrent_log_stream_failures}++;
            $sentinel_data->{total_log_stream_failures}++;

            # Give the server a few seconds to be able to answer requests again. Maybe this should be longer?
            $self->_log_loop_sleep();
        }
    }

    return !$self->_hit_max_failures();
}

sub _process_chunked_response {
    my ( $self, $opts ) = @_;

    my ( $log_parser_cr, $message_processor_cr, $content_chunk ) = @{$opts}{qw( log_parser_cr message_processor_cr content_chunk )};
    my $sentinel_data = $self->get_sentinel_data();
    my $log_files     = $self->get_log_file_data();
    my $buffer_ref    = $self->get_buffer();

    $$buffer_ref .= $content_chunk;

    while ( ( my $separator_position = index( $$buffer_ref, $self->{'_line_separator'} ) ) > -1 ) {
        my $line = substr( $$buffer_ref, 0, $separator_position + $self->{'_line_separator_offset'}, '' );
        chomp($line);

        if ( $line eq $sentinel_data->{termination_sequence} ) {
            $sentinel_data->{termination_seen}++;
            last;
        }

        # All valid messages have at least 2 | in them
        # the messages look like
        # master.log|101|{"timestamp":"2015-11-17 12:22:19 -0600","pid":"18770","contents":"Done\n","type":"out","partial":0}
        if ( ( $line =~ tr/|// ) < 2 ) {

            # It's important to parse the line even if it isn't a validly formatted message for the protocol
            $log_parser_cr->($line);

            # Don't print on keep alives
            if ( $line ne '.' ) {
                $self->{output_obj}->warn( _format_message_for_output_obj( $self->_locale()->maketext( 'The system encountered an incorrectly-formatted log message: [_1]', $line ) ) );
            }
            next;
        }

        my ( $file_name, $message_bytes, $json_message ) = split( '\|', $line, 3 );

        # Process the bytes even if the below throws an exception. If it causes an exception once, it'll probably do it again
        # No sense in stopping execution if the processor has issues.
        $log_files->{$file_name}{file_position} += int($message_bytes);

        my $err;
        try {
            $message_processor_cr->( $file_name, $message_bytes, $json_message );
        }
        catch {
            # If we ever need to break out of this loop by throwing a special exception from the processor, we can catch and handle that here.
            # Right now though (11.54) there is no need for it.
            $err = $_;
        };

        if ($err) {
            $self->{output_obj}->error( _format_message_for_output_obj( $self->_locale()->maketext( 'The system encountered an error when it attempted to process the message “[_1]”: [_2]', $json_message, Cpanel::Exception::get_string($err) ) ) );
        }
    }

    # Check to see if we have a termination sequence in the buffer
    # Note: The remote system will send the termination sequence twice to work around an IE bug.  We only need to look for it once
    # since we are not IE
    if ( index( $$buffer_ref, $sentinel_data->{termination_sequence} ) > -1 ) {
        $sentinel_data->{termination_seen}++;
    }

    # If we had data to process this wasn't a stream failure so reset the count
    $sentinel_data->{concurrent_log_stream_failures} = 0;

    return;
}

sub _hit_max_failures {
    my ($self) = @_;

    my $sentinel_data = $self->get_sentinel_data();

    return 1 if $self->{max_total_stream_failures} && $sentinel_data->{total_log_stream_failures} >= $self->{max_total_stream_failures};
    return 1 if $sentinel_data->{concurrent_log_stream_failures} >= $self->{max_concurrent_stream_failures};

    return 0;
}

sub _get_termination_integer {
    my ($self) = @_;

    # No zero allowed to avoid a leading zero problem
    return Cpanel::Rand::Get::getranddata( 11, [ 1 .. 9 ] );
}

sub _get_termination_sequence {
    my ( $self, $termination_integer ) = @_;

    return "[tail_end:$termination_integer]";
}

sub _get_request_url {
    my ( $self, $termination_integer ) = @_;

    my $log_files    = $self->get_log_file_data();
    my $query_string = Cpanel::HTTP::QueryString::make_query_string(
        session_id          => $self->{session_id},
        system_id           => $self->{system_id},
        termination_integer => $termination_integer,
        map { 'log_file' . $log_files->{$_}{file_number} => $_, 'log_file_position' . $log_files->{$_}{file_number} => $log_files->{$_}{file_position} } keys %$log_files
    );

    return sprintf(
        '%s://%s:%s/cgi/live_tail_log.cgi?%s',
        ( $self->{use_ssl} ? 'https' : 'http' ),
        $self->{host},
        ( $self->{use_ssl} ? $Cpanel::Services::Ports::SERVICE{'whostmgrs'} : $Cpanel::Services::Ports::SERVICE{'whostmgr'} ),
        $query_string
    );
}

sub _log_loop_sleep {
    my ($self) = @_;

    sleep($TIME_TO_SLEEP_BETWEEN_RETRY);
    return;
}

sub _format_message_for_output_obj {
    my ($message) = @_;

    # This { msg => [$message] } format is the only way it'll output in the browser
    if ( ref $message ) {
        return { msg => [ ( $message->{timestamp} ? "[$message->{timestamp}] $message->{contents}" : $message->{contents} ) ] };
    }
    else {
        return { msg => [$message] };
    }
}

sub _content_has_remote_exception {
    my ($content) = @_;

    # Sadly HTTP::Tiny stringifies this so we must look
    # for the string
    if ( $content =~ m{Cpanel::Exception::Remote(?:Skip|Abort)} ) {
        return 1;
    }
    return 0;

}

1;
