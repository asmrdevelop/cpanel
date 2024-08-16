package Cpanel::FileUtils::Move;

# cpanel - Cpanel/FileUtils/Move.pm                Copyright 2022 cPanel, L.L.C.
#                                                           All rights reserved.
# copyright@cpanel.net                                         http://cpanel.net
# This code is subject to the cPanel license. Unauthorized copying is prohibited

use strict;
use Cpanel::Rand            ();
use Cpanel::Debug           ();
use Cpanel::FileUtils::Link ();

##
## *** Never call system() or exec() in this module ***
##
sub safemv {
    my $srcfile = shift;
    my $option;
    if ( $srcfile =~ m/^\-/ ) {
        $option  = $srcfile;
        $srcfile = shift;
    }
    my $destfile = shift;
    my $clobber  = 0;
    my $verbose  = 0;
    my $archive  = 0;

    if ( !-e $srcfile ) {
        Cpanel::Debug::log_warn("$srcfile does not exist.");
        return 0;
    }
    return 0 if !$destfile;

    if ( $option && $option ne '--' ) {
        if ( $option =~ m/f/i ) { $clobber = 1; }
        if ( $option =~ m/v/i ) { $verbose = 1; }
        if ( $option =~ m/a/i ) { $archive = 1; }
    }

    if ( !$clobber && -e $destfile ) {
        print "Unable to move, $destfile exists!" if $verbose;
        Cpanel::Debug::log_warn( "Unable to move, $destfile, needs force option.", 'warn', __PACKAGE__ );
        return 0;
    }
    elsif ( $clobber && $archive && -e $destfile ) {
        my $tmpdestfile = Cpanel::Rand::get_tmp_file_by_name( $destfile, 'cpbak', $Cpanel::Rand::TYPE_FILE, $Cpanel::Rand::SKIP_OPEN );    # audit case 46806 ok
        if ( !rename( $destfile, $tmpdestfile ) ) {
            Cpanel::Debug::log_warn("Unable to rename $destfile: $!");
            return 0;
        }
        else {
            print "Renamed destination file to $tmpdestfile\n" if $verbose;
        }
    }
    elsif ( -e $destfile ) {
        unlink $destfile;
    }

    # First just try to rename the file
    if ( !rename( $srcfile, $destfile ) ) {
        if ( !Cpanel::FileUtils::Link::_replicate_file( $srcfile, $destfile ) ) {
            return 0;
        }

        unlink $srcfile;
        if ( -e $srcfile ) {
            unlink $destfile;
            return 0;
        }
    }

    print "Moved: $srcfile -> $destfile\n" if $verbose;
    return 1;
}

1;
