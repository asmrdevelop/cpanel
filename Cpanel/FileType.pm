package Cpanel::FileType;

# cpanel - Cpanel/FileType.pm                      Copyright 2022 cPanel, L.L.C.
#                                                           All rights reserved.
# copyright@cpanel.net                                         http://cpanel.net
# This code is subject to the cPanel license. Unauthorized copying is prohibited

use strict;

use Cpanel::Autodie          ();
use Cpanel::Fcntl::Constants ();
use Cpanel::FHUtils::Tiny    ();

my @sorted_headers_cache;
my %header_type = (
    'GIF87a' => 'image/gif',
    'GIF89a' => 'image/gif',

    "\xff\xd8\xff" => 'image/jpeg',

    "\x89\x50\x4e\x47\x0d\x0a\x1a\x0a" => 'image/png',

    #http://blogs.msdn.com/b/ieinternals/archive/2011/02/11/ie9-release-candidate-minor-changes-list.aspx#comments
    "\x00\x00\x01\x00" => 'image/x-icon',

    "\x49\x49\x2a\x00" => 'image/tiff',
    "\x4d\x4d\x00\x4a" => 'image/tiff',
);

#NOTE: This will "rewind" the file handle if such is passed in.
#(Seems useful .. potentially not? Feel free to change if that
#ends up being more trouble than its worth.)
sub determine_mime_type {
    my ($path_or_fh) = @_;

    die "Need path or file handle!" if !length $path_or_fh;

    my $fh;

    my $starting_pos;

    if ( Cpanel::FHUtils::Tiny::is_a($path_or_fh) ) {
        $fh           = $path_or_fh;
        $starting_pos = tell($fh);
        Cpanel::Autodie::seek( $fh, 0, 0 );
    }
    else {
        die "Must be path, not ($path_or_fh)!" if ref $path_or_fh;

        Cpanel::Autodie::open( $fh, '<', $path_or_fh );
    }

    my @headers = _sorted_headers();

    Cpanel::Autodie::read( $fh, my $header_from_file, length( $headers[-1] ) );
    if ( defined $starting_pos ) {
        Cpanel::Autodie::seek( $fh, $starting_pos, $Cpanel::Fcntl::Constants::SEEK_SET );
    }

    return determine_mime_type_from_stringref( \$header_from_file );
}

sub determine_mime_type_from_stringref {
    my ($header_from_file) = @_;
    for my $hdr ( _sorted_headers() ) {
        if ( substr( $$header_from_file, 0, length($hdr) ) eq $hdr ) {
            return $header_type{$hdr};
        }
    }

    return undef;
}

sub _sorted_headers {
    return @sorted_headers_cache if @sorted_headers_cache;
    return ( @sorted_headers_cache = sort { length($a) <=> length($b) } keys %header_type );
}

1;
