package Cpanel::LoadFile;

# cpanel - Cpanel/LoadFile.pm                      Copyright 2022 cPanel, L.L.C.
#                                                           All rights reserved.
# copyright@cpanel.net                                         http://cpanel.net
# This code is subject to the cPanel license. Unauthorized copying is prohibited

#Can’t use here because system perl needs to load this module:
#use cPstrict;

use strict;
use warnings;

use Cpanel::Exception          ();
use Cpanel::Fcntl::Constants   ();
use Cpanel::LoadFile::ReadFast ();

sub loadfileasarrayref {
    my $fileref = _load_file( shift, { 'array_ref' => 1 } );
    return ref $fileref eq 'ARRAY' ? $fileref : undef;
}

sub loadbinfile {
    my $fileref = _load_file( shift, { 'binmode' => 1 } );
    return ref $fileref eq 'SCALAR' ? $$fileref : undef;
}

sub slurpfile {
    my $fh      = shift;
    my $fileref = _load_file(shift);
    if ( ref $fileref eq 'SCALAR' ) {
        print {$fh} $$fileref;
    }
    return;
}

#NOTE: Prefer load() below, which die()s on error.
sub loadfile {
    my $fileref = _load_file(@_);
    return ref $fileref eq 'SCALAR' ? $$fileref : undef;
}

#NOTE: Prefer load() below, which die()s on error.
sub loadfile_r {
    my ( $file, $arg_ref ) = @_;

    if ( open my $lf_fh, '<:stdio', $file ) {
        if ( $arg_ref->{'binmode'} ) { binmode $lf_fh; }

        my $data;
        if ( $arg_ref->{'array_ref'} ) {
            @{$data} = readline $lf_fh;
            close $lf_fh;
            return $data;
        }
        else {
            $data = '';
            local $@;

            # Try::Tiny was too slow since this is called from PsParser
            eval { Cpanel::LoadFile::ReadFast::read_all_fast( $lf_fh, $data ); };
            return $@ ? undef : \$data;
        }
    }

    # Failed to open file
    return;
}

*_load_file = *loadfile_r;

sub _open {
    return _open_if_exists( $_[0] ) || die Cpanel::Exception::create( 'IO::FileNotFound', [ path => $_[0], error => _ENOENT() ] );
}

sub _open_if_exists {
    local $!;
    open my $fh, '<:stdio', $_[0] or do {

        #Try to give the best error possible.
        if ( $! == _ENOENT() ) {
            return undef;
        }
        die Cpanel::Exception::create( 'IO::FileOpenError', [ path => $_[0], error => $!, mode => '<' ] );
    };

    return $fh;
}

# Args are $path, $offset, $length
sub load_if_exists {
    my $ref = _load_r( \&_open_if_exists, @_ );
    return $ref ? $$ref : undef;
}

# Args are $path, $offset, $length
sub load_r_if_exists {
    return _load_r( \&_open_if_exists, @_ );
}

# Args are $path, $offset, $length
sub load {
    return ${ _load_r( \&_open, @_ ) };
}

# Args are $path, $offset, $length
sub load_r {
    return _load_r( \&_open,, @_ );
}

sub _load_r {
    my ( $open_coderef, $path, $offset, $length ) = @_;

    #
    # The open function will either die on failure
    # or return undef if failure is acceptable (ie load_if_exists and it does not exist)
    #
    # This avoids throwing an expensive exception when there
    # is nothing wrong.
    #
    my $fh = $open_coderef->($path) or return undef;

    local $!;

    if ($offset) {
        sysseek( $fh, $offset, $Cpanel::Fcntl::Constants::SEEK_SET );

        if ($!) {
            die Cpanel::Exception::create(
                'IO::FileSeekError',
                [
                    path     => $path,
                    position => $offset,
                    whence   => $Cpanel::Fcntl::Constants::SEEK_SET,
                    error    => $!,
                ]
            );
        }
    }

    my $data = q<>;

    #i.e., if you want it all...
    if ( !defined $length ) {

        # Slurping a file presents a couple problems.
        #
        # One way to do it is to stat() for the file size, then
        # read that many bytes. This breaks, though for things like /proc
        # where the file size that stat() reports doesn’t match the number
        # of bytes we’ll get by reading.
        #
        # A more robust way is just to slurp and slurp until we get
        # an empty read. An additional optimization is made below
        # to minimize the number of system calls on large files.
        #
        # 1) Read one chunk of the file:
        #
        my $bytes_read = Cpanel::LoadFile::ReadFast::read_fast( $fh, $data, Cpanel::LoadFile::ReadFast::READ_CHUNK );

        # 2) OPTIMIZATION: If that read was a full read, then stat(),
        # and read the reported file size as a single chunk:
        #
        if ( $bytes_read == Cpanel::LoadFile::ReadFast::READ_CHUNK ) {
            my $file_size = -f $fh && -s _;

            if ($file_size) {

                # We *could* subtract READ_CHUNK from $file_size,
                # but precision doesn’t really matter. The point here
                # is just to load large files faster than reading
                # chunk-by-chunk would yield.
                #
                Cpanel::LoadFile::ReadFast::read_fast( $fh, $data, $file_size, length $data ) // die _read_err($path);
            }
        }

        # 3) Slurp until we get an empty read:
        #
        Cpanel::LoadFile::ReadFast::read_all_fast( $fh, $data );
    }
    else {
        # if $bytes_read is smaller than $togo because read()
        # can be interrupted by a signal, this is not an error!
        #
        # See read(2) for more details.
        my $togo = $length;
        my $bytes_read;
        while ( $bytes_read = Cpanel::LoadFile::ReadFast::read_fast( $fh, $data, $togo, length $data ) && length $data < $length ) {
            $togo -= $bytes_read;
        }
    }

    if ($!) {
        die Cpanel::Exception::create( 'IO::FileReadError', [ path => $path, error => $! ] );
    }

    close $fh or warn "The system failed to close the file “$path” because of an error: $!";

    return \$data;
}

sub _ENOENT { return 2; }
1;
