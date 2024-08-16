package IO::Framed::Read;

use strict;
use warnings;

use IO::Framed::X ();

sub new {
    my ( $class, $in_fh, $initial_buffer ) = @_;

    if ( !defined $initial_buffer ) {
        $initial_buffer = q<>;
    }

    my $self = {
        _in_fh         => $in_fh,
        _read_buffer   => $initial_buffer,
        _bytes_to_read => 0,
    };

    return bless $self, $class;
}

sub get_read_fh { return $_[0]->{'_in_fh'} }

#----------------------------------------------------------------------
# IO subclass interface

sub allow_empty_read {
    my ($self) = @_;
    $self->{'_ALLOW_EMPTY_READ'} = 1;
    return $self;
}

sub READ {
    require IO::SigGuard;
    IO::SigGuard->import('sysread');
    *READ = *IO::SigGuard::sysread;
    goto &READ;
}

#We assume here that whatever read may be incomplete at first
#will eventually be repeated so that we can complete it. e.g.:
#
#   - read 4 bytes, receive 1, cache it - return undef
#   - select()
#   - read 4 bytes again; since we already have 1 byte, only read 3
#       … and now we get the remaining 3, so return the buffer.
#
sub read {
    my ( $self, $bytes ) = @_;

    die "I refuse to read zero!" if !$bytes;

    if ( length $self->{'_read_buffer'} ) {
        if ( length($self->{'_read_buffer'}) + $self->{'_bytes_to_read'} != $bytes ) {
            my $should_be = length($self->{'_read_buffer'}) + $self->{'_bytes_to_read'};
            die "Continuation: should want “$should_be” bytes, not $bytes!";
        }
    }

    if ( $bytes > length($self->{'_read_buffer'}) ) {
        $bytes -= length($self->{'_read_buffer'});

        local $!;

        local $self->{'_return'};

        $bytes -= $self->_expand_read_buffer( $bytes );

        return q<> if $self->{'_return'};
    }

    $self->{'_bytes_to_read'} = $bytes;

    if ($bytes) {
        return undef;
    }

    return substr( $self->{'_read_buffer'}, 0, length($self->{'_read_buffer'}), q<> );
}

sub _expand_read_buffer {
    return $_[0]->can('READ')->( $_[0]->{'_in_fh'}, $_[0]->{'_read_buffer'}, $_[1], length($_[0]->{'_read_buffer'}) ) || do {
        if ($!) {
            if ( !$!{'EAGAIN'} && !$!{'EWOULDBLOCK'}) {
                die IO::Framed::X->create( 'ReadError', $! );
            }
        }
        elsif ($_[0]->{'_ALLOW_EMPTY_READ'}) {
            $_[0]->{'_return'} = 1;
            0;
        }
        else {
            die IO::Framed::X->create('EmptyRead');
        }
    };
}

sub read_until {
    my ( $self, $seq ) = @_;

    if ( $self->{'_bytes_to_read'} ) {
        die "Don’t call read_until() after an incomplete read()!";
    }

    die "Missing read-until sequence!" if !defined $seq || !length $seq;

    my $at = index( $self->{'_read_buffer'}, $seq );

    if ($at > -1) {
        return substr( $self->{'_read_buffer'}, 0, $at + length($seq), q<> );
    }

    local $self->{'_return'};

    $self->_expand_read_buffer( 65536 );

    return q<> if $self->{'_return'};

    $at = index( $self->{'_read_buffer'}, $seq );

    if ($at > -1) {
        return substr( $self->{'_read_buffer'}, 0, $at + length($seq), q<> );
    }

    return undef;
}

#----------------------------------------------------------------------

1;
