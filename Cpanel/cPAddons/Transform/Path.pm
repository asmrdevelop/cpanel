
# cpanel - Cpanel/cPAddons/Transform/Path.pm       Copyright 2022 cPanel, L.L.C.
#                                                           All rights reserved.
# copyright@cpanel.net                                         http://cpanel.net
# This code is subject to the cPanel license. Unauthorized copying is prohibited

package Cpanel::cPAddons::Transform::Path;

use strict;
use warnings;
use File::Spec;

=head1 MODULE

C<Cpanel::cPAddons::Transform::Path>

=head1 DESCRIPTION

C<Cpanel::cPAddons::Transform::Path> provides small transform methods related to file paths used in the Addon transform system.

=head1 FUNCTIONS

=head2 canonicalize(PATH)

Simplifies a path to its cleanest form.

=head3 ARGUMENTS

=over

=item B<PATH> - String

Path to simplify.

=back

=head3 RETURNS

String - Simplified path

=head3 EXAMPLE

  print Cpanel::cPAddons::Transform::Path::canonicalize('/abc/');
  # print /abc/

  print Cpanel::cPAddons::Transform::Path::canonicalize('./abc');
  # print abc

  print Cpanel::cPAddons::Transform::Path::canonicalize('/abc/.//');
  # print /abc/

=cut

sub canonicalize {
    my $path = shift;
    die 'canonicalize() unexpectedly found “..” in path' if $path =~ /\.\./;
    return File::Spec->canonpath($path);
}

1;
