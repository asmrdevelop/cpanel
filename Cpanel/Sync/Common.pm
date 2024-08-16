package Cpanel::Sync::Common;

# cpanel - Cpanel/Sync/Common.pm                   Copyright 2022 cPanel, L.L.C.
#                                                           All rights reserved.
# copyright@cpanel.net                                         http://cpanel.net
# This code is subject to the cPanel license. Unauthorized copying is prohibited

## straight extractions from cpanelsync; methods used by both cpanelsync and the new v2.pm invocation

use strict;

our $BZ_OK;
our $BZ_STREAM_END;
our $hasbzip2 = 0;
#
# Do not use Compress::Bzip2 as it leaks memory as of 2.017
#
eval {
    require Compress::Raw::Bzip2;
    $BZ_OK         = Compress::Raw::Bzip2::BZ_OK();
    $BZ_STREAM_END = Compress::Raw::Bzip2::BZ_STREAM_END();
    $hasbzip2      = 1;
};

our $BZIP2_CONSUME_INPUT    = 1;
our $BZIP2_OVERWRITE_OUTPUT = 0;
our $BZIP2_APPEND_OUTPUT    = 1;

our $LZMA_OK;
our $LZMA_STREAM_END;
our $haslzma = 0;
eval {
    require Compress::Raw::Lzma;
    $LZMA_OK         = Compress::Raw::Lzma::LZMA_OK();
    $LZMA_STREAM_END = Compress::Raw::Lzma::LZMA_STREAM_END();
    $haslzma         = 1;
};

## Package global; redefined in unit tests
our $cpanelsync_excludes       = '/etc/cpanelsync.exclude';
our $cpanelsync_chmod_excludes = '/etc/cpanelsync.no_chmod';

sub unbzip2 {
    my ($file) = @_;

    die "unbzip2 requires a file" if !length $file;
    lstat($file);

    die "$file is a symlink" if -l _;
    die "$file does not exist" unless -e _;
    die "$file is a directory" if -d _;
    die "$file is not a file"  if !-f_;

    my $outfile = $file;
    $outfile =~ s/\.bz2$//;
    return if ( $outfile eq $file );

    die "cannot decompress $file. $outfile is a directory" if -d $outfile;
    unlink $outfile                                        if -e _;

    if ($hasbzip2) {
        my ( $out_fh, $in_fh );
        open( $out_fh, '>', $outfile ) or die("cpanelsync: unbzip2: error opening $outfile for writing: $!");
        open( $in_fh,  '<', $file )    or die("cpanelsync: unbzip2: error opening $file for reading: $!");
        my ( $bzip2,  $err ) = Compress::Raw::Bunzip2->new( $BZIP2_APPEND_OUTPUT, $BZIP2_CONSUME_INPUT );
        my ( $output, $status );
        my $buf = '';

        while ( read( $in_fh, $buf, 65535, length $buf ) ) {    #65535 is about 35% faster then 512
            $status = $bzip2->bzinflate( $buf, $output );
            if ( $status != $BZ_OK && $status != $BZ_STREAM_END ) {
                die "Inflation Error: Failed to decompress $file. bzinflate failed with status: $status";
            }
            print {$out_fh} $output;
            $output = '';
        }
        close($out_fh);
        close($in_fh);
        unlink($file);
    }
    else {
        system( 'bzip2', '-df', $file );
        if ( $? != 0 ) {
            die "Inflation Error: Failed to decompress $file. bzip2 exited with signal: " . ( $? & 127 ) . " and code: " . ( $? >> 8 );
        }
    }
    return 1;
}

sub get_excludes {
    my ($file) = @_;

    return if ( !-e $file || -z _ );

    my @excludes;
    open( EX, '<', $file ) or return;
    while (<EX>) {
        next if m/^\s*$/;
        chomp;
        s!/$!!;
        push @excludes, $_;
    }
    close(EX);

    return @excludes;
}

sub normalize_path {
    my ($path) = @_;
    $path =~ s{/\./}{/}g;
    $path =~ s{//+}{/}g;
    return $path;
}

sub get_digest_from_cache {
    my ( $cache_hr, $file_hr ) = @_;
    return undef if ( !( defined($file_hr) && defined($cache_hr) ) );

    my $path = normalize_path( $file_hr->{'path'} );
    return undef if ( !defined( $cache_hr->{$path} ) );
    return undef if ( !$cache_hr->{$path}->{'md5'} );

    # This only matches numeric fields at the moment.

    for my $field (qw(size mtime)) {
        return undef if ( !defined( $cache_hr->{$path}->{$field} ) );
        return undef if ( $cache_hr->{$path}->{$field} != $file_hr->{$field} );
    }

    # We should only reach this point if:
    # 1. There is an MD5 to return.
    # 2. Both the size and mtime match exactly.

    return $cache_hr->{$path}->{'md5'};
}

1;
