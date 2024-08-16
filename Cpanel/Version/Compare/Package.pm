package Cpanel::Version::Compare::Package;

# cpanel - Cpanel/Version/Compare/Package.pm        Copyright 2022 cPanel, L.L.C.
#                                                            All rights Reserved.
# copyright@cpanel.net                                          http://cpanel.net
# This code is subject to the cPanel license.  Unauthorized copying is prohibited

use cPstrict;

=head1 FUNCTIONS

=head2 C<< version_string_cmp($version1, $version2) >>

Compares package version strings in the form of "epoch:version-release".  The
"epoch:" and "-release" components may be omitted.

B<Returns:> as C<cmp> would: -1, 0, or 1 when $version1 is before, equivalent
to, or after $version2.

=cut

sub version_string_cmp ( $ver1, $ver2 ) {

    # Split the version string into its constituent parts (Epoch, Version, &
    # Release) and then compare each in turn.
    my ( $e1, $v1, $r1 ) = $ver1 =~ m/(?:(\d+):)?([^:-]+)(?:-([^:-]+))?/a;
    my ( $e2, $v2, $r2 ) = $ver2 =~ m/(?:(\d+):)?([^:-]+)(?:-([^:-]+))?/a;

    # First compare epochs, which must be an integer.  They are 0 if not
    # specified.
    my $cmp = ( $e1 || 0 ) <=> ( $e2 || 0 );
    return $cmp if $cmp;

    # Compare the version and then the release fields using the RPM sorting
    # algorithm.
    return version_cmp( $v1, $v2 ) || version_cmp( $r1 || '', $r2 || '' );
}

=head2 C<< version_cmp($version1, $version2) >>

Compares Package versions in a manner that approximates librpm's comparison
algorithm.  This algorithm can be used for comparing the individual version or
release values, but should B<not> be used to compare the combined
version-release; see C<version_string_cmp>.

=cut

# This algorithm is taken from http://stackoverflow.com/a/3206477.
sub version_cmp ( $ver1, $ver2 ) {

    # Split into alpha xor numeric groups, which define the individual sections
    # that will be compared.  Discard all other characters.
    my @v1 = ( $ver1 =~ m/([a-zA-Z]+|[0-9]+)/g );
    my @v2 = ( $ver2 =~ m/([a-zA-Z]+|[0-9]+)/g );

    # Compare each section in succession until the values no longer match.
    while ( @v1 && @v2 ) {
        my $s1 = shift @v1;
        my $s2 = shift @v2;

        # Numeric sections are compared numerically (<=>); alphabetic sections
        # are compared lexicographically (cmp).  If one of the versions has a
        # numeric section and the other alphabetic, the numeric version is
        # newer.
        if ( $s1 =~ m/\d/a ) {
            return 1 if $s2 =~ m/\D/a;    # Handle numeric/alphabetic mismatch.
            my $cmp = $s1 <=> $s2;
            return $cmp if $cmp;
        }
        else {
            return -1 if $s2 =~ m/\d/a;    # Handle numeric/alphabetic mismatch.
            my $cmp = $s1 cmp $s2;
            return $cmp if $cmp;
        }
    }

    # If one of the versions runs out of parts, the one with more parts is
    # considered newer.
    return @v1 <=> @v2;
}

1;
