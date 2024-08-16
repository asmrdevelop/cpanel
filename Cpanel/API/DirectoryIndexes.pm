# cpanel - Cpanel/API/DirectoryIndexes.pm          Copyright 2022 cPanel, L.L.C.
#                                                           All rights Reserved.
# copyright@cpanel.net                                         http://cpanel.net
# This code is subject to the cPanel license. Unauthorized copying is prohibited

package Cpanel::API::DirectoryIndexes;

use strict;
use warnings;

use Cpanel::Htaccess                    ();
use Cpanel::DirectoryIndexes::IndexType ();

=head1 MODULE

C<Cpanel::API::DirectoryIndexes>

=head1 DESCRIPTION

C<Cpanel::API::DirectoryIndexes> provides API access to control the
DirectoryIndexes setting for directories without index pages (index.htm,
index.html, index.php, ...)

=head1 FUNCTIONS

=head2 get_indexing(  dir => ...)

Get the directory indexing setting for a given directory.

=head3 ARGUMENTS

=over

=item dir - string

The full path to the directory you want to view the settings for.

=back

=head3 RETURNS

A string with one of four possible values:

=over

=item inherit

The directory uses the server's default directory listings setting.

=item disabled

Directory indexes are disabled.

=item standard

Directory indexes are enabled and display in the standard format.

=item fancy

Directory indexes are enabled and display in the Fancy format.
L<http://httpd.apache.org/docs/trunk/mod/mod_autoindex.html#IndexOptions>

=back

=head3 THROWS

=over

=item When one of the required arguments is missing.

=item When fetching the directory index configuration fails.

=back

=cut

sub get_indexing {
    my ( $args, $result ) = @_;

    my $dir = $args->get_length_required('dir');

    local $@;
    my $type = eval { Cpanel::Htaccess::indextype( $dir, uapi => 1 ) };
    _simplify_exception($@);

    $result->data( Cpanel::DirectoryIndexes::IndexType::internal_to_external($type) );
    return 1;
}

=head2 set_indexing ( dir => ..., type => ...)

=head3 ARGUMENTS

=over

=item dir - string

Full path to the directory you want to change the setting for.

=item type - string

The new indexing setting for the directory.

One of four possible values:

=over

=item inherit

This directory has no explicit setting and will inherit the server's default.

=item disabled

Directory indexes are disabled.

=item standard

Directory indexes are enabled.

=item fancy

Directory indexes are enabled and configured to be Fancy
L<http://httpd.apache.org/docs/trunk/mod/mod_autoindex.html#IndexOptions>

=back

=back

=head3 RETURNS

The type the index is now set to. Same as C<get_indexing> values.

=head3 THROWS

=over

=item When one of the required arguments is missing.

=item When the value passed with the type argument is not one of the defined types.

=item When setting the directory index configuration fails.

=back

=cut

sub set_indexing {
    my ( $args, $result ) = @_;

    my $dir  = $args->get_length_required('dir');
    my $type = $args->get_length_required('type');

    local $@;
    eval { Cpanel::Htaccess::setindex( $dir, Cpanel::DirectoryIndexes::IndexType::external_to_internal($type), uapi => 1 ) };
    _simplify_exception($@);

    $result->data($type);    # If we're here, we succeeded. This also means that $type will be valid.
    return 1;
}

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

Only present if the function failed to retrieve the state.

=item index_type - string

The new indexing setting for the directory.

One of four possible values:

=over

=item inherit

This directory has no explicit setting and will inherit the server's default.

=item disabled

Directory indexes are disabled.

=item standard

Directory indexes are enabled.

=item fancy

Directory indexes are enabled and configured to be Fancy.
L<http://httpd.apache.org/docs/trunk/mod/mod_autoindex.html#IndexOptions>

=back

=back

=back

=item parent - hashref

Information about the parent directory of the current path if it's not the home directory.

=over

=item path - string

The path on disk.

=item state - hashref

=over

=item error - string

Only present if the function failed to retrieve the state.

=item index_type - string

The new indexing setting for the directory.

One of four possible values:

=over

=item inherit

This directory has no explicit setting and will inherit the server's default.

=item disabled

Directory indexes are disabled.

=item standard

Directory indexes are enabled.

=item fancy

Directory indexes are enabled and configured to be Fancy
L<http://httpd.apache.org/docs/trunk/mod/mod_autoindex.html#IndexOptions>

=back

=back

=back

=item current - hashref

The currently selected folder.

=over

=item path - string

What the path to the home folder is on disk.

=item state - hashref

=over

=item error - string

Only present if the function failed to retrieve the state.

=item index_type - string

The new indexing setting for the directory.

One of four possible values:

=over

=item inherit

This directory has no explicit setting and will inherit the server's default.

=item disabled

Directory indexes are disabled.

=item standard

Directory indexes are enabled.

=item fancy

Directory indexes are enabled and configured to be Fancy
L<http://httpd.apache.org/docs/trunk/mod/mod_autoindex.html#IndexOptions>

=back

=back

=back

=item children - array

List of child folders and their state. Each item is a hashref with the following properties:

=item path - string

The path on disk.

=item state - hashref

=over

=item error - string

Only present if the function failed to retrieve the state.

=item index_type - string

The new indexing setting for the directory.

One of four possible values:

=over

=item inherit

This directory has no explicit setting and will inherit the server's default.

=item disabled

Directory indexes are disabled.

=item standard

Directory indexes are enabled.

=item fancy

Directory indexes are enabled and configured to be Fancy
L<http://httpd.apache.org/docs/trunk/mod/mod_autoindex.html#IndexOptions>

=back

=back

=back

=cut

sub list_directories {
    my ( $args, $result ) = @_;

    my $dir = $args->get_length_required('dir');

    local $@;
    my $data = eval { Cpanel::Htaccess::list_directories( $dir, directory_indexed => 1, uapi => 1 ) };
    _simplify_exception($@);

    $result->data($data);
    return 1;
}

=head2 _simplify_exception ( $exception ) [PRIVATE]

Strip out non-user cruft from the exception when possible.

=head3 ARGUMENTS

=over

=item exception - string

The exception to die with.

=back

=cut

# Strip out non-user cruft from the exception when possible.
sub _simplify_exception {
    my ($exception) = @_;
    if ($exception) {
        if ( eval { $exception->isa('Cpanel::Exception') } ) {
            $exception = $exception->get_string_no_id();
        }
        die $exception =~ s/\n?$/\n/r;
    }
    return;
}

my $indexmanager_mutating = {
    needs_feature => 'indexmanager',
    needs_role    => 'WebServer',
};

my $indexmanager_non_mutating = {
    %$indexmanager_mutating,
    allow_demo => 1,
};

our %API = (
    set_indexing     => $indexmanager_mutating,
    get_indexing     => $indexmanager_non_mutating,
    list_directories => $indexmanager_non_mutating,
);

1;
