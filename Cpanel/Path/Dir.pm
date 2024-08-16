package Cpanel::Path::Dir;

# cpanel - Cpanel/Path/Dir.pm                      Copyright 2022 cPanel, L.L.C.
#                                                           All rights reserved.
# copyright@cpanel.net                                         http://cpanel.net
# This code is subject to the cPanel license. Unauthorized copying is prohibited

use strict;
use warnings;
use Cpanel::Context   ();
use Cpanel::Exception ();

=head1 MODULE

C<Cpanel::Path::Dir>

=head1 DESCRIPTION

<Cpanel::Path::Dir> provides helpers related to directory path manipulation.

=head1 SYNOPSIS

  use Cpanel::Path::Dir ();

  my $dir = normalize_dir('//home//user/');
  # $dir is '/home/user'

  my $is_same = dir_is_the_same('/home', '/home');
  # $is_same is true

  my $dir_is_below = dir_is_below('/home/user', '/home');
  # $dir_is_below is true

  my $relative_dir = relative_dir('/home/user/foo', '/home');
  # $relative_dir is 'user/foo'

  my @intermediate_dirs = intermediate_dirs('/home', '/home/user/foo/bar');
  # @intermediate_dirs is ( '/home/user', '/home/user/foo' )

=head1 FUNCTIONS

=head2 normalize_dir($DIR)

Collapses series of slashes to a single slash, and removes any trailing slash.

=head3 ARGUMENTS

=over

=item DIR - string

Required. The directory path to normalize.

=back

=head3 RETURNS

string - the normalized path.

=cut

sub normalize_dir {
    my ($dir) = @_;

    $dir =~ s{/+}{/}g;
    $dir =~ s{/$}{};

    return $dir;

}

=head2 dir_is_the_same(DIR1, DIR2)

Check if two normalized paths are the same.

=head3 ARGUMENTS

=over

=item DIR1 - string

Required. A path.

=item DIR2 - string

Required. A path.

=back

=head3 RETURNS

string - 0 if false, 1 if true.

=cut

sub dir_is_the_same {
    my ( $dir, $testdir ) = @_;

    $dir     = normalize_dir($dir);
    $testdir = normalize_dir($testdir);

    return 1 if $dir eq $testdir;

    return 0;
}

=head2 dir_is_below(DIR, BASEDIR)

Check if one path is a subdirectory of the other.

=head3 ARGUMENTS

=over

=item DIR - string

Required. A path that is possibly the child of BASEDIR.

=item BASEDIR - string

Required. A path that is possibly the parent of DIR.

=back

=head3 RETURNS

string - 0 if false, 1 if true.

=cut

sub dir_is_below {
    my ( $dir, $testdir ) = @_;

    $dir     = normalize_dir($dir);
    $testdir = normalize_dir($testdir);

    return 0 if $dir eq $testdir;

    # First check  -- is the dir (when restricted to length of test string) same as test string?
    # Second check -- Are we sure we're not being fooled by the path component containing the test string (CPANEL-23029)?
    if ( substr( $dir, 0, length $testdir ) eq $testdir && index( substr( $dir, length $testdir ), "/" ) == 0 ) {
        return 1;
    }

    return 0;
}

=head2 relative_dir(DIR, BASEDIR)

Calculate the relative path between BASEDIR and DIR.

=head3 ARGUMENTS

=over

=item DIR - string

Required. A path that may be a subdirectory of BASEDIR.

=item BASEDIR - string

Required. A path that may be a parent directory of DIR.

=back

=head3 RETURNS

string - BASEDIR prefix and trailing slash have been removed from DIR, providing the relative portion.
If the BASEDIR prefix can not be removed from DIR then the full DIR string is returned.

=cut

sub relative_dir {
    my ( $dir, $basedir ) = @_;

    $dir     = normalize_dir($dir);
    $basedir = normalize_dir($basedir);

    $dir =~ s{^\Q$basedir\E/?}{};

    return normalize_dir($dir);
}

=head2 intermediate_dirs(BASEDIR, SUBDIR)

Generate a list of any intermediate directories that exist between BASEDIR and SUBDIR.

=head3 ARGUMENTS

=over

=item BASEDIR - string

Required. A path that may be a parent directory of BASEDIR.

=item SUBDIR - string

Required. A path that may be a subdirectory of BASEDIR.

=back

=head3 RETURNS

list - Zero or more intermediate directories. Does not include BASEDIR or SUBDIR.

=cut

sub intermediate_dirs {
    my ( $basedir, $subdir ) = @_;

    Cpanel::Context::must_be_list();

    # Empty basedir would be treated like '/'. Must check before normalization.
    die Cpanel::Exception::create( 'InvalidParameter', 'The [list_and_quoted,_1] [numerate,_2,argument,arguments] cannot be empty.', [ ['basedir'], 1 ] ) unless length $basedir;

    return unless dir_is_below( $subdir, $basedir );

    $basedir = normalize_dir($basedir);

    my @nodes = split( q{/}, relative_dir( $subdir, $basedir ) );
    pop @nodes;    # Last node is subdir itself
    my @intermediates;
    while (@nodes) {
        unshift @intermediates, ( "$basedir/" . join( q{/}, @nodes ) );
        pop @nodes;
    }
    return @intermediates;
}

1;
