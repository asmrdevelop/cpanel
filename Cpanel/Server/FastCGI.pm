package Cpanel::Server::FastCGI;

# cpanel - Cpanel/Server/FastCGI.pm                Copyright 2022 cPanel, L.L.C.
#                                                           All rights reserved.
# copyright@cpanel.net                                         http://cpanel.net
# This code is subject to the cPanel license. Unauthorized copying is prohibited

use strict;

our $MAX_ATTEMPTS = 3;

use bytes;
use Errno                            qw[EINTR];
use Cpanel::Buffer                   ();
use Cpanel::Alarm                    ();
use Net::FastCGI::Constant           qw( :common :type :role :flag :protocol_status );
use Net::FastCGI::Protocol           ();
use Cpanel::CPAN::Net::FastCGI::Fast ();
use Cpanel::CPAN::Net::FastCGI::IO   ();
use Cpanel::Socket::UNIX::Micro      ();
use Cpanel::Socket::Constants        ();
use Cpanel::Server::Constants        ();

my $MAX_CONNECT_ATTEMPTS = 3;

=encoding UTF-8

=head1 DESCRIPTION

Implements a FastCGI responder as defined by
http://www.fastcgi.com/devkit/doc/fcgi-spec.html#S6.2

=head1 SYNOPSIS

    use Cpanel::Server::FastCGI ();

    my $socket  = IO::Socket::UNIX->new($socket_path);
    my $logger  = Cpanel::Logger->new();
    my $fastcgi = Cpanel::Server::FastCGI->new(
        'record_id'           => 1,
        'logger'              => $logger,
        'fastcgi_socket'      => $socket,
        'http_client_socket'    => $input_fh,
    );

    local $@;
    eval {
      $ENV{'GATEWAY_INTERFACE'} = 'CGI/1.1';
      $ENV{'....'} = '...';
      $fastcgi->begin_request();
      my $output = '';
      while ( $fastcgi->read( $output, 32768, length $output ) ) {

      }
    };

    ...HANDLE $@

    fastcgi->close();
    if ($? == 0) {
        .. HANDLE FAILURE
    }

=head1 DESCRIPTION

=head2 new

=head3 Purpose

Create a Cpanel::Server::FastCGI object

=head3 Arguments

=head4 Required

=over

=item 'logger': Cpanel::Logger object

=item 'fastcgi_socket': IO::Socket::UNIX object - The socket that is connected to the fastcgi server

=item 'http_client_socket': IO::Socket::* object - The socket that is connected to the http client

=back

=head4 Optional

=over

=item 'record_id': integer - A unique record id that has not yet been passed to the provided fastcgi_socket

=back

=head3 Returns

=over

=item A Cpanel::Server::FastCGI object

=back

If an error occurs, the function will throw an exception.

=cut

sub new {
    my ( $class, %OPTS ) = @_;

    # Require logger here because we hope to use this for cpdavd in the future
    foreach my $param (qw(http_client_socket logger fastcgi_socket_path)) {
        if ( !defined $OPTS{$param} ) {
            require Cpanel::Exception;
            die Cpanel::Exception::create( 'MissingParameter', [ 'name' => $param ] );
        }
    }

    return bless {
        '_fastcgi_socket'      => undef,
        '_fastcgi_socket_path' => $OPTS{'fastcgi_socket_path'},
        '_http_client_socket'  => $OPTS{'http_client_socket'},
        '_logger'              => $OPTS{'logger'},
        '_record_id'           => $OPTS{'record_id'} || 0,
        '_stdout_buffer'       => '',
      },
      $class;
}

=head1 DESCRIPTION

=head2 begin_request

=head3 Purpose

Begin a new fastcgi request, and send \%ENV.

=head3 Arguments

=head4 Required

=over

=item '$bytes_left_to_read': The number of bytes to read from the http client's socket

=back

If an error occurs, the function will throw an exception.

=cut

sub _connect_socket {
    my ($self) = @_;

    {
        my ( $eval_err, $os_err );

        # Try 3 times in case we get EINTR
        if ( !$self->{'_fastcgi_socket'} || !fileno $self->{'_fastcgi_socket'} ) {
            for ( 1 .. $MAX_CONNECT_ATTEMPTS ) {
                local $@;
                local $!;
                socket( $self->{'_fastcgi_socket'}, $Cpanel::Socket::Constants::AF_UNIX, $Cpanel::Socket::Constants::SOCK_STREAM, $Cpanel::Socket::Constants::PROTO_IP ) or die "Failed to create socket: $!";
                my $connect_ok = eval { connect( $self->{'_fastcgi_socket'}, Cpanel::Socket::UNIX::Micro::micro_sockaddr_un( $self->{'_fastcgi_socket_path'} ) ); };
                $eval_err = $@;
                $os_err   = $!;
                if ( $connect_ok && !$eval_err && $self->{'_fastcgi_socket'} && fileno $self->{'_fastcgi_socket'} ) {
                    $self->{'_fastcgi_socket'}->autoflush(1);
                    last;
                }
                else {
                    delete $self->{'_fastcgi_socket'};
                }
            }
        }
        if ( !$self->{'_fastcgi_socket'} ) {
            if ($eval_err) {
                $@ = $eval_err;
                die;
            }
            else {
                die "The system failed to connect to: “$self->{'_fastcgi_socket_path'}”: $os_err";
            }
        }
    }

    return 1;
}

sub begin_request {
    my ( $self, $bytes_left_to_read ) = @_;

    $self->{'_request_is_active'} = 1;
    $self->{'_eof'}               = 0;

    $self->_connect_socket();

    # We try to reconnect if our connection to the FCGI server was closed
    # because it timed out waiting for us to send another request.  This
    # only happens when the HTTP Keepalive timeout is longer then the FCGI
    # server timeout. We should never try to reconnect more than once
    # because the problem is likely to be something more sinister on
    # subsequent attempts
    foreach my $attempt ( 1 .. $MAX_ATTEMPTS ) {
        $self->{'_record_id'}++;
        local $@;

        if ( $self->{'_fastcgi_socket'} && fileno( $self->{'_fastcgi_socket'} ) ) {
            last
              if eval {
                $self->_write_to_fastcgi_socket( Net::FastCGI::Protocol::build_record( FCGI_BEGIN_REQUEST, $self->{'_record_id'}, Net::FastCGI::Protocol::build_begin_request_body( FCGI_RESPONDER, FCGI_KEEP_CONN ) )
                      . Net::FastCGI::Protocol::build_record( FCGI_PARAMS, $self->{'_record_id'}, Cpanel::CPAN::Net::FastCGI::Fast::build_params( \%ENV ) )
                      . Net::FastCGI::Protocol::build_record( FCGI_PARAMS, $self->{'_record_id'}, '' )
                      . ( !$bytes_left_to_read ? Net::FastCGI::Protocol::build_record( FCGI_STDIN, $self->{'_record_id'}, '' ) : '' ) );

                # Fastcgi requires an empty record at the end to tell
                # we have completed sending the request
              };
        }

        if ( $attempt == $MAX_ATTEMPTS ) {
            $self->{'_eof'} = 1;

            # We could not recover so we re-throw the exception
            die;    # "die;" without any arguemnts re-throws $@ if set
        }

        # Auto reconnect:
        # The fastcgi server may have closed our connection
        # due to timeout when waiting for another request because the client
        # has been idle but the connection to the client is still open due to
        # HTTP Keep-Alive.
        #
        # Since we do not get a notice that our connection was closed our only indication
        # is that the writes to the socket will fail.
        #
        #
        #
        # If the socket disconnected the close will fail and the reconnect will fail
        # Need to find out why its gone?
        #
        eval { $self->{'_fastcgi_socket'}->close(); };

        $self->_connect_socket();

    }

    if ($bytes_left_to_read) {
        return $self->_read_content_length_from_http_client_and_send_to_fcgi_server($bytes_left_to_read);
    }
    return 1;
}

sub _read_content_length_from_http_client_and_send_to_fcgi_server {
    my ( $self, $bytes_left_to_read ) = @_;

    if ( $bytes_left_to_read > $Cpanel::Server::Constants::MAX_ALLOWED_CONTENT_LENGTH_ALLOW_UPLOAD ) {
        die("The maximum allowed post data size is: $Cpanel::Server::Constants::MAX_ALLOWED_CONTENT_LENGTH_ALLOW_UPLOAD");
    }
    my $start_time         = time();
    my $content            = '';
    my $alarm              = Cpanel::Alarm->new( $Cpanel::Server::Constants::READ_CONTENT_TIMEOUT_ALLOW_UPLOAD, \&_timeout );
    my $http_client_socket = $self->{'_http_client_socket'};
    local $!;
    while ($bytes_left_to_read) {
        my $bytes_to_read_this_read = $bytes_left_to_read > ( FCGI_MAX_CONTENT_LEN - length $content ) ? ( FCGI_MAX_CONTENT_LEN - length $content ) : $bytes_left_to_read;
        my $bytes_read              = $http_client_socket->read( $content, $bytes_to_read_this_read, length $content );
        if ( $bytes_read == -1 ) {
            next if $! == EINTR;
            require Cpanel::Exception;
            die Cpanel::Exception::create( 'IO::ReadError', [ error => $!, length => $bytes_to_read_this_read ] );
        }
        else {
            $bytes_left_to_read -= $bytes_read;
            if ( !$bytes_read || !$bytes_left_to_read ) {
                $self->_write_to_fastcgi_socket( Net::FastCGI::Protocol::build_record( FCGI_STDIN, $self->{'_record_id'}, $content ) . Net::FastCGI::Protocol::build_record( FCGI_STDIN, $self->{'_record_id'}, '' ) );
                last;
            }
            elsif ( length $content == FCGI_MAX_CONTENT_LEN ) {
                $self->_write_to_fastcgi_socket( Net::FastCGI::Protocol::build_record( FCGI_STDIN, $self->{'_record_id'}, $content ) );
                $content = '';
            }
        }
    }

    return 1;
}

sub _timeout {
    require Cpanel::Exception;
    die Cpanel::Exception->create_raw("Your request could not be processed during the allowed timeframe.");
}

*sysread = \&read;

=head1 DESCRIPTION

=head2 sysread, read

=head3 Purpose

 This function more or less mimics Perl’s read() built-in, abstracting
 away the handling of the FastCGI details underneath.

 Caveats:

 - Errors result in a thrown exception. $! is not set.
 - STDERR gets logged.
 - Any non-STDOUT input prompts an undef return.

=head3 Arguments

See perl read()

=cut

sub read {    ## no critic qw(RequireArgUnpacking)
    my ( $self, $buffer_ref, $bytes_to_read, $buffer_offset ) = ( $_[0], \$_[1], $_[2], $_[3] );

    if ( my $orig_stdout_buffer_length = length $self->{'_stdout_buffer'} ) {
        Cpanel::Buffer::move_bytes_from_buffer_ref_to_buffer_ref(
            \$self->{'_stdout_buffer'},    # SOURCE BUFFER
            $buffer_ref,                   # TARGET BUFFER
            $bytes_to_read,                # NUMBER OF BYTES TO MOVE
            $buffer_offset,                # TARGET BUFFER OFFSET
        );

        # Just like perl read() if you ask for more than
        # is available we can only give you what we have.
        return ( $orig_stdout_buffer_length - length $self->{'_stdout_buffer'} );
    }

    if ( !$self->{'_request_is_active'} ) {
        die("FastCGI: read attempted when the request was already completed");

    }

    local $!;
    while (1) {
        my ( $type, $id, $content ) = Cpanel::CPAN::Net::FastCGI::IO::read_record( $self->{'_fastcgi_socket'} );
        if ( !defined $type ) {
            if ($!) {
                die "Net::FastCGI::IO::read_record failed to read a record: $!";
            }
            last;
        }

        if ( $type == FCGI_STDOUT ) {
            my $orig_content_length = length $content;
            Cpanel::Buffer::move_bytes_from_buffer_ref_to_buffer_ref(
                \$content,         # SOURCE BUFFER
                $buffer_ref,       # TARGET BUFFER
                $bytes_to_read,    # NUMBER OF BYTES TO MOVE
                $buffer_offset,    # TARGET BUFFER OFFSET
            );

            $self->{'_stdout_buffer'} = $content;    # anything we didn't splice in we keep in the buffer for next read
                                                     # We we have a 0 length content, this is still a success
                                                     # and we need to return true so the read function is called
                                                     # again and we get FCGI_END_REQUEST
                                                     # Example of why the 0E0 kuldge is needed:
                                                     #
                                                     # while( read .... ) {
                                                     #
                                                     # }
                                                     #
                                                     # We need to return 0E0 when we gen an 'empty' FCGI record as it indicates
                                                     # the end of that packet type.  It does not indicate that reading is complete
                                                     # only that this type of record is complete.  We need the read loop to continue in this
                                                     # instance to avoid missing FCGI_END_REQUEST
            return ( $orig_content_length == 0 ? '0E0' : ( $orig_content_length - length $content ) );
        }
        elsif ( $type == FCGI_STDERR ) {
            $self->{'_logger'}->info("[fcgi] $content");
        }
        elsif ( $type == FCGI_END_REQUEST ) {
            my ( $app_status, $protocol_status ) = Net::FastCGI::Protocol::parse_end_request_body($content);
            if ( $protocol_status != FCGI_REQUEST_COMPLETE ) {
                if ( $protocol_status == FCGI_CANT_MPX_CONN ) {
                    die "FastCGI failed because the application cannot multiplex connections.";
                }
                elsif ( $protocol_status == FCGI_OVERLOADED ) {
                    die "FastCGI failed because the application is overloaded.";
                }
                elsif ( $protocol_status == FCGI_UNKNOWN_ROLE ) {
                    die "FastCGI failed because the application does not recognize the web server’s specified role (FCGI_RESPONDER).";
                }
                else {
                    die "FastCGI failed for an unknown reason (protocolStatus = $protocol_status)";
                }
            }

            #This value of $app_status is what the exit() system call sets.
            #so we need to do a << 8 to make it compatible with
            #perl's $?

            # The FastCGI spec does not report exit signals
            # so its impossible to provide a better $?

            # See close in this module for more information
            $self->{'exit_status'}        = $app_status << 8;
            $self->{'_request_is_active'} = 0;
            $self->{'_eof'}               = 1;
            return undef;

        }
        else {
            die "Unrecognized FastCGI request type $type\n";
        }
    }

    return undef;

}

=head1 DESCRIPTION


=head2 eof

=head3 Purpose

 This function more or less mimics Perl’s eof() built-in, abstracting
 away the handling of the FastCGI details underneath.

=head3 Arguments

See perl eof()

=cut

sub eof { return $_[0]->{'_eof'}; }

=head1 DESCRIPTION

=head2 close

=head3 Purpose

We provide a close() function that is compatible with
perl close on a open child (|-) that will set $? as perl does
in order to interchangeably use this module.

Note: this function does not close the fcgi_socket as that is left
to the caller that opened the socket

=head3 Arguments

See perl close()

=cut

sub close {
    my ($self) = @_;
    if ( $self->{'_request_is_active'} ) {
        $self->{'_logger'}->info("[fcgi] closed before response was complete");
    }
    $self->{'_eof'} = 1;
    $? = $self->{'exit_status'};

    return 1;
}

sub _write_to_fastcgi_socket {
    my ( $self, $buffer ) = @_;

    my ( $total_written, $written );
    local $!;
    local $SIG{'PIPE'} = sub { die "Failed to write to FastCGI socket: $!"; };

    # keep trying to write as the socket may only accept some at a time
    while ( length $buffer ) {
        $written = syswrite( $self->{'_fastcgi_socket'}, $buffer );
        if ( !defined $written || $! ) {
            next if $! == EINTR;
            require Cpanel::Exception;
            die Cpanel::Exception::create( 'IO::WriteError', [ error => $!, length => length $buffer ] );
        }
        $total_written += $written;
        return $total_written if !$written || !length $buffer;
        substr( $buffer, 0, $written, '' );
    }
    return $total_written;
}

1;
