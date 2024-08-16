package Cpanel::ReadMultipleFH;

# cpanel - Cpanel/ReadMultipleFH.pm                Copyright 2022 cPanel, L.L.C.
#                                                           All rights reserved.
# copyright@cpanel.net                                         http://cpanel.net
# This code is subject to the cPanel license. Unauthorized copying is prohibited

use strict;
use warnings;

use Cpanel::FHUtils::Blocking  ();
use Cpanel::FHUtils::OS        ();
use Cpanel::IO::Flush          ();
use Cpanel::LoadFile::ReadFast ();

my $CHUNK_SIZE = 2 << 16;

my $DEFAULT_TIMEOUT      = 600;    #10 minutes
my $DEFAULT_READ_TIMEOUT = 0;

#Named parameters:
#   filehandles: an arrayref, each of whose members is one of:
#       - a filehandle
#       - [ $filehandle(, undef) ]  (acts the same as the first form)
#       - [ $filehandle, $buffer_sr ]
#       - [ $filehandle, $output_fh ]
#
#   IMPORTANT: All filehandles are assumed to have empty PerlIO buffers.
#
#   timeout: This is an overall timeout in seconds, defaults to $DEFAULT_TIMEOUT.
#       NOTE: A value of 0 disables the timeout.
#   read_timeout: in seconds, defaults to $DEFAULT_READ_TIMEOUT.
#       NOTE: A value of 0 disables the timeout.
#
sub new {    ## no critic qw(Subroutines::ProhibitExcessComplexity)
    my ( $class, %opts ) = @_;

    my %fh_buffer;
    my %output;

    my @fhs = @{ $opts{'filehandles'} };

    my $read_input  = '';
    my $read_output = '';
    my %fhmap;

    my %is_os_filehandle;

    for my $fh_buf_ar (@fhs) {
        if ( UNIVERSAL::isa( $fh_buf_ar, 'GLOB' ) ) {
            $fh_buf_ar = [$fh_buf_ar];
        }
        elsif ( !UNIVERSAL::isa( $fh_buf_ar, 'ARRAY' ) ) {
            die 'items in “filehandles” must be either a filehandle or ARRAY';
        }

        my $fh = $fh_buf_ar->[0];

        Cpanel::FHUtils::Blocking::set_non_blocking($fh);

        $fhmap{ fileno($fh) } = $fh;
        vec( $read_input, fileno($fh), 1 ) = 1;

        if ( defined $fh_buf_ar->[1] && UNIVERSAL::isa( $fh_buf_ar->[1], 'SCALAR' ) ) {
            $fh_buffer{$fh} = $fh_buf_ar->[1];
        }
        else {
            my $buf = q{};
            $fh_buffer{$fh} = \$buf;

            if ( defined $fh_buf_ar->[1] && UNIVERSAL::isa( $fh_buf_ar->[1], 'GLOB' ) ) {
                $output{$fh} = $fh_buf_ar->[1];

                $is_os_filehandle{$fh} = Cpanel::FHUtils::OS::is_os_filehandle( $fh_buf_ar->[1] );
            }
            elsif ( defined $fh_buf_ar->[1] ) {
                die '2nd value in “filehandles” array member must be undef, SCALAR, or GLOB!';
            }
        }
    }

    my $finished;

    my $self = {
        _fh_buffer => \%fh_buffer,
        _finished  => 0,
    };

    bless $self, $class;

    my ( $nfound, $select_time_left, $select_timeout );

    my $overall_timeout = defined $opts{'timeout'}      ? $opts{'timeout'}      : $DEFAULT_TIMEOUT;
    my $read_timeout    = defined $opts{'read_timeout'} ? $opts{'read_timeout'} : $DEFAULT_READ_TIMEOUT;

    my $has_overall_timeout = $overall_timeout ? 1 : 0;

    my $overall_time_left = $overall_timeout || undef;

  READ_LOOP:
    while (
        !$finished &&                                          # has not finished
        ( !$has_overall_timeout || $overall_time_left > 0 )    # has not reached overall timeout
    ) {
        $select_timeout = _get_shortest_timeout( $overall_time_left, $read_timeout );

        ( $nfound, $select_time_left ) = select( $read_output = $read_input, undef, undef, $select_timeout );

        # We hit the select timeout, so end.
        if ( !$nfound ) {

            # determine if we hit the $read_timeout or the dwindling $overall_time_left
            $self->{'_timed_out'} = ( $select_timeout == $read_timeout ) ? $read_timeout : $overall_timeout;
            last;
        }
        elsif ( $nfound != -1 ) {    # case 47309: If we get -1 it probably means we got interrupted by a signal
                                     # vec checks to see if data ready on fileno
            for my $fileno ( grep { vec( $read_output, $_, 1 ) } keys %fhmap ) {
                my $fh = $fhmap{$fileno};

                Cpanel::LoadFile::ReadFast::read_fast( $fh, ${ $fh_buffer{$fh} }, $CHUNK_SIZE, length ${ $fh_buffer{$fh} } ) or do {
                    delete $fhmap{$fileno};

                    $finished = !( scalar keys %fhmap );

                    last READ_LOOP if $finished;

                    vec( $read_input, $fileno, 1 ) = 0;

                    next;
                };

                # If we have an output filehandle we do not store
                # the data in the buffer
                # as it will use too much memory
                if ( $output{$fh} ) {
                    my $payload_sr = \substr( ${ $fh_buffer{$fh} }, 0, length ${ $fh_buffer{$fh} }, q<> );

                    if ( $is_os_filehandle{$fh} ) {

                        #We want to write all of the data out at once before
                        #we read more stuff from the buffer because otherwise
                        #we could continue reading more in than we write, and
                        #eventually we’d run out of memory.
                        Cpanel::IO::Flush::write_all( $output{$fh}, $read_timeout, $$payload_sr );
                    }
                    else {

                        #Since this isn’t a Perl filehandle we’re writing
                        #to, we assume it either won’t fail or that it
                        #handles failures internally.
                        print { $output{$fh} } $$payload_sr;
                    }
                }
            }
        }

        # subtract elapsed time from time left
        $overall_time_left -= ( $select_timeout - $select_time_left ) if $has_overall_timeout;
    }

    delete $fh_buffer{$_} for keys %output;

    %fhmap = ();

    $self->{'_finished'} = $finished;
    if ( !$finished && defined $overall_time_left && $overall_time_left <= 0 ) {

        # we know we hit the dwindling $overall_time_left here
        $self->{'_timed_out'} = $overall_timeout;
    }

    return $self;
}

sub _get_shortest_timeout {
    my ( $overall_time_left, $read_timeout ) = @_;

    # If both timeouts are undef or 0, we don't have a read timeout
    return undef if ( !$overall_time_left && !$read_timeout );

    # If overall time left is not defined, we are not using an overall timeout
    return $read_timeout if !defined $overall_time_left;

    return ( !$read_timeout || $overall_time_left <= $read_timeout )
      ?

      # if we don't have a read timeout or if the total time left is less than or equal to the read timeout, use the total time left
      $overall_time_left
      :

      # if the read timeout is less than the total timeout or we don't have a total timeout, use the read timeout
      $read_timeout;
}

#Returns a scalar reference.
# $_[0] = $self
# $_[1] = $fh
sub get_buffer {
    return $_[0]->{'_fh_buffer'}{ $_[1] };
}

# $_[0] = $self
sub did_finish {
    return $_[0]->{'_finished'} ? 1 : 0;
}

# $_[0] = $self
sub timed_out {
    return defined $_[0]->{'_timed_out'} ? $_[0]->{'_timed_out'} : 0;
}

1;
