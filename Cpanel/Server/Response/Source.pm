package Cpanel::Server::Response::Source;

# cpanel - Cpanel/Server/Response/Source.pm        Copyright 2022 cPanel, L.L.C.
#                                                           All rights reserved.
# copyright@cpanel.net                                         http://cpanel.net
# This code is subject to the cPanel license. Unauthorized copying is prohibited

use strict;
use warnings;
#
use Cpanel::Exception ();
#
use constant {
    buffer_is_read_only             => 0,
    input_handle_read_function_name => 'read',
    read_size                       => 65535,
};

use Class::XSAccessor (
    getters => {
        entire_content_is_in_memory => 'entire_content_is_in_memory',
        content_type                => 'content-type'
    }
);

our $LF   = "\n";
our $CR   = "\r";
our $CRLF = "$CR$LF";

#
# Input fields
# entire_content_is_in_memory - input_buffer has the entire contents of the source in memory
# input_buffer                - a scalar ref containg data that has been read from tne source
#
# Http Header input fields
# http-status                 - the http status provided by the source
# http-status-message         - the http status message provided by the source
# content-type                - the http content-type provided by the source
# content-length              - the http content-length provided by the source
# last-modified               - the http last-modified provided by the source
# headers                     - arbitrary http headers to include in the response that are separated by \r\n
#                               (i.e., this is the actual text, not a hashref)
#
sub new {
    my ( $class, %OPTS ) = @_;
    return bless {
        'input_buffer'                => ( $OPTS{'input_buffer'} // die Cpanel::Exception::create( 'MissingParameter', [ name => 'input_buffer' ] ) ),
        'entire_content_is_in_memory' => ( $OPTS{'entire_content_is_in_memory'} // $class->entire_content_is_in_memory() // die Cpanel::Exception::create( 'MissingParameter', [ name => 'entire_content_is_in_memory' ] ) ),
        'http-status'                 => $OPTS{'http-status'},
        'http-status-message'         => $OPTS{'http-status-message'},
        'content-type'                => $OPTS{'content-type'},
        'content-length'              => $OPTS{'content-length'},
        'last-modified'               => $OPTS{'last-modified'},
        'headers'                     => ( $OPTS{'use-cache'} ? $OPTS{'headers'} : ( $OPTS{'headers'} // '' ) . nocache() ),
    }, $class;
}

sub get {
    return $_[0]->{ $_[1] };
}

sub get_fields {
    return $_[0];
}

sub nocache {
    return "Cache-Control: no-cache, no-store, must-revalidate, private\r\nPragma: no-cache\r\n";
}

sub parse_and_consume_headers {
    my ( $self, $input_ref ) = @_;

    $self->{'_line_separator'}        = index( $$input_ref, "$CRLF$CRLF" ) > -1 ? $CRLF : $LF;
    $self->{'_line_separator_offset'} = length( $self->{'_line_separator'} );

    my $is_websocket;
    my $send_websocket_connection;

    while (1) {

        # No more \n means no more headers
        if ( ( $self->{'_last_lf_position'} = index( $$input_ref, $LF ) ) == -1 ) {
            return 0;
        }

        # In this case we are looking for \n but the next header is \r\n
        elsif ( $self->{'_line_separator'} eq $LF && index( $$input_ref, $CR ) == $self->{'_last_lf_position'} - 1 ) {
            $self->{'_line_separator'}        = $CRLF;
            $self->{'_line_separator_offset'} = 2;
        }

        # In this case we are looking for \r\n but the next header is \n
        elsif ( $self->{'_line_separator'} eq $CRLF && index( $$input_ref, $CR ) != $self->{'_last_lf_position'} - 1 ) {
            $self->{'_line_separator'}        = $LF;
            $self->{'_line_separator_offset'} = 1;
        }

        $_ = substr( $$input_ref, 0, index( $$input_ref, $self->{'_line_separator'} ) + $self->{'_line_separator_offset'}, '' );

        # Three ways to indicate status
        if ( !length $_ || $_ eq $CRLF || $_ eq $LF ) {    #end of headers
            if ( $is_websocket && $send_websocket_connection ) {
                $self->{'headers'} .= "Connection: $send_websocket_connection$CRLF";
            }

            return 1;
        }
        elsif (m/^HTTP\S+[ \t]+([0-9]+)[ \t]+([^\r\n]+)/) {
            $self->{'http-status'}         = $1;
            $self->{'http-status-message'} = $2;
        }
        elsif (m/^(?:last-modified|status|content-length|location|content-type|content-encoding):/i) {
            if (m/^status:[ \t]+([0-9]+)[ \t]*([^\r\n]*)/i) {
                $self->{'http-status'}         = $1;
                $self->{'http-status-message'} = $2;
            }
            elsif (m/^content-length:[ \t]+([0-9]+)/i) {
                $self->{'content-length'} = $1;
            }
            elsif (m/^last-modified:[ \t]+([^\r\n]+)/i) {
                $self->{'last-modified'} = $1;
            }
            elsif (m/^location:[ \t]+([^\r\n]+)/i) {
                $self->{'location'} = $1;
            }
            elsif (m/^content-type:[ \t]+([^\r\n]+)/i) {
                $self->{'content-type'} = $1;
            }
            elsif (m/^content-encoding:[ \t]+([^\r\n]+)/i) {
                $self->{'content-encoding'} = $1;
                if ( substr( $_, -2 ) ne "\r\n" ) {
                    s/[\r\n]+$//;
                    $self->{'headers'} .= $_ . $CRLF;
                }
                else {
                    $self->{'headers'} .= $_;
                }
            }
        }
        elsif (m/\Aconnection:[ \t]+(Upgrade)[\r\n]*\z/i) {
            $send_websocket_connection = $1;
        }
        elsif ( !m/^(?:connection|date|keep-alive|server|x-powered-by):/i ) {
            $self->{'headers'} .= substr( $_, -2 ) ne "\r\n" ? s/[\r\n]+$//r . $CRLF : $_;

            #WebSockets requires that we return Connection:
            if ( $_ =~ m<\AUpgrade:[ \t]+websocket\s*\z>s ) {
                $is_websocket = 1;
            }
        }
    }

    return 0;
}

1;

__END__
