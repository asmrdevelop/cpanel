package Cpanel::Encoding;

# cpanel - Cpanel/Encoding.pm                      Copyright 2022 cPanel, L.L.C.
#                                                           All rights reserved.
# copyright@cpanel.net                                         http://cpanel.net
# This code is subject to the cPanel license. Unauthorized copying is prohibited

use strict;
use warnings;

use Cpanel::SafeDir         ();
use Cpanel::SafeRun::Simple ();

our $VERSION = '1.0';

our $BASELINE_ENCODING = 'us-ascii';
our $DEFAULT_ENCODING  = 'utf-8';

my %guessed_encodings_cache;

sub guess_file {
    my $file = shift;
    if ( !exists( $guessed_encodings_cache{$file} ) ) {
        $guessed_encodings_cache{$file} = Cpanel::SafeRun::Simple::saferun( '/usr/local/cpanel/bin/guess_file_encoding', $file );
        chomp $guessed_encodings_cache{$file};
        $guessed_encodings_cache{$file} ||= $BASELINE_ENCODING;
    }
    return $guessed_encodings_cache{$file};
}

sub api2_guess_file_opts {
    my %OPTS = @_;
    my $file = safepath( $OPTS{'file'} );

    my $encodings_ar = _get_encodings();

    my $guess = $OPTS{'file_charset'};

    if ( !$guess ) {
        $guess = guess_file($file);

        if ( $guess =~ m{\Aus-?ascii\z}i ) {
            $guess = 'utf-8';
        }
    }

    my @RSD;
    foreach my $map ( @{$encodings_ar} ) {
        push @RSD, { 'map' => $map, 'selected' => ( lc($map) eq lc($guess) ? 'selected' : '' ) };
    }

    return \@RSD;
}

sub api2_get_encodings {
    my $encodings_ar = _get_encodings();

    my @RSD;
    my ( $enc, $enc_copy );
    my $default = $DEFAULT_ENCODING;
    $default =~ tr{A-Z_.-}{a-z}d;
    foreach $enc ( @{$encodings_ar} ) {
        $enc_copy = $enc;
        $enc_copy =~ tr{A-Z_.-}{a-z}d;
        push @RSD, { map => $enc, selected => ( $enc_copy eq $default ? 'selected' : '' ) };
    }

    return \@RSD;
}

sub _get_encodings {
    require Cpanel::Locale::Utils::Charmap;

    # This API originally provided charmaps which were not always iconv compatible.
    # Disabling the iconv option maintains original API output.
    return Cpanel::Locale::Utils::Charmap::get_charmaps( { 'iconv' => 0 } );
}

sub api2_guess_file {
    my %OPTS = @_;
    my $file = safepath( $OPTS{'file'} );
    return [ { 'file' => $file, 'encoding' => guess_file($file) } ];
}

my $allow_demo = { allow_demo => 1 };

our %API = (
    get_encodings   => $allow_demo,
    guess_file      => $allow_demo,
    guess_file_opts => $allow_demo,
);

sub api2 {
    my ($func) = @_;
    return { %{ $API{$func} } } if $API{$func};
    return;
}

sub safepath {
    my $path = shift;
    return if !$path;

    $path =~ tr{/}{}s;    # collapse //s to /
    if ( $path eq $Cpanel::homedir || $path eq $Cpanel::abshomedir ) {
        return $Cpanel::abshomedir;
    }

    my @SL   = split( /\//, $path );
    my $file = pop @SL;
    return Cpanel::SafeDir::safedir( join( '/', @SL ) ) . '/' . $file;
}

1;
