package Cpanel::ExtractFile;

# cpanel - Cpanel/ExtractFile.pm                   Copyright 2022 cPanel, L.L.C.
#                                                           All rights reserved.
# copyright@cpanel.net                                         http://cpanel.net
# This code is subject to the cPanel license. Unauthorized copying is prohibited

use strict;
use warnings;

use Cpanel::SafeRun::Errors ();
use Cwd                     ();

sub extractfile {
    my ( $file, %OPTS ) = @_;
    my $file_test_results = Cpanel::SafeRun::Errors::saferunnoerror( 'file', $file );
    my @files;
    my @CMDARGS;
    my $extractcmd = 'tar';
    if ( $file_test_results =~ /zip\s+archive/i ) {
        $extractcmd = 'unzip';
        if ( $OPTS{'list'} ) {
            push( @CMDARGS, '-l', '-v' );
        }
        else {
            push @CMDARGS, '-o';
        }
        if ( $OPTS{'dir'} ) {
            push @CMDARGS, '-d', $OPTS{'dir'};
        }
    }
    else {
        if ( $OPTS{'list'} ) {
            push( @CMDARGS, '-t' );
        }
        else {
            push( @CMDARGS, '-x' );
        }
        if ( $file_test_results =~ /compress/i ) {
            if ( $file_test_results =~ /bzip/i ) {
                push( @CMDARGS, '-j' );
            }
            else {
                push( @CMDARGS, '-z' );
            }
        }
        if ( $OPTS{'dir'} ) {
            push @CMDARGS, '-C', $OPTS{'dir'};
        }
        push @CMDARGS, '-v', '-f',;
    }
    my @PSL;
    my $fileitem;

    my $extractdir = $OPTS{'dir'} ? $OPTS{'dir'} : Cwd::getcwd();
    $extractdir =~ s/\/$//;    #strip trailing /

    open( my $extract_fh, '-|' ) || exec( $extractcmd, @CMDARGS, $file );
    while ( readline($extract_fh) ) {
        if ( $OPTS{'livedot'} ) {
            print ".\n";
        }
        if ( $extractcmd eq 'tar' ) {
            if ( $OPTS{'list'} ) {

                # When List: Always returns the relative path to each extracted file
                # Actually list the symlink; don't list what it points to.
                s/\s+->\s+.+$//;
                @PSL      = split( /\s+/, $_ );
                $fileitem = $PSL[$#PSL];
                chomp($fileitem);
                $fileitem =~ s/^\.\///g;
                push @files, $fileitem;
            }
            else {

                # When Extracting: Always returns the full path to each extracted file
                chomp();
                if (/^\.\//) {
                    s/^\./$extractdir/g;
                }
                else {
                    $_ = $extractdir . '/' . $_;
                    tr{/}{}s;    # collapse //s to /
                }
                push @files, $_;
            }
        }
        else {
            if ( $OPTS{'list'} ) {

                # When List: Always returns the relative path to each extracted file
                @PSL      = split( /\s+/, $_ );
                $fileitem = $PSL[$#PSL];
            }
            else {

                # When Extracting: Always returns the full path to each extracted file
                $fileitem = ( split( /:/, $_, 2 ) )[1];
            }
            chomp($fileitem);
            $fileitem =~ s/\s+$//g;
            $fileitem =~ s/^\s+//g;
            push @files, $fileitem;
        }
    }
    close($extract_fh);
    if ( $extractcmd eq 'unzip' ) {
        for ( 1 .. 2 ) { pop(@files); }
        for ( 1 .. 3 ) { shift(@files); }
    }
    return \@files;
}
1;
