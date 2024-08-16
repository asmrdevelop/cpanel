package Cpanel::Server::Responders::Chunked::Gzip;

# cpanel - Cpanel/Server/Responders/Chunked/Gzip.pm
#                                                  Copyright 2022 cPanel, L.L.C.
#                                                           All rights reserved.
# copyright@cpanel.net                                         http://cpanel.net
# This code is subject to the cPanel license. Unauthorized copying is prohibited

use strict;

use parent qw(Cpanel::Server::Responders::Stream::Gzip);

use Cpanel::Server::Responders::Chunked ();

# This is a hack to make sure we do things in order
sub finish {
    my ( $self, $flags ) = @_;
    defined $flags or die "Invalid number of arguments passed to finish()";

    # If we have not yet written the headers and we have the complete
    # body in memory, we can downgrade to Stream since its faster
    if ( length ${ $self->{'headers_buffer'} } ) {
        if ( length ${ $self->{'input_buffer'} } < $Cpanel::Server::Responders::Stream::Gzip::MINIMUM_GZIP_SIZE ) {
            bless $self, 'Cpanel::Server::Responders::Stream';
        }
        else {
            bless $self, 'Cpanel::Server::Responders::Stream::Gzip';
        }
        return $self->finish($flags);
    }

    $self->write( $Cpanel::Server::Responder::WRITE_FINISH | $flags );

    return $self->{'body_bytes_written'};
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
            substr( ${ $self->{'headers_buffer'} }, -2, 2, "Transfer-Encoding: chunked\r\nContent-Encoding: gzip\r\n\r\n" );
            $self->{'body_bytes_written'} += $self->{'output_coderef'}->( \( ${ $self->{'headers_buffer'} } . ${ $self->_generate_chunks($flags) } ) ) - length ${ $self->{'headers_buffer'} };
            ${ $self->{'headers_buffer'} } = ${ $self->{'gzip_stream_buffer'} } = '';
        }
        elsif ( length ${ $self->{'gzip_stream_buffer'} } ) {
            $self->{'body_bytes_written'} += $self->{'output_coderef'}->( $self->_generate_chunks($flags) );
            ${ $self->{'gzip_stream_buffer'} } = '';
        }
        elsif ( $flags & $Cpanel::Server::Responder::WRITE_FINISH ) {
            $self->{'body_bytes_written'} += $self->{'output_coderef'}->( \$Cpanel::Server::Responders::Chunked::CHUNKED_ENCODING_TERMINATION_STRING );
        }
    }
    return 1;
}

sub _generate_chunks {
    my ( $self, $flags ) = @_;
    defined $flags or die "Invalid number of arguments passed to _generate_chunks()";

    return \sprintf( ( $flags & $Cpanel::Server::Responder::WRITE_FINISH ) ? $Cpanel::Server::Responders::Chunked::FINISH_CHUNK_TEMPLATE : $Cpanel::Server::Responders::Chunked::NORMAL_CHUNK_TEMPLATE, length( ${ $self->{'gzip_stream_buffer'} } ), ${ $self->{'gzip_stream_buffer'} } );
}

sub sent_complete_content {    ##no critic qw(RequireArgUnpacking)
    return $_[0]->{'body_bytes_written'} > 0 ? 1 : 0;
}

1;
