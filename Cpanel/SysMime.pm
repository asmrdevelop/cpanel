package Cpanel::SysMime;

# cpanel - Cpanel/SysMime.pm                       Copyright 2022 cPanel, L.L.C.
#                                                           All rights reserved.
# copyright@cpanel.net                                         http://cpanel.net
# This code is subject to the cPanel license. Unauthorized copying is prohibited

use strict;
use warnings;

use Cpanel::ConfigFiles::Apache 'apache_paths_facade';    # see POD for import specifics
use Cpanel::SafeFile ();
use Cpanel::Debug    ();

#ensure_mimetype( { 'application/blah' => ['pig','cow','frog'] } );

sub ensure_mimetype {
    my $dirsnref = shift;
    my %seendir;
    my $directive_list = join( '|', map { $_; } keys %{$dirsnref} );
    my $mimetypes_file = apache_paths_facade->file_conf_mime_types();
    if ( !-e $mimetypes_file ) {
        Cpanel::Debug::log_warn("Could not find $mimetypes_file");
        return;
    }
    my $sysmimelock = Cpanel::SafeFile::safeopen( \*SYSMIME, '+<', $mimetypes_file );
    if ( !$sysmimelock ) {
        Cpanel::Debug::log_warn("Could not edit $mimetypes_file");
        return;
    }
    my @SYSMIME = <SYSMIME>;
    seek( SYSMIME, 0, 0 );
    foreach (@SYSMIME) {

        if (/^\s*($directive_list)\s*(.*)/o) {
            my $directive = $1;
            next if ( $seendir{$directive} );
            my @DL = map { s/^\.//g; $_; } split( /\s+/, $2 );    ## no critic qw(ControlStructures::ProhibitMutatingListFunctions)
            $seendir{$directive} = 1;

            foreach my $ext ( @{ $dirsnref->{$directive} } ) {
                $ext =~ s/^\.//g;
                if ( !grep( /^\Q$ext\E$/, @DL ) ) {
                    push @DL, $ext;
                }
            }
            print SYSMIME $directive . " \t\t " . join( ' ', @DL ) . "\n";
        }
        else {
            print SYSMIME;
        }
    }
    foreach my $directive ( keys %{$dirsnref} ) {
        next if ( $seendir{$directive} );
        print SYSMIME $directive . " \t\t " . join( ' ', @{ $dirsnref->{$directive} } ) . "\n";
    }
    truncate( SYSMIME, tell(SYSMIME) );
    Cpanel::SafeFile::safeclose( \*SYSMIME, $sysmimelock );
    return;
}

1;

__END__
Sample Usage:

use Cpanel::SysMime ();

Cpanel::SysMime::ensure_mimetype(
            {
                'application/pig' => ['pig','cow'],
                'video/x-sgi-movie' => ['evil'],
            }
        );
