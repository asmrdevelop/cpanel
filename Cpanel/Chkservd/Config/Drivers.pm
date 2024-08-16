package Cpanel::Chkservd::Config::Drivers;

# cpanel - Cpanel/Chkservd/Config/Drivers.pm       Copyright 2022 cPanel, L.L.C.
#                                                           All rights reserved.
# copyright@cpanel.net                                         http://cpanel.net
# This code is subject to the cPanel license. Unauthorized copying is prohibited

use strict;
use warnings;

use Cpanel::LoadFile::ReadFast ();

our $VERSION = '1.0';

# Note: we use this module for finding the exim alt port which
# is done in quite a few places.  Please avoid adding additional
# deps if at all possible

sub load_driver_directory {
    my ( $dir, $services_hash_ref, $match_regex ) = @_;

    #Needed since opendir() won’t reset $! on success.
    local $!;

    $services_hash_ref ||= {};
    if ( opendir my $dh, $dir ) {

        my @drivers = readdir($dh);
        die "readdir($dir): $!" if $!;

        foreach my $driver_file (@drivers) {
            if ( $driver_file =~ tr{.-}{} ) {
                next
                  if $driver_file eq '.'
                  || $driver_file eq '..'
                  || $driver_file =~ m/\.conf$/
                  || $driver_file =~ m{\.rpm[^\.]+$}
                  ||                                  # CPANEL-5659: light defense for .rpmorig, .rpmsave files until this can be refactored
                  $driver_file =~ m{-cpanelsync$};    # CPANEL-5659: light defense for -cpanelsync files until this can be refactored
            }

            next if ( $match_regex && $driver_file !~ $match_regex );

            open my $driver_fh, '<:stdio', "$dir/$driver_file" or do {    # Use :stdio to avoid some of the PerlIO overhead since we are slurping in the file
                die "open($dir/$driver_file): $!";
            };

            my $cfg_txt = '';
            Cpanel::LoadFile::ReadFast::read_all_fast( $driver_fh, $cfg_txt );
            die "read($dir/$driver_file): $!" if $!;

            foreach my $line ( split( m{\n}, $cfg_txt ) ) {
                my ( $service, $servdata ) = split( /=/, $line, 2 );
                next if !$service;
                next if $service =~ /^\s*#/;    # Don't process comment lines.
                if ( $service =~ m/service\[([^\]]+)\]/ ) {
                    $services_hash_ref->{$1} = $servdata;
                }
            }
            close $driver_fh;
        }
        closedir $dh;
    }
    else {
        die "opendir($dir): $!" if !$!{'ENOENT'};
    }

    return $services_hash_ref;
}
1;

__END__
