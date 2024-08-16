package Cpanel::Interconnect;

# cpanel - Cpanel/Interconnect.pm                  Copyright 2022 cPanel, L.L.C.
#                                                           All rights reserved.
# copyright@cpanel.net                                         http://cpanel.net
# This code is subject to the cPanel license. Unauthorized copying is prohibited

#----------------------------------------------------------------------
#This module implements a read/write interconnect between two "sides".
#Either "side" can be either a read/write filehandle or a 2-member array(ref)
#of: [ $read_fh, $write_fh ].
#
#For example, if you have two sockets, you can make them "talk" to each other
#via this module: read from the first and write to the second, and vice-versa.
#
#This module uses only unbuffered reads and writes. Before starting, it will
#read/clear the buffers on both read filehandles and use anything there as the
#first thing to send to the other side.
#
#NOTE: This will close() the passed-in filehandles.
#TODO: It would be ideal not to close the filehandles; however, this couldn't
#be made to work at this time with rsync, which is the primary "consumer" of
#this module as of October 2014.
#----------------------------------------------------------------------

use strict;

use Errno                     ();
use Cpanel::Exception         ();
use Cpanel::FHUtils           ();
use Cpanel::FHUtils::Blocking ();
use Cpanel::FHUtils::Tiny     ();

our $READ_SIZE = 1 << 19;

my $DATA_WAIT_TIMEOUT = 60**2 * 6;    # 6 Hour timeout

my $EAGAIN = Errno::EAGAIN();
my $EINTR  = Errno::EINTR();

#%OPTS is:
#   handles - must be two unique filehandles (order is irrelevant)
#
sub new {
    my ( $class, %OPTS ) = @_;

    if ( !$OPTS{'handles'} ) {
        die 'Missing “handles”!';
    }
    elsif ( ref $OPTS{'handles'} ne 'ARRAY' || ( @{ $OPTS{'handles'} } != 2 ) ) {
        die '“handles” must be an arrayref containing two "sides".';
    }

    my $self = _generate_interconnect_setup( $OPTS{'handles'} );

    bless $self, $class;

    return $self;
}

sub connect {
    my ($self) = @_;

    my ( $bytes_read, $bytes_written, $read_handle, $read_output, $write_input, $write_output, $nfound, $time_left );

    my $all_read_handles_are_open = 1;

    my @handles = @{ $self->{'handles'} };

    local ( $!, $^E );

    my @reader_fhs   = map { $_->source_is_reader() ? $_->get_fh('source') : () } @handles;
    my $read_bitmask = Cpanel::FHUtils::Tiny::to_bitmask(@reader_fhs);

    #TODO: Replace the direct accesses to Cpanel::Interconnect::_Player
    #object internals with method calls.

  SELECT_LOOP:

    # TODO: More ideally, this should continue looping as along as there
    # is at least one read handle open so as to accommodate connections
    # where one side no longer reads but will still write. But changing that
    # appears to break tests, and given that nothing customer-facing appears
    # to be broken presently, this may be something that customers don’t
    # actually need us to fix.
    while ($all_read_handles_are_open) {

        $write_input = q<>;

        # Only select() target handles that have data
        # ready to be written to them as handles that
        # do not have data pending will likely always
        # be ready and the select will never block and
        # chew up all the cpu.
        if ( length $handles[0]->{'buffer'} ) {
            $write_input |= $handles[0]->{'target_bitmask'};
        }
        if ( length $handles[1]->{'buffer'} ) {
            $write_input |= $handles[1]->{'target_bitmask'};
        }

        ( $nfound, $time_left ) = select(
            $read_output = $read_bitmask,     #
            $write_output = $write_input,     #
            undef,                            #
            $DATA_WAIT_TIMEOUT                #
        );

        if ( $nfound == -1 ) {

            # If we get interrupted by a signal, this should not be a fatal error
            # and we can just try again.
            next SELECT_LOOP if ( $! == $EINTR );

            die Cpanel::Exception::create( 'IO::SelectError', [ error => $! ] );
        }
        elsif ( !$time_left ) {
            die Cpanel::Exception::create( 'Timeout', 'The system reached the timeout of [quant,_1,second,seconds] while reading interconnected handles.', [$DATA_WAIT_TIMEOUT] );
        }

      MAIN_READ_LOOP:
        foreach my $handle (@handles) {
            if ( vec( $read_output, $handle->{'source_fileno'}, 1 ) ) {
                $bytes_read = $handle->do_read();

                if ( !defined $bytes_read ) {
                    unless ( $! == $EAGAIN || $! == $EINTR ) {
                        die Cpanel::Exception::create( 'IO::ReadError', 'The system failed to read [format_bytes,_1] from the interconnected handle because of an error: [_2]', [ $READ_SIZE, $! ] );
                    }

                    next MAIN_READ_LOOP;
                }
                elsif ( $bytes_read == 0 ) {    # Closed
                    $all_read_handles_are_open = 0;

                    # TODO: To support “half-closed” connections, ideally
                    # this would shutdown(SHUT_RD) rather than close()
                    # if the handle is a socket. The close() here prevents
                    # us from writing to this filehandle.
                    _close_fh( $handle->{'source_fh'} );

                    # Close the target as well if the buffer is empty
                    # Otherwise we need to write it in the loop below
                    if ( !length $handle->{'buffer'} ) {

                        # Nothing left to write
                        #
                        # TODO: To support half-closed connections, ideally
                        # this would shutdown(SHUT_WR) instead if the handle
                        # is a socket.
                        _close_fh( $handle->{'target_fh'} );

                        next MAIN_READ_LOOP;
                    }
                }
                elsif ( $bytes_read < 0 ) {
                    die Cpanel::Exception::create( 'IO::ReadError', 'The system failed to read [format_bytes,_1] from the interconnected handle because of an error: [_2]', [ $READ_SIZE, $! ] );
                }
            }

          MAIN_WRITE_LOOP:

            while ( length $handle->{'buffer'} ) {
                $bytes_written = $handle->do_write();

                if ( !defined $bytes_written ) {    # Try to write as much as possible
                                                    # as we will chop off what we cannot
                                                    # write below and try again once the handle is ready
                    unless ( $! == $EAGAIN || $! == $EINTR ) {
                        die Cpanel::Exception::create( 'IO::WriteError', 'The system failed to write [format_bytes,_1] to the interconnected handle because of an error: [_2]', [ length $handle->{'buffer'}, $! ] );
                    }

                    # We need to break out of the select if the other set of
                    # handles has data that needs to be read in order to avoid
                    # blocking forever when the connected system's buffer
                    # get full
                    $read_handle = ( $handles[0]->{'target_fileno'} == $handle->{'target_fileno'} ) ? 1 : 0;

                    ( $nfound, $time_left ) = select( $read_output = $handles[$read_handle]->{'source_bitmask'}, $write_output = $handle->{'target_bitmask'}, undef, $DATA_WAIT_TIMEOUT );

                    if ( $nfound == -1 ) {

                        # If we get interrupted by a signal, this should not be a fatal error
                        # and we can just try again.
                        next MAIN_WRITE_LOOP if ( $! == $EINTR );

                        die Cpanel::Exception::create( 'IO::SelectError', [ error => $! ] );
                    }
                    elsif ( !$time_left ) {
                        die Cpanel::Exception::create( 'Timeout', 'The system reached the timeout of [quant,_1,second,seconds] while writing interconnected handles.', [$DATA_WAIT_TIMEOUT] );
                    }

                    # If we can write more try to do that first
                    # so we can reduce the size of our memory buffer
                    next MAIN_WRITE_LOOP if vec( $write_output, $handle->{'target_fileno'}, 1 );

                    # The other side had data and we still could not write
                    # we need to go read it so we do not block forever
                    next MAIN_READ_LOOP;
                }
                elsif ( $bytes_written == 0 ) {    # Closed
                    die Cpanel::Exception::create( 'IO::WriteError', 'The system failed to write [format_bytes,_1] to the interconnected handle because it was unexpectedly closed.', [ length $handle->{'buffer'} ] );
                }
                elsif ( $bytes_written < 0 ) {
                    die Cpanel::Exception::create( 'IO::WriteError', 'The system failed to write [format_bytes,_1] to the interconnected handle because of an error: [_2]', [ length $handle->{'buffer'}, $! ] );
                }

                # Successfully wrote something
                else {
                    substr( $handle->{'buffer'}, 0, $bytes_written, '' );
                }
            }
        }
    }

    #Close any filehandles that may still be open.
    for (@handles) {
        _close_fh($_) for @{$_}{qw(source_fh target_fh)};
    }

    return 1;
}

sub _close_fh {
    my ($fh) = @_;
    return unless defined $fh;
    if ( $fh->isa('IO::Socket::SSL') ) {
        $fh->stop_SSL( SSL_fast_shutdown => 1 );

        # second attempt
        if ( $fh->isa('IO::Socket::SSL') ) {
            $fh->close( SSL_no_shutdown => 1 );
        }
    }
    else { close($fh) }
    return;
}

sub _handle_or_stdout {
    my ($handle) = @_;

    return ( Cpanel::FHUtils::are_same( $handle, \*STDIN ) ? \*STDOUT : $handle );
}

sub _generate_interconnect_setup {
    my ($handles) = @_;

    my @handles_data;
    for my $fh_or_fh_arrayref (@$handles) {
        my ( $read_fh, $write_fh );
        if ( 'ARRAY' eq ref $fh_or_fh_arrayref ) {
            if ( @$fh_or_fh_arrayref != 2 ) {
                die "File handle pair should have exactly 2 members: [@$fh_or_fh_arrayref]";
            }

            ( $read_fh, $write_fh ) = @$fh_or_fh_arrayref;

            if ( !Cpanel::FHUtils::is_reader($read_fh) ) {
                die "Read filehandle ($read_fh) is not a reader .. ??";
            }
            if ( !Cpanel::FHUtils::is_writer($write_fh) ) {
                die "Write filehandle ($write_fh) is not a writer .. ??";
            }
        }
        else {
            ( $read_fh, $write_fh ) = ( $fh_or_fh_arrayref, $fh_or_fh_arrayref );
        }

        my $instantiant = 'Cpanel::Interconnect::_Player';
        if ( $read_fh->isa('IO::Socket::SSL') ) {
            Cpanel::Interconnect::_Player::_init_ssl_vars();
            if ( $write_fh->isa('IO::Socket::SSL') ) {
                $instantiant .= '::SSLReadWrite';
            }
            else {
                $instantiant .= '::SSLRead';
            }
        }
        elsif ( $write_fh->isa('IO::Socket::SSL') ) {
            $instantiant .= '::SSLWrite';
        }

        push @handles_data,
          [
            $instantiant->new($read_fh),
            $write_fh,
          ];
    }

    for my $h ( 0, 1 ) {
        $handles_data[$h][0]->set_target( $handles_data[ _flip01($h) ][1] );
    }

    $_ = $_->[0] for @handles_data;

    if ( Cpanel::FHUtils::are_same( map { $_->get_fh('source') } @handles_data ) ) {
        die "Source filehandles cannot be the same!";
    }

    if ( Cpanel::FHUtils::are_same( map { $_->get_fh('target') } @handles_data ) ) {
        die "Target filehandles cannot be the same!";
    }

    return { handles => \@handles_data };
}

sub _flip01 {
    my $v = shift;
    return 1 - $v;
}

#----------------------------------------------------------------------
#NOTE: This module is a bit tightly coupled to Cpanel::Interconnect;
#it would be nice to refactor this a bit more cleanly in the future.
#----------------------------------------------------------------------

package Cpanel::Interconnect::_Player;

sub new {
    my ( $class, $read_fh ) = @_;

    my $self = {
        buffer => q<>,
    };
    bless $self, $class;

    #Clear read buffers on the file handles. This is important because
    #those buffers could contain the first bits that we need to pass to
    #the other file handle.
    #
    #NOTE: Both sides have a hash entry named 'source_fh', even if it's
    #the same file handle as what's in target_fh and is write-only. This
    #is an artifact of this module's initial design for 11.46. It was
    #considered to change this during a refactor for 11.48 but felt to
    #be too risky. The code below accommodates this, so it's ok; we
    #wouldn't have gotten this far were there an actual problem with the
    #passed-in filehandles.
    if ( Cpanel::FHUtils::is_reader($read_fh) ) {
        $self->{'buffer'} .= Cpanel::FHUtils::flush_read_buffer($read_fh);
        $self->{'_source_is_reader'} = 1;
    }

    $self->_set_fh( 'source', $read_fh );

    return $self;
}

sub source_is_reader {
    my ($self) = @_;

    return $self->{'_source_is_reader'} ? 1 : 0;
}

sub get_fh {
    my ( $self, $type ) = @_;

    return $self->{"${type}_fh"} || die "No “$type”!";
}

sub set_target {
    my ( $self, $receptor_fh ) = @_;

    $self->_set_fh( 'target', $receptor_fh );

    return;
}

#Might as well not create these variables every time.
my $got;
my $ret;
my $bytes_written;

my $ERROR_WANT_READ;
my $ERROR_ZERO_RETURN;
my $ERROR_WANT_WRITE;
my $ERROR_SYSCALL;

sub _init_ssl_vars {
    $ERROR_WANT_READ   = Net::SSLeay::ERROR_WANT_READ();
    $ERROR_ZERO_RETURN = Net::SSLeay::ERROR_ZERO_RETURN();
    $ERROR_WANT_WRITE  = Net::SSLeay::ERROR_WANT_WRITE();
    $ERROR_SYSCALL     = Net::SSLeay::ERROR_SYSCALL();
    return 1;
}

#Sets $!
sub do_read {

    #$_[0] = self;

    return sysread(
        $_[0]->{'source_fh'},
        $_[0]->{'buffer'},
        $Cpanel::Interconnect::READ_SIZE,
        length $_[0]->{'buffer'},
    );
}

#Sets $!
sub do_write {

    #$_[0] = self;

    return syswrite( $_[0]->{'target_fh'}, $_[0]->{'buffer'} );
}

sub _set_fh {
    my ( $self, $type, $fh ) = @_;

    #Strictly speaking, the _net_ssleay stuff should be in a separate
    #class since now we’re doing SSL stuff potentially on a non-SSL
    #socket/handle. But the benefit from that would seem fairly minimal.

    @{$self}{ "${type}_fh", "${type}_bitmask", "${type}_fileno", "${type}_net_ssleay" } = (
        $fh,
        Cpanel::FHUtils::Tiny::to_bitmask($fh),
        fileno($fh),
        _get_ssl_object($fh),
    );

    #All filehandles must be non-blocking for Interconnect.
    if ( Cpanel::FHUtils::Blocking::is_set_to_block($fh) ) {
        Cpanel::FHUtils::Blocking::set_non_blocking($fh);
    }

    return;
}

#Because of some mysterious weirdness, this cannot move to a different module.
#
sub _get_ssl_object {

    #We access the internal Net::SSLeay index so that we can optimize SSL
    #in this module. (Using IO::Socket::SSL’s abstractions was quite slow.)
    return $_[0]->isa('IO::Socket::SSL') ? $_[0]->_get_ssl_object() : undef;
}

#----------------------------------------------------------------------

package Cpanel::Interconnect::_Player::SSLRead;

use parent -norequire, qw( Cpanel::Interconnect::_Player );

#Sets $!
sub do_read {

    #$_[0] = self;
    ( $got, $ret ) = Net::SSLeay::read( $_[0]->{'source_net_ssleay'} );

    if ( !defined $got || $ret <= 0 ) {
        my $err = Net::SSLeay::get_error( $_[0]->{'source_net_ssleay'}, $ret );
        if ( !$err ) {
            $! ||= $EINTR;
            return undef;
        }

        # In OpenSSL 3+ an empty read triggers a sendmsg, which, if the
        # peer TCP socket is already closed, triggers EPIPE. Since a
        # read operation doesn’t normally cause EPIPE, let’s assume that
        # any time that happens, it’s because of that sendmsg, whose failure
        # state we can just ignore.
        #
        if ( $err == Net::SSLeay::ERROR_SSL() && $!{'EPIPE'} ) {
            $got = q<>;
        }
        else {
            return 0 if ( $err == $ERROR_SYSCALL && !$! ) || $err == $ERROR_ZERO_RETURN;    # underly read returned nothing or clean shutdown
            if ( $err == $ERROR_WANT_READ || $err == $ERROR_WANT_WRITE ) {
                $! ||= $EAGAIN;
            }

            #Net::SSLeay::read() should set $!, but it doesn't always
            $! ||= $EINTR;
            Net::SSLeay::ERR_clear_error();
            return undef;
        }
    }

    $_[0]->{'buffer'} .= $got;

    return length $got;
}

#----------------------------------------------------------------------

package Cpanel::Interconnect::_Player::SSLWrite;

use parent -norequire, qw( Cpanel::Interconnect::_Player );

#Sets $!
sub do_write {

    #$_[0] = self;

    $bytes_written = Net::SSLeay::write( $_[0]->{'target_net_ssleay'}, $_[0]->{'buffer'} );
    if ( !defined $bytes_written || $bytes_written <= 0 ) {
        my $err = Net::SSLeay::get_error( $_[0]->{'target_net_ssleay'}, $bytes_written );
        if ( !$err ) {
            $! ||= $EINTR;
            return undef;
        }
        return 0 if $err == $ERROR_ZERO_RETURN;    # clean shutdown

        if ( $err == $ERROR_WANT_READ || $err == $ERROR_WANT_WRITE ) {
            $! ||= $EAGAIN;
        }

        #Net::SSLeay::read() should set $!, but it doesn't always
        $! ||= $EINTR;
        Net::SSLeay::ERR_clear_error();
        return undef;
    }
    return $bytes_written;
}

#----------------------------------------------------------------------

package Cpanel::Interconnect::_Player::SSLReadWrite;

use parent -norequire, qw(
  Cpanel::Interconnect::_Player::SSLRead
  Cpanel::Interconnect::_Player::SSLWrite
);

1;
