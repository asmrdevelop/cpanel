package Cpanel::Server::Responders::Stream::Gzip;

# cpanel - Cpanel/Server/Responders/Stream/Gzip.pm Copyright 2022 cPanel, L.L.C.
#                                                           All rights reserved.
# copyright@cpanel.net                                         http://cpanel.net
# This code is subject to the cPanel license. Unauthorized copying is prohibited

use strict;

use Cpanel::Gzip::Stream      ();
use Cpanel::Server::Responder ();

use parent qw(Cpanel::Server::Responders::Stream);

our $MINIMUM_GZIP_SIZE = 450;

# Write the gzip header into the gzip_stream_buffer
sub open_gzip_stream {
    my $buffer = '';

    $_[0]->{'gzip_stream_obj'}    = Cpanel::Gzip::Stream->new( \$buffer ) || die("Unable to compress stream: $!");
    $_[0]->{'gzip_stream_buffer'} = \$buffer;

    return 1;
}

sub flush_sync {
    my ($self) = @_;

    $self->{'gzip_stream_obj'}->flush_sync();

    return;
}

sub consume_and_compress_input_buffer {
    my ( $self, $flags ) = @_;
    defined $flags or die "Invalid number of arguments passed to consume_and_compress_input_buffer()";

    if ( length ${ $self->{'input_buffer'} } ) {
        $self->open_gzip_stream() if !$self->{'gzip_stream_obj'};

        $self->{'gzip_stream_obj'}->write( $self->{'input_buffer'} );
        ${ $self->{'input_buffer'} } = '' if !( $flags & $Cpanel::Server::Responder::READ_ONLY );

        if ( $flags != $Cpanel::Server::Responder::WRITE_FINISH ) {
            $self->{'gzip_stream_obj'}->flush_sync();
        }
    }

    if ( $self->{'gzip_stream_obj'} && ( $flags & $Cpanel::Server::Responder::WRITE_FINISH ) ) {
        $self->{'gzip_stream_obj'}->close();
    }

    return 0;

}

sub _calculate_and_add_content_length_and_encoding_to_headers {

    # if there is no body content we need to create the stream
    $_[0]->open_gzip_stream() if !$_[0]->{'gzip_stream_obj'};

    $_[0]->{'sent_content_length'} = length( ${ $_[0]->{'gzip_stream_buffer'} } ) || 0;
    substr( ${ $_[0]->{'headers_buffer'} }, -2, 2, "Content-Encoding: gzip\r\nContent-Length: $_[0]->{'sent_content_length'}\r\n\r\n" );
    return 1;
}

sub _add_content_encoding_to_headers {
    substr( ${ $_[0]->{'headers_buffer'} }, -2, 2, "Content-Encoding: gzip\r\n\r\n" );
    return 1;
}

sub write {
    my ( $self, $flags ) = @_;
    defined $flags or die "Invalid number of arguments passed to write()";

    if ( ( $flags & $Cpanel::Server::Responder::WRITE_FINISH ) || ( ( $flags & $Cpanel::Server::Responder::WRITE_NOW ) && length ${ $self->{'input_buffer'} } ) ) {
        $self->consume_and_compress_input_buffer($flags);

        # headers_buffer contains the http headers as a string
        # if headers_buffer has content it means we have not written
        # the headers to the output yet as they are consumed after
        # they are written
        if ( length ${ $self->{'headers_buffer'} } ) {
            if ( $flags & $Cpanel::Server::Responder::WRITE_FINISH ) {
                $self->_calculate_and_add_content_length_and_encoding_to_headers();
            }
            else {
                $self->_add_content_encoding_to_headers();
            }
            if ( length ${ $self->{'gzip_stream_buffer'} } ) {
                $self->{'body_bytes_written'} += ( $self->{'output_coderef'}->( \( ${ $self->{'headers_buffer'} } . ${ $self->{'gzip_stream_buffer'} } ) ) - length ${ $self->{'headers_buffer'} } );
            }
            else {
                $self->{'output_coderef'}->( $self->{'headers_buffer'} );
                $self->{'body_bytes_written'} = 0;
            }
            ${ $self->{'headers_buffer'} } = ${ $self->{'gzip_stream_buffer'} } = '';
        }
        elsif ( length ${ $self->{'gzip_stream_buffer'} } ) {
            $self->{'body_bytes_written'} += $self->{'output_coderef'}->( $self->{'gzip_stream_buffer'} );
            ${ $self->{'gzip_stream_buffer'} } = '';
        }
    }
    return 1;
}
1;
