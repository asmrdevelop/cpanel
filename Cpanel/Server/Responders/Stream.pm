package Cpanel::Server::Responders::Stream;

# cpanel - Cpanel/Server/Responders/Stream.pm      Copyright 2022 cPanel, L.L.C.
#                                                           All rights reserved.
# copyright@cpanel.net                                         http://cpanel.net
# This code is subject to the cPanel license. Unauthorized copying is prohibited

use strict;
use warnings;

use Class::XSAccessor ( getters => [qw/sent_content_length/] );

use parent 'Cpanel::Server::Responder';

sub _add_pre_known_content_length_to_headers {
    $_[0]->{'sent_content_length'} = $_[0]->{'content-length'} || 0;
    substr( ${ $_[0]->{'headers_buffer'} }, -2, 2, "Content-Length: $_[0]->{'sent_content_length'}\r\n\r\n" );
    return 1;
}

sub _calculate_and_add_content_length_to_headers {
    $_[0]->{'sent_content_length'} = length( ${ $_[0]->{'input_buffer'} } ) || 0;
    substr( ${ $_[0]->{'headers_buffer'} }, -2, 2, "Content-Length: $_[0]->{'sent_content_length'}\r\n\r\n" );
    return 1;
}

sub write {
    scalar @_ == 2 or die "Invalid number of arguments passed to write()";
    my ( $self, $flags ) = @_;

    if ( ( $flags & $Cpanel::Server::Responder::WRITE_FINISH ) || ( ( $flags & $Cpanel::Server::Responder::WRITE_NOW ) && length ${ $self->{'input_buffer'} } ) ) {

        # headers_buffer contains the http headers as a string
        # if headers_buffer has content it means we have not written
        # the headers to the output yet as they are consumed after
        # they are written
        if ( length ${ $self->{'headers_buffer'} } ) {
            if ( $flags & $Cpanel::Server::Responder::WRITE_FINISH ) {
                $self->_calculate_and_add_content_length_to_headers();
            }
            elsif ( defined $self->{'content-length'} ) {
                $self->_add_pre_known_content_length_to_headers();
            }
            if ( length ${ $self->{'input_buffer'} } ) {
                $self->{'body_bytes_written'} += $self->{'output_coderef'}->( \( ${ $self->{'headers_buffer'} } . ${ $self->{'input_buffer'} } ) ) - length ${ $self->{'headers_buffer'} };
            }
            else {
                $self->{'output_coderef'}->( $self->{'headers_buffer'} );
                $self->{'body_bytes_written'} = 0;
            }
            ${ $self->{'input_buffer'} }   = '' if !( $flags & $Cpanel::Server::Responder::READ_ONLY );
            ${ $self->{'headers_buffer'} } = '';
        }
        elsif ( length ${ $self->{'input_buffer'} } ) {
            $self->{'body_bytes_written'} += $self->{'output_coderef'}->( $self->{'input_buffer'} );

            ${ $self->{'input_buffer'} } = '' if !( $flags & $Cpanel::Server::Responder::READ_ONLY );
        }
    }
    return 1;
}

sub sent_complete_content {
    return defined $_[0]->{'body_bytes_written'} && defined $_[0]->{'sent_content_length'} && $_[0]->{'body_bytes_written'} == $_[0]->{'sent_content_length'} ? 1 : 0;
}

1;
