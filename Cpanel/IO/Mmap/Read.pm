package Cpanel::IO::Mmap::Read;

# cpanel - Cpanel/IO/Mmap/Read.pm                  Copyright 2022 cPanel, L.L.C.
#                                                           All rights reserved.
# copyright@cpanel.net                                         http://cpanel.net
# This code is subject to the cPanel license. Unauthorized copying is prohibited

=encoding UTF-8

=head1 NAME

Cpanel::IO::Mmap::Read

=head1 DESCRIPTION

Read from a file handle using mmap

=cut

=head1 SYNOPSIS

    use Cpanel::IO::Mmap::Read ();

    my $buffer;
    my $fh = IO::File->new('/home/file_larger_then_2mib.gz','<');
    my $reader_obj = Cpanel::IO::Mmap::Read->new($fh);
    while($reader_obj->read($buffer,1024**2)) {
        ...
    }


    undef $reader_obj;

    OR

    $reader_obj->release_buffer();

=cut

=head1 DESCRIPTION

=cut

use strict;
use warnings;

use Sys::Mmap                ();
use Cpanel::Fcntl::Constants ();

use constant PROT_READ  => Sys::Mmap::PROT_READ();
use constant MAP_SHARED => Sys::Mmap::MAP_SHARED();
use constant SEEK_SET   => $Cpanel::Fcntl::Constants::SEEK_SET;
use constant SEEK_CUR   => $Cpanel::Fcntl::Constants::SEEK_CUR;
use constant SEEK_END   => $Cpanel::Fcntl::Constants::SEEK_END;

use Errno qw[EINVAL];

=head2 new

=head3 Purpose

Creates a new Cpanel::IO::Mmap::Read object

=head3 Arguments

=over

=item $fh: filehandle - A perl file handle

=back

=head3 Returns

=over

=item A Cpanel::IO::Mmap::Read object

=back

If an error occurs, the function will throw an exception.

=cut

sub new {

    #my ( $class, $fh ) = @_;
    return bless { '_fh_position' => 0, '_fh' => $_[1], '_file_length' => sysseek( $_[1], 0, SEEK_END ) }, $_[0];
}

=head2 mmap_read (also read, sysread)

=head3 Purpose

Uses mmap to a specified number of bytes from the file handle
that was provided when the object was created and store the contents
in a read-only buffer.

=head3 Arguments

=over

=item $buffer_ref: string - A scalar to store the data that will be read

=item $bytes_to_read: integer - The number of bytes to read

=item $offset: integer - The position in the file read (currently not implemented, but checked to ensure callers do not replace read() calls and get unexpected results).

=back

=head3 Returns

=over

=item The number of bytes read from the file handle or undef if nothing has been read

=back

If an error occurs, the function will throw an exception.

=cut

*sysread = *mmap_read;
*read    = *mmap_read;

sub mmap_read {    ## no critic qw(RequireArgUnpacking)
    my ( $self, $buffer_ref, $bytes_to_read, $offset ) = ( $_[0], \$_[1], $_[2], $_[3] );

    die "mmap_read does not support reading at an offset" if $offset;

    $self->release_buffer() if $self->{'_buffer_is_mmapd'};

    my $bytes_left_in_file   = ( $self->{'_file_length'} - $self->{'_fh_position'} );
    my $actual_bytes_to_read = (
        $bytes_to_read < $bytes_left_in_file ||                          # remaining is less then what we want to read
          ( $self->{'_file_length'} && $self->{'_file_length'} == 0 )    # the file has a zero but true length (usually a character device like /dev/zero)
    ) ? $bytes_to_read : $bytes_left_in_file;

    # Finish reading
    return if !$actual_bytes_to_read;

    # Will generate an exception on failure
    Sys::Mmap::mmap( $$buffer_ref, $actual_bytes_to_read, PROT_READ, MAP_SHARED, $self->{'_fh'}, $self->{'_fh_position'} );

    $self->{'_buffer_is_mmapd'} = 1;
    $self->{'_mmap_buffer'}     = $buffer_ref;    # Save so we can unmmap it later
    $self->{'_fh_position'} += length $$buffer_ref;

    # We only return if we did die on the mmap
    return $actual_bytes_to_read;
}

=head2 seek

=head3 Purpose

Implements a perl seek call for this object

=head3 Arguments

See perldoc -f seek

=head3 Returns

See perldoc -f seek

=cut

sub seek {
    my ( $self, $position, $whence ) = @_;

    $whence ||= SEEK_SET;

    $self->release_buffer();
    if ( $whence == SEEK_END ) {
        my $new_position = $self->{'_file_length'} + $position;
        if ( $new_position < 0 || $new_position > $self->{'_file_length'} ) {
            $! = EINVAL;
            return -1;
        }
        return ( $self->{'_fh_position'} = $new_position );
    }
    elsif ( $whence == SEEK_CUR ) {

        # We hold the position internally since we are really
        # looking at bits of mmaped memory.  SEEK_CUR in this case
        # is just adjusting the position of our internal pointer

        my $new_position = $self->{'_fh_position'} + $position;
        if ( $new_position < 0 || $new_position > $self->{'_file_length'} ) {
            $! = EINVAL;
            return -1;
        }
        return ( $self->{'_fh_position'} = $new_position );

    }
    else {
        return ( $self->{'_fh_position'} = $position );
    }
}

=head2 release_buffer

=head3 Purpose

unmmaps the buffer.

=head3 Arguments

None

=head3 Returns

1. If an error occurs, the function will throw an exception.

=cut

=head1 KNOWN BUGS / ISSUES

Cpanel::IO::Mmap::Read does not provide all the functionality of
that’s compatible with IO::File.

sysseek(), binmode(), chmod(), etc. are not provided, however
we currently do not need them.  If that changes they will be implemented
later.

=cut

*close = *release_buffer;    # compat

sub release_buffer {
    return 0 if !$_[0]->{'_buffer_is_mmapd'};

    # Will generate an exception on failure
    Sys::Mmap::munmap( ${ $_[0]->{'_mmap_buffer'} } );
    return delete $_[0]->{'_buffer_is_mmapd'};
}

*DESTROY = \*release_buffer;
