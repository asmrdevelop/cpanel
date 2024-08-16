package Cpanel::FileUtils::Split;

# cpanel - Cpanel/FileUtils/Split.pm               Copyright 2022 cPanel, L.L.C.
#                                                           All rights reserved.
# copyright@cpanel.net                                         http://cpanel.net
# This code is subject to the cPanel license. Unauthorized copying is prohibited

use strict;
use warnings;

# Avoid loading Errno if possible to reduce memory footprint
use constant _EINTR => 4;

use Cpanel::Math ();

=head1 NAME

Cpanel::FileUtils::Split

=head1 SYNOPSIS

This module is intended to manage splitting up one file into multiple parts, with sub-parts thereof.
We refer to these 'sub-parts' as "chunks" due to it making sense in the context of what this was designed
to serve -- chunked uploads.

See t/small/Cpanel-FileUtils-Split.t and Cpanel/Transport/Files/Backblaze.pm for example usage, also NOTES

Most of the "magic" you'll wanna understand is in process_parts, so make sure to read the code there.

=head1 DESCRIPTION

This module implements a generic file splitter, currently used to decomplicate/decouple this logic from the BackBlaze B2 backup transport.

=head1 NOTES

The key assumption in this module is that the file you are splitting isn't growing/shrinking/disappearing out from under you.
Basically this module intends to take a given file, split it into several parts, then pick small chunks out of each part into memory for you to process
This allows doing things like circumventing file size limits on upload services like BackBlaze B2.

Example case:
  Service I upload to has 5GB size limit per file
  Service allows chunked uploads for files to help avoid timeouts
  "Reccomended" chunk size is 5MB or something
  Then I can write something like:

  my $splitter = Cpanel::FileUtils::Split->new( 'file' => $test_file, 'part_size' => 1024, 'chunk_size' => 100 );
  my $parts_manifest = $splitter->get_manifest();
  ... # Write the parts manifest file individually as this is actually not a huge file. Probably beneath the chunk size threshhold.
  my $pre_part_processor_sr  = sub { ... }; # Some subroutine that tells my upload service "hey I'm starting a chunked upload for this file"
  my $chunk_processor_sr     = sub { ... }; # Some subroutine that actually does the upload, see POD for subroutine for usage
  my $post_part_processor_sr = sub { ... }; # Some subroutine that signals the service that I'm done uploading chunks.
  $splitter->process_parts( $pre_part_processor_sr, $chunk_processor_sr, $post_part_processor_sr );

  ...And that would "do the needful for your chunked upload.

=head1 SUBROUTINES

=head2 new

Instantiate a new instance

Required args:

* File: A path to a real file on the system (unless using Test::MockFile)

* part_size: The desired part size to split this up by. If this doesn't divide cleanly, the remainder will be delivered in get_manifest()
as 'last_part_size'.

* chunk_size: The desired chunk size to split the individual parts up by. If it doesn't divide cleanly, the last chunk you are delivered
in the subroutine passed as the second arg to process_parts will be the remaining bytes (hopefully that's not too confusing).

Part size or chunk size, when set to 0, is equivalent to "the whole thing".
In the context of part size, that means the whole file.
In the context of chunk size, that means the entire part.

Returns the object or dies (if invalid args were passed or we couldn't open the file for reading).

=cut

# Hash of args and a subroutine to validate the arg
my %required_args = (
    'file'       => sub { _error( 'InvalidParameter', [ "part_size", "Must be a path to a real file on the system" ] ) if !-f $_[0] },
    'part_size'  => sub { _error( 'InvalidParameter', [ "part_size",  "must be defined and greater than or equal to zero" ] ) if ( !defined( $_[0] ) && $_[0] < 0 ) },
    'chunk_size' => sub { _error( 'InvalidParameter', [ "chunk_size", "Must be defined and greater than or equal to zero" ] ) if ( !defined( $_[0] ) && $_[0] < 0 ) },
);

sub new {
    my ( $class, %args ) = @_;

    # Validate args
    foreach ( keys %required_args ) {
        $required_args{$_}->( $args{$_} );
    }

    my $obj = bless \%args, $class;

    # NOTE _ is only set due to the validation above doing -f on the file! If refactoring this, be sure not to break that assumption!
    $obj->{'size'}      = -s _;
    $obj->{'part_size'} = $obj->{'size'} if $obj->{'part_size'} == 0;
    _die_invalid( 'chunk_size', "chunk_size is larger than part_size." ) if $obj->{'part_size'} < $obj->{'chunk_size'};
    $obj->_calculate_parts();
    open( $obj->{'_fh'}, '<', $obj->{'file'} ) || _error( 'IO::FileOpenError', [ path => $obj->{'file'}, error => $!, mode => '<' ] );
    $obj->{'_pos'} = 0;

    return $obj;
}

sub _calculate_parts {
    my ($self) = @_;
    return $self->{'parts_arr'} if $self->{'parts_arr'};

    # Calculate number of parts, saving the remainder as the "last part size" for when things aren't evenly split.
    # Use ceiling as that automatically accounts for having a remainder.
    $self->{'num_parts'}      = Cpanel::Math::ceil( $self->{'size'} / $self->{'part_size'} );
    $self->{'last_part_size'} = $self->{'size'} % $self->{'part_size'};

    return;
}

sub _calculate_chunks {
    my ( $self, $cur_part_size ) = @_;
    my $chunks_hr = {
        'num_chunks'         => Cpanel::Math::ceil( $cur_part_size / $self->{'chunk_size'} ),
        'maximum_chunk_size' => $self->{'chunk_size'},
        'last_chunk_size'    => $cur_part_size % $self->{'chunk_size'},
    };
    return $chunks_hr;
}

=head2 get_manifest

Returns a HASHREF of information about the file you want to process in a split manner.

Example:

    {
        'size'              => 4098, # The file's size per -s
        'maximum_part_size' => 1024, # The part_size you passed into the constructor
        'last_part_size'    => 2,    # The remainder (if any) when attempting to split the file.
        'num_parts'         => 5,    # The number of parts this is split into ( calculated as ceil( $size / $maximum_part_size ) ).
    }

=cut

sub get_manifest {
    my ($self) = @_;
    return {
        'size'              => $self->{'size'},
        'maximum_part_size' => $self->{'part_size'},
        'last_part_size'    => $self->{'last_part_size'},
        'num_parts'         => $self->{'num_parts'},
    };
}

=head2 process_parts

Accepts an array of subroutine references (see below).
Returns undef, or dies if:
* We encounter a file read error that isn't EINTR
* Your processor subroutines feel the need to do so.

Subroutines you pass in gets a hash of args containing the following:
  $pre_part_processor_sub:
    'part_size'  => integer representing size (in bytes) of the current file part. Possibly useful for signaling a service that you are beginning a file.
    'part_num'   => The number of part that is currently being processed (starting at 1).
  $chunk_processor_sub:
    'chunk_size' => integer representing size (in bytes) of the current file chunk. If chunk size is set to part_size, you'll get the entire file part.
    'chunk'      => The actual data read in for the chunk, ready for you to pass on to whereever it needs to go.
    'chunk_num'  => The number of chunk that is currently being processed (starting at 1)
  $post_part_processor_sub:
    same args as pre sub. Useful for signaling that you are done uploading chunks that correspond to this file part.
  $last_part_override_procesor
    same args as pre/post sub, only with one extra:
    'part' => the entire part read in. This is useful when your last bit of the file is actually too small to do a chunked upload on.
    If this is passed in, the previous three subs are not ran for the last part.

I strongly urge you to read the Cpanel::Transport::Files::Backblaze module if you wish to understand why this was done in this manner.

=cut

sub process_parts {
    my ( $self, $pre_part_processor_sub, $chunk_processor_sub, $post_part_processor_sub, $last_part_override_processor ) = @_;

    foreach my $cur_part ( 1 .. $self->{'num_parts'} ) {
        my $cur_part_size = $self->{'part_size'};
        $cur_part_size = $self->{'last_part_size'} if ( $self->{'last_part_size'} && $cur_part eq $self->{'num_parts'} );
        if ( $cur_part_size == $self->{'last_part_size'} && $last_part_override_processor ) {
            my $pos_before_read = $self->{'_pos'};
            my $part            = $self->_read_chunk($cur_part_size);
            $last_part_override_processor->( 'part_size' => $cur_part_size, 'part_num' => $cur_part, 'part' => $part, 'part_pos' => $pos_before_read );
        }
        else {
            $pre_part_processor_sub->( 'part_size' => $cur_part_size, 'part_num' => $cur_part ) if $pre_part_processor_sub;

            # Now process the chunks
            my $cur_chunks_hr = $self->_calculate_chunks($cur_part_size);

            foreach my $cur_chunk ( 1 .. $cur_chunks_hr->{'num_chunks'} ) {
                my $cur_chunk_size = $cur_chunks_hr->{'maximum_chunk_size'};
                $cur_chunk_size = $cur_chunks_hr->{'last_chunk_size'} if ( $cur_chunks_hr->{'last_chunk_size'} && $cur_chunk eq $cur_chunks_hr->{'num_chunks'} );

                my $chunk = $self->_read_chunk($cur_chunk_size);
                $chunk_processor_sub->( 'chunk_size' => $cur_chunk_size, 'chunk' => $chunk, 'chunk_num' => $cur_chunk ) if $chunk_processor_sub;
            }
            $post_part_processor_sub->( 'part_size' => $cur_part_size, 'part_num' => $cur_part ) if $post_part_processor_sub;
        }
    }

    return;
}

sub _read_chunk {
    my ( $self, $cur_chunk_size ) = @_;

    # Go to the point in the file we need to be at and read in the chunk, resetting if we encounter EINTR.
    my ( $read_size, $chunk );
    my $err = _EINTR;
    while ( !defined($read_size) && $err == _EINTR ) {
        local $!;
        seek $self->{'_fh'}, $self->{'_pos'}, 0;
        $read_size = read $self->{'_fh'}, $chunk, $cur_chunk_size;
        $err = $!;
    }
    if ( $err && $err != _EINTR ) {
        $self->_error( "IO::ReadError", { 'error' => $err } );
    }
    $self->{'_pos'} = tell $self->{'_fh'};
    return $chunk;
}

=head2 _error

Instead of dies scattered around we funnel them all to here.

=cut

sub _error {
    my ( $self, $exception_type, $exception_params ) = @_;

    require Cpanel::Exception;
    die Cpanel::Exception::create( $exception_type, $exception_params );
}

sub DESTROY {
    close( $_[0]->{'_fh'} );
    return;
}
