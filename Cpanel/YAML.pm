package Cpanel::YAML;

# cpanel - Cpanel/YAML.pm                          Copyright 2022 cPanel, L.L.C.
#                                                           All rights reserved.
# copyright@cpanel.net                                         http://cpanel.net
# This code is subject to the cPanel license. Unauthorized copying is prohibited

use strict;

use YAML::Syck         ();
use Cpanel::YAML::Syck ();

#convenience aliases
BEGIN {
    *Dump     = *YAML::Syck::Dump;
    *Load     = *YAML::Syck::Load;
    *SafeDump = *YAML::Syck::Dump;
    *DumpFile = *YAML::Syck::DumpFile;
}

our $MAX_LOAD_LENGTH      = 65535;
our $MAX_PRIV_LOAD_LENGTH = 4194304;    # four megs

#Copied from YAML::Syck
sub _is_openhandle {
    my $h = shift;

    return 1 if ( ref($h) eq 'GLOB' );
    return 1 if ( ref( \$h ) eq 'GLOB' );
    return 1 if ( ref($h) =~ m/^IO::/ );

    return;
}

sub SafeLoadFile {    # only allow a small bit of data to be loaded
    LoadFile( $_[0], $MAX_LOAD_LENGTH );
}

#Copied and slightly tweaked frm YAML::Syck;
sub LoadFile {
    my $file = shift;
    my $max  = shift;

    my $str_r;
    if ( _is_openhandle($file) ) {
        if ($max) {
            my $togo   = $max;
            my $buffer = '';
            my $bytes_read;
            while ( $bytes_read = read( $file, $buffer, $togo, length $buffer ) && length $buffer < $max ) {
                $togo -= $bytes_read;
            }
            $str_r = \$buffer;
        }
        else {
            $str_r = \do { local $/; <$file> };
        }
    }
    else {
        if ( !-e $file || -z $file ) {
            require Carp;
            Carp::croak("'$file' is non-existent or empty");
        }
        open( my $fh, '<', $file ) or do {
            require Carp;
            Carp::croak("Cannot read from $file: $!");
        };
        $str_r = \do { local $/; <$fh> };
    }

    return YAML::Syck::LoadYAML($$str_r);
}

1;
