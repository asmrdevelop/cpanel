package Cpanel::Path;

# cpanel - Cpanel/Path.pm                          Copyright 2022 cPanel, L.L.C.
#                                                           All rights reserved.
# copyright@cpanel.net                                         http://cpanel.net
# This code is subject to the cPanel license. Unauthorized copying is prohibited

use strict;
use warnings;

use Cpanel::StringFunc::Trim  ();
use Cpanel::StringFunc::Match ();
use Cpanel::Logger            ();
use Cpanel::Path::Normalize   ();
use Cwd                       ();

our $VERSION = '1.0';

sub relativesymlink {
    my $srcfullpath  = shift;
    my $destfullpath = shift;
    my $val;

    return 0 if ( $destfullpath eq $srcfullpath );
    return 0 if ( !-e $srcfullpath );

    # Just in case, and to clean up the path
    $srcfullpath  = relative2abspath($srcfullpath);
    $destfullpath = relative2abspath($destfullpath);

    my $link = abs2relativepath( $srcfullpath, $destfullpath );

    if ( !-e $destfullpath || -l $destfullpath ) {
        unlink($destfullpath);
        $val = symlink( $link, $destfullpath );
    }

    return $val;
}

################################################################################
# getdir - returns directory, similar to dirname but if path ends with a
#   directory, then returns that
################################################################################
sub getdir {
    my $path = shift;
    if ( -d $path ) {
        return $path;
    }
    else {
        my @dirs = split( /\//, $path );
        pop(@dirs);

        # if the only token we have left is '', then this must
        # be '/'
        if ( $#dirs == 0 && $dirs[0] eq '' ) {
            return '/';
        }
        return join( '/', @dirs );
    }
    return '';
}

################################################################################
# calcabspath - calculates the absolute path of a relative path given a specific
#       base path.
################################################################################
sub calcabspath {
    my $relpath  = shift;
    my $basepath = shift;

    if ( !defined($basepath) || $basepath eq '' ) {
        Cpanel::Logger::cplog( "Improper use of calcabspath! basepath must be defined.", 'die', __PACKAGE__ );
    }
    if ( !Cpanel::StringFunc::Match::beginmatch( $basepath, '/' ) ) {
        Cpanel::Logger::cplog( "Improper use of calcabspath! $basepath must be an absolute path.", 'warn', __PACKAGE__ );
        return '';
    }
    return Cpanel::Path::Normalize::normalize( $basepath . '/' . $relpath );
}

sub _collapse_identical_front_tokens {
    my ( $path1, $path2, $delim ) = @_;

    if ( !defined($delim) || $delim eq '' ) {
        Cpanel::Logger::cplog( 'Improper use of _collapse_identical_front_tokens (no delim)', 'die', __PACKAGE__ );
    }
    my $delim_regex = qr/$delim/;

    my $delimiter_at_beginning;

    if ( Cpanel::StringFunc::Match::beginmatch( $path1, $delim ) && Cpanel::StringFunc::Match::beginmatch( $path2, $delim ) ) {
        $delimiter_at_beginning = 1;
    }
    elsif ( !Cpanel::StringFunc::Match::beginmatch( $path1, $delim ) && !Cpanel::StringFunc::Match::beginmatch( $path2, $delim ) ) {
        $delimiter_at_beginning = 0;
    }
    else {

        # one of the strings begin with delimiter and the other is not. No need
        # to collapse these, they are different from beginning.
        return ( $path1, $path2 );
    }

    my @path1_arr = split( $delim_regex, $path1 );
    my @path2_arr = split( $delim_regex, $path2 );

    # pick the shorter one for num of tokens to process
    my $num_of_tokens = scalar @path1_arr;
    if ( $num_of_tokens > scalar @path2_arr ) {
        $num_of_tokens = scalar @path2_arr;
    }

    # throw away the front tokens if they are the same
  COLLAPSE_LOOP:
    while ($num_of_tokens) {

        if ( $path1_arr[0] ne $path2_arr[0] ) {
            last COLLAPSE_LOOP;
        }

        shift @path1_arr;
        shift @path2_arr;
        $num_of_tokens--;
    }

    $path1 = join( $delim, @path1_arr );
    $path2 = join( $delim, @path2_arr );

    # a split and then a join does not handle delimiter at the beginning.
    # we must add the delimiter at the beginning ourselves.
    if ($delimiter_at_beginning) {
        $path1 = $delim . $path1;
        $path2 = $delim . $path2;
    }

    return ( $path1, $path2 );
}

sub _count_tokens {
    my ( $str, $delim ) = @_;
    if ( !defined($str) || $str eq '' ) {
        Cpanel::Logger::cplog( 'Improper use of _count_tokens (no str)', 'die', __PACKAGE__ );
    }
    if ( !defined($delim) || $delim eq '' ) {
        Cpanel::Logger::cplog( 'Improper use of _count_tokens (no delim)', 'die', __PACKAGE__ );
    }
    my $delim_regex = qr/$delim/;
    my @arr         = split( $delim_regex, $str );

    # don't count an empty token at the beginning.
    if ( scalar @arr > 0 && $arr[0] eq '' ) {
        shift @arr;
    }
    return scalar @arr;
}

################################################################################
# calcrelpath - calculates the relative path of an absolute path given a
#   specific base path.
################################################################################
sub calcrelpath {
    my $abspath  = shift;
    my $basepath = shift;

    if ( !defined($abspath) || $abspath eq '' ) {
        return '';
    }
    if ( !defined($basepath) || $basepath eq '' ) {
        Cpanel::Logger::cplog( "Improper use of calcrelpath! basepath must be defined.", 'die', __PACKAGE__ );
    }

    if ( !Cpanel::StringFunc::Match::beginmatch( $basepath, '/' ) ) {
        Cpanel::Logger::cplog( "Improper use of calcrelpath! $basepath must be an absolute path.", 'warn', __PACKAGE__ );
        return '';
    }

    $basepath = Cpanel::Path::Normalize::normalize($basepath);
    $abspath  = Cpanel::Path::Normalize::normalize( '/' . $abspath );

    $basepath = getdir($basepath);

    $abspath  = Cpanel::StringFunc::Trim::endtrim( $abspath,  '/' );
    $basepath = Cpanel::StringFunc::Trim::endtrim( $basepath, '/' );

    # this dir is the relative path. Return ''
    if ( $abspath eq $basepath ) {
        return '';
    }

    # if basepath = '/my/base' and abspath = '/my/base/etc', then return 'etc'
    if ( Cpanel::StringFunc::Match::beginmatch( $abspath, $basepath ) ) {
        my $rel_path = substr( $abspath, length($basepath) );
        $rel_path = Cpanel::StringFunc::Trim::begintrim( $rel_path, '/' );
        return $rel_path;
    }

    ( $abspath, $basepath ) = _collapse_identical_front_tokens( $abspath, $basepath, '/' );

    $abspath = Cpanel::StringFunc::Trim::begintrim( $abspath, '/' );

    # if there's no basepath, then our abspath is the relative path
    if ( $basepath eq '' or $basepath eq '/' ) {
        return $abspath;
    }

    # our formula is below;
    return Cpanel::Path::Normalize::normalize( ( '../' x _count_tokens( $basepath, '/' ) ) . $abspath );
}

sub _clean_base_path {
    my $basepath = shift;

    # If basepath is not defined, then make it absolute to CWD
    if ( !defined($basepath) || $basepath eq '' ) {
        $basepath = Cwd::fastcwd();
    }

    $basepath = getdir($basepath);

    # Basepath must absolutely exist and be defined
    if ( !Cpanel::StringFunc::Match::beginmatch( $basepath, '/' ) ) {
        $basepath = Cwd::fastcwd() . '/' . $basepath;
        $basepath = getdir($basepath);

        if ( !-e $basepath ) {
            Cpanel::Logger::cplog( "Unable to determine absolute base path.", 'warn', __PACKAGE__ );
            return '';
        }
    }
    elsif ( !-e $basepath ) {
        Cpanel::Logger::cplog( "$basepath does not exist.", 'warn', __PACKAGE__ );
        return '';
    }
    return Cpanel::Path::Normalize::normalize($basepath);
}

sub relative2abspath {
    my $relpath  = shift;
    my $basepath = shift;

    if ( Cpanel::StringFunc::Match::beginmatch( $relpath, '/' ) ) {

        # We don't care if you send an absolute path, just clean and return it
        return Cpanel::Path::Normalize::normalize($relpath);
    }

    # If the relpath exists then job is easy
    if ( -e $relpath ) {    # Relative to CWD
        $relpath = Cwd::fastcwd() . '/' . $relpath;
        $relpath = Cpanel::Path::Normalize::normalize($relpath);
        return $relpath;
    }

    $basepath = _clean_base_path($basepath);
    if ( !defined($basepath) || $basepath eq '' ) {
        return '';
    }

    $relpath = Cpanel::Path::Normalize::normalize($relpath);
    return calcabspath( $relpath, $basepath );
}

sub abs2relativepath {
    my $abspath  = shift;
    my $basepath = shift;

    if ( !Cpanel::StringFunc::Match::beginmatch( $abspath, '/' ) ) {
        $abspath = relative2abspath($abspath);
    }
    else {
        $abspath = Cpanel::Path::Normalize::normalize($abspath);
    }

    $basepath = _clean_base_path($basepath);
    if ( !defined($basepath) || $basepath eq '' ) {
        return '';
    }
    return calcrelpath( $abspath, $basepath );
}

1;
