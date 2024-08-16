# cpanel - Cpanel/API/DirectoryProtection.pm       Copyright 2022 cPanel, L.L.C.
#                                                           All rights Reserved.
# copyright@cpanel.net                                         http://cpanel.net
# This code is subject to the cPanel license. Unauthorized copying is prohibited

package Cpanel::API::DirectoryProtection;

use strict;
use warnings;

use Cpanel::Htaccess ();

=head1 MODULE

C<Cpanel::API::DirectoryProtection>

=head1 DESCRIPTION

C<Cpanel::API::DirectoryProtection> provides API access to control the LeechProtect feature. LeechProtection
is used in conjunction with Directory Privacy to protect website basic auth logins from brute force attacks.
The feature is implemented using a Rewrite Condition rule in the .htaccess file for a specific directory.
When the user attempts to authenticate, C<bin/leechprotect> is run to validate that the login is not being brute
force attacked. See C<bin/leechprotect> for more details on how brute force attacks are detected.

=head1 FUNCTIONS

=head2 list_directories(  dir => ...)

Get the list of child directories and their status.

=head3 ARGUMENTS

=over

=item dir - string

Full path to the directory you want a list of child directories for.

=back

=head3 RETURNS

Hashref with the following properties:

=over

=item home - hashref

Information about the user's home directory on the server.

=over

=item path - string

The path on disk.

=item state - hashref

=over

=item error - string

Only present if the system fails to retrieve the directory's leech protection status.

=item has_leech_protection - Boolean

1 if protected, 0 if not protected.

=back

=back

=item parent - hashref

Information about the parent directory of the current path if it is not the home directory.

=over

=item path - string

The path on disk.

=item state - hashref

=over

=item error - string

Only present if the system fails to retrieve the directory's leech protection status.

=item has_leech_protection - Boolean

1 if protected, 0 if not protected.

=back

=back

=item current - hashref

The currently-selected directory.

=over

=item path - string

The directory's path on disk.

=item state - hashref

=over

=item error - string

Only present if the system fails to retrieve the directory's leech protection status.

=item has_leech_protection - Boolean

1 if protected, 0 if not protected.

=back

=back

=item children - array

List of child directories and their leech protection status. Each item is a hashref with the following properties:

=over

=item path - string

The path on disk.

=item state - hashref

=over

=item error - string

Only present if the system fails to retrieve the directory's leech protection status.

=item has_leech_protection - Boolean

1 if protected, 0 if not protected.

=back

=back

=back

=cut

sub list_directories {
    my ( $args, $result ) = @_;

    my $dir = $args->get_length_required('dir');

    local $@;
    my $data = eval { Cpanel::Htaccess::list_directories( $dir, leech_protection => 1 ) };
    _simplify_exception($@);

    $result->data($data);
    return 1;
}

# Strip out non-user cruft from the exception when possible.
sub _simplify_exception {
    my ($exception) = @_;
    if ($exception) {
        if ( eval { $exception->isa('Cpanel::Exception') } ) {
            $exception = $exception->get_string_no_id();
        }
        die $exception =~ s/\n?$/\n/r;
    }
}

my $webprotect_mutating = {
    needs_feature => 'webprotect',
    needs_role    => 'WebServer',
};

my $webprotect_non_mutating = {
    %$webprotect_mutating,
    allow_demo => 1,
};

our %API = ( list_directories => $webprotect_non_mutating );

1;
