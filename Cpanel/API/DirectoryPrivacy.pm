# cpanel - Cpanel/API/DirectoryPrivacy.pm          Copyright 2022 cPanel, L.L.C.
#                                                           All rights Reserved.
# copyright@cpanel.net                                         http://cpanel.net
# This code is subject to the cPanel license. Unauthorized copying is prohibited

package Cpanel::API::DirectoryPrivacy;

use strict;
use warnings;

use Cpanel::Htaccess            ();
use Cpanel::HttpUtils::Htpasswd ();

=head1 MODULE

C<Cpanel::API::DirectoryPrivacy>

=head1 DESCRIPTION

C<Cpanel::API::DirectoryPrivacy> provides API access to controlling .htaccess files for
a cpanel user.

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

=back

=item parent - hashref

Information about the parent directory of the current path if it is not the home directory.

=over

=item path - string

The path on disk.

=back

=item current - hashref

The currently-selected directory.

=over

=item path - string

The home directory's path on disk.

=back

=item children - array

List of child directories and their privacy information. Each item is a hashref with the following properties:

=item path - string

The path on disk.

=item state - hashref

=over

=item error - string

Only present if the system fails to retrieve the directory's privacy information.

=item auth_type - string

Type of authentication. Currently will only return Basic.

=item auth_name - string

Name used for the resource.

=item passwd_file - string

Path to the password file on disk.

=item protected - Boolean

1 if protected, 0 if not protected.

=back

=back


=cut

sub list_directories {
    my ( $args, $result ) = @_;

    my $dir = $args->get_length_required('dir');

    local $@;
    my $data = eval { Cpanel::Htaccess::list_directories( $dir, directory_privacy => 1 ) };
    _simplify_exception($@);

    $result->data($data);
    return 1;
}

=head2 is_directory_protected(dir => ...)

Check if the requested directory uses password protection.

=head3 ARGUMENTS

=over

=item dir - string

The full path to the directory to check for password protection.

=back

=head3 RETURNS

Hashref with the following properties:

=over

=item auth_type - string

Type of authentication. Currently will only return Basic.

=item auth_name - string

Name used for the resource.

=item passwd_file - string

Path to the password file on disk.

=item protected - Boolean

1 if protected, 0 if not protected.

=back

=cut

sub is_directory_protected {
    my ( $args, $result ) = @_;
    my $dir = $args->get_length_required('dir');

    local $@;
    my $data = eval { Cpanel::Htaccess::is_protected($dir) };
    _simplify_exception($@);

    $result->data($data);
    return 1;
}

=head2 configure_directory_protection(dir => ..., enabled => ..., authname => ...)

Enable or disable the password protection for the indicated directory. Password
protected directories are controlled by .htaccess files using basic authentication.

Warning: Basic Auth sends passwords in clear text over the wire.

Note: Once protection is enabled, you can use the C<Htaccess::add_user()> and
C<Htaccess::delete_user()> api to add and remove users to the passwd database
for this directory.

=head3 ARGUMENTS

=over

=item dir - string

Full path to the directory you want to set the password protection for.

=item enabled - Boolean

1 to enable password protection, 0 to disable password protection.

=item authname - required when enabling, this is the name to use for the resource you are securing.  This parameter is only used when
enabling password protection. It is ignored for disabling password protection.

=back

=head3 RETURNS

Hashref with the current state of protection. This hash returns the following properties:

=over

=item auth_type - string

Type of authentication. Currently will only return Basic.

=item auth_name - string

Name used for the resource.

=item passwd_file - string

Path to the password file on disk.

=item protected - Boolean

1 if protected, 0 if not protected.

=back

=cut

sub configure_directory_protection {
    my ( $args, $result ) = @_;
    my $dir     = $args->get_length_required('dir');
    my $enabled = $args->get_required('enabled');
    my $authname;
    if ($enabled) {
        $authname = $args->get_length_required('authname');
        require Cpanel::Validate::Ascii;
        Cpanel::Validate::Ascii::validate_ascii_or_die( $authname, 'authname', print_only => 1 );
    }

    require Cpanel::Validate::Boolean;
    Cpanel::Validate::Boolean::validate_or_die( $enabled, 'enabled' );

    local $@;
    my $data = eval { Cpanel::Htaccess::set_protected( $dir, $enabled, $authname ) };
    _simplify_exception($@);
    $result->data($data);
    return 1;
}

=head2 list_users(dir => ...)

Get the list of users that are listed in the passwd file for this directory.

Note these users may or may not be currently used depending on if the directory
protection is enabled for the directory.

=head3 ARGUMENTS

=over

=item dir - string

Full path to the directory that you want a list of users for.

=back

=head3 RETURNS

string[] - List of users that can access the requested directory if it is protected
and if the user can provide the matching password.

=cut

sub list_users {
    my ( $args, $result ) = @_;
    my $dir = $args->get_length_required('dir');

    local $@;
    my $data = eval { Cpanel::HttpUtils::Htpasswd::list_users($dir) };
    _simplify_exception($@);

    $result->data($data);
    return 1;
}

=head2 add_user(dir => ..., user => ..., password => ...)

Add a user to the protected directory user database for the given directory.

=head3 ARGUMENTS

=over

=item dir - string

The user-owned directory for which to add a user.

=item user - string

User name to add to the password file.

=item password - string

Clear text password for the user.

=back

=head3 EXCEPTIONS

=over

=item Missing parameters

=item Invalid parameters

=item Password file locked by other write operation.

=item Current user does not own a resource needed to proceed.

=item Possibly others.

=back

=cut

sub add_user {
    my ( $args, $result ) = @_;
    my $dir      = $args->get_length_required('dir');
    my $user     = $args->get_length_required('user');
    my $password = $args->get_length_required('password');

    local $@;
    my $ret = eval { Cpanel::HttpUtils::Htpasswd::add_user( $dir, $user, $password ) };
    _simplify_exception($@);
    return $ret;
}

=head2 delete_user(dir, user)

Remove a user from the protected directory password file.

=head3 ARGUMENTS

=over

=item dir - string

The user-owned directory from which to remove a user.

=item user - string

User name to remove from the password file.

=back

=head3 EXCEPTIONS

=over

=item Missing parameters

=item Invalid parameters

=item Password file locked by other write operation.

=item Current user does not own a resource needed to proceed.

=item Possibly others.

=back

=cut

sub delete_user {
    my ( $args, $result ) = @_;
    my $dir  = $args->get_length_required('dir');
    my $user = $args->get_length_required('user');

    local $@;
    my $ret = eval { Cpanel::HttpUtils::Htpasswd::delete_user( $dir, $user ); };
    _simplify_exception($@);
    return $ret;
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

our %API = (
    list_directories               => $webprotect_non_mutating,
    is_directory_protected         => $webprotect_non_mutating,
    configure_directory_protection => $webprotect_mutating,
    list_users                     => $webprotect_non_mutating,
    add_user                       => $webprotect_mutating,
    delete_user                    => $webprotect_mutating,
);

1;
