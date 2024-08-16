package Cpanel::Server::Responders::Chunked;

# cpanel - Cpanel/Server/Responders/Chunked.pm     Copyright 2022 cPanel, L.L.C.
#                                                           All rights reserved.
# copyright@cpanel.net                                         http://cpanel.net
# This code is subject to the cPanel license. Unauthorized copying is prohibited

use strict;
use warnings;

use parent 'Cpanel::Server::Responder';

our $CHUNKED_ENCODING_TERMINATION_STRING = "0\r\n\r\n";
our $NORMAL_CHUNK_TEMPLATE               = "%x\r\n%s\r\n";
our $FINISH_CHUNK_TEMPLATE               = "%x\r\n%s\r\n0\r\n\r\n";

sub finish {
    my ( $self, $flags ) = @_;
    defined $flags or die "Invalid number of arguments passed to finish()";

    # If we have not yet written the headers and we have the complete
    # body in memory, we can downgrade to Stream since its faster
    if ( length ${ $self->{'headers_buffer'} } ) {
        bless $self, 'Cpanel::Server::Responders::Stream';
        return $self->finish($flags);
    }

    $self->write( $Cpanel::Server::Responder::WRITE_FINISH | $flags );

    return $self->{'body_bytes_written'};
}

sub write {
    my ( $self, $flags ) = @_;
    defined $flags or die "Invalid number of arguments passed to write()";

    if ( ( $flags & $Cpanel::Server::Responder::WRITE_FINISH ) || ( ( $flags & $Cpanel::Server::Responder::WRITE_NOW ) && length ${ $self->{'input_buffer'} } ) ) {

        # headers_buffer contains the http headers as a string
        # if headers_buffer has content it means we have not written
        # the headers to the output yet as they are consumed after
        # they are written
        if ( length ${ $self->{'headers_buffer'} } ) {
            substr( ${ $self->{'headers_buffer'} }, -2, 2, "Transfer-Encoding: chunked\r\n\r\n" );
            $self->{'body_bytes_written'} += $self->{'output_coderef'}->( \( ${ $self->{'headers_buffer'} } . ${ $self->_generate_chunks($flags) } ) ) - length ${ $self->{'headers_buffer'} };
            ${ $self->{'headers_buffer'} } = '';
            ${ $self->{'input_buffer'} }   = '' if !( $flags & $Cpanel::Server::Responder::READ_ONLY );
        }
        elsif ( length ${ $self->{'input_buffer'} } ) {
            $self->{'body_bytes_written'} += $self->{'output_coderef'}->( $self->_generate_chunks($flags) );
            ${ $self->{'input_buffer'} } = '' if !( $flags & $Cpanel::Server::Responder::READ_ONLY );
        }
        elsif ( $flags & $Cpanel::Server::Responder::WRITE_FINISH ) {
            $self->{'body_bytes_written'} += $self->{'output_coderef'}->( \$CHUNKED_ENCODING_TERMINATION_STRING );
        }
    }
    return 1;
}

sub _generate_chunks {
    my ( $self, $flags ) = @_;
    defined $flags or die "Invalid number of arguments passed to _generate_chunks()";

    return \sprintf( ( $flags & $Cpanel::Server::Responder::WRITE_FINISH ) ? $FINISH_CHUNK_TEMPLATE : $NORMAL_CHUNK_TEMPLATE, length( ${ $self->{'input_buffer'} } ), ${ $self->{'input_buffer'} } );
}

sub sent_complete_content {    ##no critic qw(RequireArgUnpacking)
    return $_[0]->{'body_bytes_written'} > 0 ? 1 : 0;
}

1;
