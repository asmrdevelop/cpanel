
# cpanel - Cpanel/cPAddons/File/Perms.pm           Copyright 2022 cPanel, L.L.C.
#                                                           All rights reserved.
# copyright@cpanel.net                                         http://cpanel.net
# This code is subject to the cPanel license. Unauthorized copying is prohibited

package Cpanel::cPAddons::File::Perms;

use strict;
use warnings;

use Cpanel::Config::Httpd::Perms ();

use Cpanel::Imports;

=head1 NAME

Cpanel::cPAddons::File::Perms

=head1 DESCRIPTION

Utility module that handles checking if the webserver is running as the user or nobody.

Also provides methods to fix the permissions for a file list.

=head1 METHODS

=head2 Cpanel::cPAddons::File::Perms::runs_as_user()

Checks if the web server is running mod_suphp, mod_ruid2, or mpm_itk. If it is, the scripts
will run as the owner. Otherwise the scripts will run as the nobody or apache users.

=head3 RETURNS

boolean - true if it runs scripts as the owner, false otherwise.

=cut

sub runs_as_user {
    return Cpanel::Config::Httpd::Perms::webserver_runs_as_user(
        ruid2  => 1,
        itk    => 1,
        suphp  => 1,
        suexec => 1,
    );
}

=head2 Cpanel::cPAddons::File::Perms::fix()

Sets the list of files to the specified permission.

=head3 ARGUMENTS

=over

=item files

array ref - list of full paths to files to change.

=back

=over

=item perms

number - permission to set. Examples are: 0644, 0600, ...

=back

=head3 RETURNS

list with two items:

=over

=item [0]

number - if non-0 then there was an error.

  0 - no error.
  3 - argument error.
  4 - chmod call error.

=back

=over

=item [1]

string - error message if any.

=back

=cut

sub fix {
    my ( $files, $perms ) = @_;
    if ( !$files || $files && ref $files ne 'ARRAY' ) {
        return ( 3, locale()->maketext('No files passed.') );
    }

    if ( !$perms ) {
        return ( 3, locale()->maketext('No permission passed.') );
    }

    if ( !chmod $perms, @$files ) {
        return ( 4, $! );
    }

    return ( 0, '' );
}

1;
