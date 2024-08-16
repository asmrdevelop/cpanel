
# cpanel - Cpanel/Validate/Homedir.pm              Copyright 2022 cPanel, L.L.C.
#                                                           All rights reserved.
# copyright@cpanel.net                                         http://cpanel.net
# This code is subject to the cPanel license. Unauthorized copying is prohibited

package Cpanel::Validate::Homedir;

use strict;
use warnings;

use Cpanel::Path::Homedir ();
use Cpanel::Path::Resolve ();
use Cpanel::Exception     ();

=head1 MODULE

C<Cpanel::Validate::Homedir>

=head1 DESCRIPTION

C<Cpanel::Validate::Homedir> provides validators that check if a path
is based in a user's home directory. If you do not pass the user, then the
home directory for the current user is used.

=head1 SYNOPSIS

  my $path = '/home/cpuser/sample';
  use Cpanel::Validate::Homedir ();
  if (Cpanel::Validate::Homedir::path_is_in_homedir($path)) {
    # path is in the user's homedir
  }

  if (!Cpanel::Validate::Homedir::path_is_in_homedir($path, 'otheruser')) {
    # path is not in the 'otheruser' user's homedir.
  }

  Cpanel::Validate::Homedir::path_is_in_homedir_or_die($path);


=head1 FUNCTIONS

=head2 path_is_in_homedir(PATH, USER)

Check if the path is in the user's home directory.

=head3 ARGUMENTS

=over

=item PATH - string

Required. Path to check.

=item USER - string

Optional. If not provided, it will look up the homedir for the current user.

=back

=head3 RETURNS

1 when the path is in the user's home directory. 0 otherwise.

=cut

sub path_is_in_homedir {
    my ( $path, $user ) = @_;
    my $homedir  = Cpanel::Path::Homedir::get_homedir($user);
    my $abs_path = Cpanel::Path::Resolve::resolve_path( $path, $user );
    return $abs_path eq $homedir || ( index( $abs_path, $homedir . '/' ) == 0 ) ? 1 : 0;
}

=head2 path_is_in_homedir_or_die(PATH, USER)

Die if the path is not in the user home directory.

=head3 ARGUMENTS

=over

=item PATH - string

Required. Path to check.

=item USER - string

Optional. If not provided, it will look up the home directory for the current user.

=back

=head3 THROWS

=over

=item When the path is not based in the user's home directory.

=back

=cut

sub path_is_in_homedir_or_die {
    my ( $path, $user ) = @_;
    my $homedir  = Cpanel::Path::Homedir::get_homedir($user);
    my $abs_path = Cpanel::Path::Resolve::resolve_path( $path, $user );
    if ( $abs_path ne $homedir && !( index( $abs_path, $homedir . '/' ) == 0 ) ) {
        die Cpanel::Exception::create( 'PathNotInDirectory', [ path => $path, base => $homedir ] );
    }
    return;
}

1;
