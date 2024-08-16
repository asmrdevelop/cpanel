
# cpanel - Cpanel/Path/Homedir.pm                  Copyright 2022 cPanel, L.L.C.
#                                                           All rights reserved.
# copyright@cpanel.net                                         http://cpanel.net
# This code is subject to the cPanel license. Unauthorized copying is prohibited

package Cpanel::Path::Homedir;

use strict;
use warnings;

use Cpanel::PwCache     ();
use Cpanel::Path::Check ();

=head1 MODULE

C<Cpanel::Path::Homedir>

=head1 DESCRIPTION

<Cpanel::Path::Homedir> provides helpers related to home
directory resolution and path manipulation.

=head1 SYNOPSIS

  use Cpanel::Path::Homedir;

=head1 FUNCTIONS

=head2 get_homedir(USER)

Get the home directory for the user.

=head3 ARGUMENTS

=over

=item USER - string

Optional. If not provided, will assume the current user.

=back

=head3 RETURNS

string - the home directory for the user.

=cut

sub get_homedir {
    my ($user) = @_;
    if ( !defined $user ) {
        return $Cpanel::homedir // Cpanel::PwCache::gethomedir($>);
    }
    return Cpanel::PwCache::gethomedir($user);
}

=head2 assume_homedir(PATH, USER)

If the path is relative, it prepends the users home directory to the path.

=head3 ARGUMENTS

=over

=item PATH - string

Required. Path to adjust.

=item USER - string

Optional. User to get the home directory for. If not provided, it will use the
current users home directory.

=back

=head3 RETURNS

string - the adjusted path.

=cut

sub assume_homedir {
    my ( $path, $user ) = @_;
    if ( !Cpanel::Path::Check::is_absolute_path($path) ) {

        # Its a relative path and we will put it in the
        # users /home/{user}/ folder.
        $path = get_homedir($user) . '/' . $path;
    }
    return $path;
}

1;
