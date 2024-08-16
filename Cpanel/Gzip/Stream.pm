package Cpanel::Gzip::Stream;

# cpanel - Cpanel/Gzip/Stream.pm                   Copyright 2022 cPanel, L.L.C.
#                                                           All rights reserved.
# copyright@cpanel.net                                         http://cpanel.net
# This code is subject to the cPanel license. Unauthorized copying is prohibited

# This is intended to be a tiny version of IO::Compress::Gzip

use strict;
use Compress::Raw::Zlib ();

use constant Z_FINISH     => Compress::Raw::Zlib::Z_FINISH();
use constant Z_SYNC_FLUSH => Compress::Raw::Zlib::Z_SYNC_FLUSH();
use constant Z_OK         => Compress::Raw::Zlib::Z_OK();

use constant Z_DEFAULT_STRATEGY => Compress::Raw::Zlib::Z_DEFAULT_STRATEGY();
use constant Z_DEFLATED         => Compress::Raw::Zlib::Z_DEFLATED();
use constant FLAG_APPEND        => Compress::Raw::Zlib::FLAG_APPEND();
use constant FLAG_CRC           => Compress::Raw::Zlib::FLAG_CRC();
use constant MAX_WBITS          => Compress::Raw::Zlib::MAX_WBITS();
use constant MAX_MEM_LEVEL      => Compress::Raw::Zlib::MAX_MEM_LEVEL();

use constant WRITE_SCALAR    => 0;
use constant WRITE_FH        => 1;
use constant WRITE_SCALARREF => 2;

our $Z_OK             = 0;       # needed for compat
our $Z_BLOCK_SIZE     = 65535;
our $Z_COMPRESS_LEVEL = 4;       # cf. https://blog.stackexchange.com/2009/08/a-few-speed-improvements/

*syswrite = \&write;

sub new {
    my ( $class, $output ) = @_;

    # Thanks to IO::Compress::FAQ for the gzip header
    my $gzip_header = pack( 'nccVcc', 0x1f8b, Z_DEFLATED, 0, time(), 0, 0x03 );
    my $method      = 0;

    if ( ref $output && ref $output eq 'SCALAR' ) {
        $method = WRITE_SCALARREF;
        ${$output} .= $gzip_header;
    }
    elsif ( ref $output ) {
        $method = WRITE_FH;
        print {$output} $gzip_header or return undef;
    }
    else {
        $method = WRITE_SCALAR;
        $output = $gzip_header;
    }

    return bless {
        'method' => $method,
        'open'   => 1,
        'output' => $output,
        'zlib'   => scalar Compress::Raw::Zlib::_deflateInit(
            FLAG_APPEND | FLAG_CRC,
            $Z_COMPRESS_LEVEL,
            Z_DEFLATED,
            -(MAX_WBITS),
            MAX_MEM_LEVEL,
            Z_DEFAULT_STRATEGY,
            $Z_BLOCK_SIZE,
            ''
        ),
    }, $class;
}

sub write {
    my $self = shift;
    if ($#_) {    #more than one arg
        my $status;
        foreach (@_) {
            if ( $self->{'method'} == WRITE_FH ) {
                my $buffer;
                $status ||= $self->{'zlib'}->deflate( $_, $buffer );
                print { $self->{'output'} } $buffer;
            }
            else {
                $status ||= $self->{'zlib'}->deflate( $_, $self->{'output'} );
            }
        }
        return $status == Z_OK ? 1 : 0;
    }
    elsif ( $self->{'method'} == WRITE_FH ) {
        my $buffer;
        my $status = $self->{'zlib'}->deflate( $_[0], $buffer );
        print { $self->{'output'} } $buffer;
        return $status == Z_OK ? 1 : 0;
    }
    return $self->{'zlib'}->deflate( $_[0], $self->{'output'} ) == Z_OK ? 1 : 0;
}

sub close {
    my $self   = shift;
    my $status = $self->flush();

    if ( $self->{'method'} == WRITE_FH ) {
        print { $self->{'output'} } pack( 'LL', $self->{'zlib'}->crc32(), $self->{'zlib'}->total_in() );
    }
    elsif ( $self->{'method'} == WRITE_SCALARREF ) {
        ${ $self->{'output'} } .= pack( 'LL', $self->{'zlib'}->crc32(), $self->{'zlib'}->total_in() );
    }
    else {
        $self->{'output'} .= pack( 'LL', $self->{'zlib'}->crc32(), $self->{'zlib'}->total_in() );
    }

    $self->{'open'} = 0;

    return $status;
}

sub flush {
    my ( $self, $flags ) = @_;

    return if !$self->{'open'};

    if ( !defined $flags ) { $flags = Z_FINISH; }

    if ( $self->{'method'} == WRITE_FH ) {
        my $buffer;
        my $status = $self->{'zlib'}->flush( $buffer, $flags );
        print { $self->{'output'} } $buffer;
        return $status;
    }

    return $self->{'zlib'}->flush( $self->{'output'}, $flags );

}

sub flush_sync {
    my ($self) = @_;

    $self->flush(Z_SYNC_FLUSH);
}

sub autoflush { 1; }

# ---- end object calls

sub gzip {
    my ( $input_ref, $output_ref ) = @_;

    my $obj = __PACKAGE__->new($output_ref);
    if ( ref $input_ref && ref $input_ref ne 'SCALAR' ) {
        local $/;
        $obj->write( readline($input_ref) );
    }
    else {
        my $z = $obj->write($input_ref);
    }

    return $obj->close();
}

1;
