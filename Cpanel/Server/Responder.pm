package Cpanel::Server::Responder;

# cpanel - Cpanel/Server/Responder.pm              Copyright 2022 cPanel, L.L.C.
#                                                           All rights reserved.
# copyright@cpanel.net                                         http://cpanel.net
# This code is subject to the cPanel license. Unauthorized copying is prohibited

use strict;

our $MAX_ALLOWED_IN_MEMORY = 4194304;

our $WRITE_DEFER  = 0;
our $WRITE_NOW    = 1;
our $READ_ONLY    = 2;    #input_buffer is read only
our $WRITE_FINISH = 4;

=head1 METHODS

=cut

# input_handle   - an IO similar object that content will be read from
# input_buffer   - a scalar reference to data read from the input_handle
# headers_buffer - a scalar reference to http headers in string format
# output_coderef - a coderef that takes a single argument of a scalar reference and outputs it
#                  Example
#                  sub output_coderef = {
#                       my($text) = @_;
#                       print $$text;
#                  };
# input_handle_read_function_name - the name of the function to call on the input_handle object
#                                   to read more data
# read_size - The amount of data to read from the input_handle in a single read call
# content-length - The length of the input_buffer + any remaining data on input_handle (may not be known)

sub new {
    my ( $class, %OPTS ) = @_;

    foreach my $required (qw(input_buffer output_coderef input_handle_read_function_name)) {
        if ( !$OPTS{$required} ) {
            require Cpanel::Exception;
            die Cpanel::Exception::create( 'MissingParameter', [ name => $required ] );
        }
    }

    my $self = bless {
        'headers_buffer'                  => $OPTS{'headers_buffer'},
        'input_buffer'                    => $OPTS{'input_buffer'},
        'input_handle'                    => $OPTS{'input_handle'},
        'output_coderef'                  => $OPTS{'output_coderef'},
        'input_handle_read_function_name' => $OPTS{'input_handle_read_function_name'},
        'read_size'                       => ( $OPTS{'read_size'} || $Cpanel::Buffer::DEFAULT_READ_SIZE ),
        'body_bytes_written'              => 0,
        'content-length'                  => $OPTS{'content-length'},

    }, $class;

    $self->init();

    return $self;
}

=head2 I<OBJ>->get_input_buffer()

Returns the string reference that was passed in to C<new()>
as C<input_buffer>.

=cut

sub get_input_buffer {
    my ($self) = @_;

    return $self->{'input_buffer'};
}

sub readonly_from_input_and_send_response {
    my ($self) = @_;

    if ( $self->{'input_handle'} ) {

        # Handle the case where got passed in a buffer
        # we need to write it out right away since reading
        # below will destroy the contents of the buffer
        # since its read-only
        $self->write( $WRITE_NOW | $READ_ONLY ) if length ${ $self->{'input_buffer'} };

        #empty out the perlio layer before we switch to sysreads
        while ( $self->{'input_handle'}->read( ${ $self->{'input_buffer'} }, $self->{'read_size'} ) ) {
            $self->write( $WRITE_NOW | $READ_ONLY );
        }
    }
    return $self->finish($READ_ONLY);
}

sub blocking_read_from_input_and_send_response {
    $_[0]->_blocking_read_from_input();
    return $_[0]->finish($WRITE_FINISH);
}

sub nonblocking_read_from_input_and_send_response {
    my ($self) = @_;

    $self->{'input_handle'}->blocking(0);

    if ( !$self->{'input_handle_never_used_perlio'} ) {

        # nonblocking read cannot happen until
        # the perlIO buffer is cleaned out
        #
        # To facilitate this we set blocking 0 to and clean
        # out the buffer with _blocking_read_from_input
        $self->_blocking_read_from_input();
    }

    local $@;
    if ( eval { fileno( $self->{'input_handle'} ) } ) {    # try is too expensive here
        my ( $rin, $rout, $nfound ) = ('');
        vec( $rin, fileno( $self->{'input_handle'} ), 1 ) = 1;
        my $write_count = 0;
        my $readret;
        while (1) {
            if ( ( $nfound = select( $rout = $rin, undef, undef, undef ) ) && $nfound != -1 ) {    # case 47309: If we get -1 it probably means we got interrupted by a signal
                $readret = $self->{'input_handle'}->sysread( ${ $self->{'input_buffer'} }, $self->{'read_size'}, length ${ $self->{'input_buffer'} } );

                if ($readret) {
                    $self->write( ++$write_count > 1 ? $WRITE_NOW : $WRITE_DEFER );
                }
                elsif ( !defined $readret ) {

                    #For some reason we’re getting $readret == undef and !$!
                    #even though “perldoc -f read” says an undef return will set $!.
                    last if !$!;

                    if ( !$!{'EINTR'} && !$!{'EAGAIN'} ) {
                        die "Failed to read in nonblocking_read_from_input_and_send_response: $!";
                    }
                }
                else {
                    last;    # zero read without error
                }

            }
        }
    }

    #XXX FIXME UGLY HACK so that we can ship this in v66
    if ( $ENV{'CP_SEC_WEBSOCKET_KEY'} ) {
        return $self->write($WRITE_NOW);
    }

    return $self->finish($WRITE_FINISH);
}

sub _blocking_read_from_input {
    my ($self) = @_;

    if ( $self->{'input_handle'} ) {
        my $input_handle_read_function_name = $self->{'input_handle_read_function_name'};

        #empty out the perlio layer before we switch to sysreads
        while ( $self->{'input_handle'}->$input_handle_read_function_name( ${ $self->{'input_buffer'} }, $self->{'read_size'}, length ${ $self->{'input_buffer'} } ) ) {
            $self->write( length ${ $self->{'input_buffer'} } > $MAX_ALLOWED_IN_MEMORY ? $WRITE_NOW : $WRITE_DEFER );
        }
    }

    # Handle the case where got passed in a buffer
    # from something that read before but there was no more to read
    $self->write($WRITE_DEFER) if length ${ $self->{'input_buffer'} };

    return 1;
}

sub finish {
    my ( $self, $flags ) = @_;
    defined $flags or die "Invalid number of arguments passed to finish()";

    $self->write( $WRITE_FINISH | $flags );

    return $self->{'body_bytes_written'};
}

sub write {
    ...;
    return 1;
}

sub init {
    return 1;
}

1;
