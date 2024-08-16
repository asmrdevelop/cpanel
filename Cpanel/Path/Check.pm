
# cpanel - Cpanel/Path/Check.pm                    Copyright 2022 cPanel, L.L.C.
#                                                           All rights reserved.
# copyright@cpanel.net                                         http://cpanel.net
# This code is subject to the cPanel license. Unauthorized copying is prohibited

package Cpanel::Path::Check;

use strict;
use warnings;

=head1 MODULE

C<Cpanel::Path::Check>

=head1 DESCRIPTION

C<Cpanel::Path::Check> provides common helpers for checking path related conditions.

=head1 SYNOPSIS

  use Cpanel::Path::Check;

=head1 FUNCTIONS

=head2 is_absolute_path(PATH)

=head3 ARGUMENTS

=over

=item PATH - string

Path to check.

=back

=head3 RETURNS

1 when the PATH is an absolute path, 0 otherwise.

=cut

sub is_absolute_path {
    my $path = shift;
    die 'Missing path' if !defined $path;
    return index( $path, '/' ) == 0 ? 1 : 0;
}

=head2 is_relative_path(PATH)

=head3 ARGUMENTS

=over

=item PATH - string

Path to check.

=back

=head3 RETURNS

1 when the PATH is a relative path, 0 otherwise.

=cut

sub is_relative_path {
    my $path = shift;
    return is_absolute_path($path) ? 0 : 1;
}

1;
