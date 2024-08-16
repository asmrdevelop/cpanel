
# cpanel - Cpanel/Path/Resolve.pm                  Copyright 2022 cPanel, L.L.C.
#                                                           All rights reserved.
# copyright@cpanel.net                                         http://cpanel.net
# This code is subject to the cPanel license. Unauthorized copying is prohibited

package Cpanel::Path::Resolve;

use strict;
use warnings;

use Cpanel::Exception       ();
use Cpanel::Path::Homedir   ();
use Cpanel::Path::Normalize ();

=head1 MODULE

C<Cpanel::Path::Resolve>

=head1 DESCRIPTION

C<Cpanel::Path::Resolve> provides helpers to resolve user paths.

=head1 SYNOPSIS

  use Cpanel::Path::Resolve;

=head1 FUNCTIONS

=cut

=head2 resolve_path(PATH, USER)

=head3 ARGUMENTS

=over

=item PATH - string

Required. Path to resolve.

=item USER - string

Optional. If provided, will assume the home directory for the user for relative paths.
Otherwise, it assumes the current user's home directory for relative paths.

=back

=head3 RETURNS

string - fully resolved path

=head3 THROWS

=over

=item When the path can not be resolved.

=back

=cut

sub resolve_path {
    my ( $path, $user ) = @_;
    die 'Missing path' if !defined $path;

    $path = Cpanel::Path::Homedir::assume_homedir($path);

    # Get the canonical path.
    my $abs_path = Cpanel::Path::Normalize::normalize($path);
    if ( !defined $abs_path ) {
        die Cpanel::Exception::create( 'InvalidParameter', 'The system failed to locate the “[_1]” filepath on the disk.', [$path] );
    }

    return $abs_path;
}

1;
