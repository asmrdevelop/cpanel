# cpanel - Cpanel/HttpUtils/Htpasswd.pm            Copyright 2022 cPanel, L.L.C.
#                                                           All rights Reserved.
# copyright@cpanel.net                                         http://cpanel.net
# This code is subject to the cPanel license. Unauthorized copying is prohibited
package Cpanel::HttpUtils::Htpasswd;

use strict;
use warnings;

=head1 MODULE

C<Cpanel::HttpUtils::Htpasswd>

=head1 DESCRIPTION

C<Cpanel::HttpUtils::Htpasswd> provides access to the password files
used by cpanel directory protection. These are located in the users
home folder under:

  /home/<user>/.htpasswds/<home relative directory path>/passwd

=cut

use Cpanel::Imports;

use Cpanel                               ();
use Cpanel::AdminBin::Call               ();
use Cpanel::CheckPass::AP                ();
use Cpanel::Exception                    ();
use Cpanel::Rand::Get                    ();
use Cpanel::SafeDir::MK                  ();
use Cpanel::Transaction::File::Raw       ();    # PPI USE OK - dynamic load below
use Cpanel::Transaction::File::RawReader ();    # PPI USE OK - dynamic load below

my $HTPASSWD_PERMS = 0644;

=head1 STATIC PROPERTIES

=head2 MODES

Hash of the modes supported by open method.

=head3 OPTIONS

=over

=item READONLY

Open the passwd file as read-only

=item READWRITE

Open the passwd file as read-write

=back

=cut

our %MODES = (
    READONLY  => 'Cpanel::Transaction::File::RawReader',
    READWRITE => 'Cpanel::Transaction::File::Raw',
);

=head1 FUNCTIONS

=head2 add_user(DIRECTORY, USER, PASSWORD)

=head3 ARGUMENTS

=over

=item DIRECTORY - string

User owned directory that we want to add the user for.

=item USER - string

User name to add to the password file.

=item PASSWORD - string

Clear text password for the user.

=back

=head3 EXCEPTIONS

=over

=item Possibly others.

=back

=head3 ASSUMPTIONS

=over

=item All the parameters are non-empty strings.

=back

=cut

sub add_user {
    my ( $directory, $user, $password ) = @_;

    require Cpanel::SafeDir::Fixup;
    $directory = Cpanel::SafeDir::Fixup::homedirfixup($directory);

    _validate_directory($directory);
    _validate_user($user);
    _validate_password($password);
    _validate_password_strength($password);

    my $random           = Cpanel::Rand::Get::getranddata(256);
    my $encoded_password = Cpanel::CheckPass::AP::apache_md5_crypt( $password, $random );
    my $transaction      = Cpanel::HttpUtils::Htpasswd::open( $directory, $MODES{READWRITE} );

    my @htpasswd = split( m{\n}, ${ $transaction->get_data() } );
    my @lines;
    my $is_update = 0;
    my $new_line  = "$user:$encoded_password";
    for my $line (@htpasswd) {
        if ( $line =~ m/^(\S+):/ ) {
            if ( $1 eq $user ) {

                # Update the record in place
                push @lines, $new_line;
                $is_update = 1;
            }
            else {
                push @lines, $line;
            }
        }
    }

    if ( !$is_update ) {

        # Add it to the end.
        push @lines, $new_line;
    }

    $transaction->set_data( \join( "\n", @lines ) );
    $transaction->save_and_close_or_die();

    return 1;
}

=head2 delete_user(DIRECTORY, USER)

Remove a user from the protected directory password file.

=head3 ARGUMENTS

=over

=item DIRECTORY - string

User owned directory that we want to remove the user.

=item USER - string

User name to remove from the password file.

=back

=head3 EXCEPTIONS

=over

=item Missing parameters

=item Password file locked by other write operation

=item Possibly others.

=back

=cut

sub delete_user {
    my ( $directory, $user ) = @_;

    require Cpanel::SafeDir::Fixup;
    $directory = Cpanel::SafeDir::Fixup::homedirfixup($directory);

    _validate_directory($directory);
    _validate_user($user);

    my $transaction = Cpanel::HttpUtils::Htpasswd::open( $directory, $MODES{READWRITE} );
    my @htpasswd    = split( m{\n}, ${ $transaction->get_data() } . '' );
    my @lines       = grep { $_ !~ /^\Q$user\E:/ } @htpasswd;
    if ( @lines == @htpasswd ) {
        $transaction->close_or_die();
        die Cpanel::Exception::create( 'InvalidParameter', 'The “[_1]” user is not protecting the “[_2]” directory.', [ $user, $directory ] );
    }

    $transaction->set_data( \join( "\n", @lines ) );
    $transaction->save_and_close_or_die();
    return 1;
}

=head2 list_users(DIRECTORY)

List the users for the protected directory.

=head3 ARGUMENTS

=over

=item DIRECTORY - string

User owned directory that we want to list the users for.

=back

=head3 RETURNS

String[] - List of users that can access the requested directory if its protected and if the user can provide the matching password.

=head3 THROWS

=over

=item When the directory requested does not exist.

=back

=cut

sub list_users {
    my ($directory) = @_;

    require Cpanel::SafeDir::Fixup;
    $directory = Cpanel::SafeDir::Fixup::homedirfixup($directory);
    _validate_directory($directory);

    my $transaction = Cpanel::HttpUtils::Htpasswd::open( $directory, $MODES{READONLY} );

    my @lines = split( m{\n}, ${ $transaction->get_data() } || '' );
    my @users;
    for my $line (@lines) {
        next if !$line;
        if ( $line =~ m/^(\S+):/ ) {
            push @users, $1;
        }
    }
    return \@users;
}

=head2 _validate_ownership(PATH) [PRIVATE]

Validate the path is controlled by the current user.

=head3 ARGUMENTS

=over

=item PATH - string

Path to the directory we are checking ownership for.

=back

=head3 RETURNS

1 if ownership is valid.

=head3 THROWS

=over

=item CannotReplaceFile exception if the current user does not own the path

=back
=cut

sub _validate_ownership {
    my ($path) = @_;

    my ( $hta_uid, $hta_gid ) = ( stat $path )[ 4, 5 ];
    my $mismatch = defined($hta_uid) && $hta_uid != $>;

    if ($mismatch) {
        die Cpanel::Exception::create(
            'CannotReplaceFile',
            [
                pid    => $$,
                euid   => $>,
                egid   => $),
                path   => $path,
                fs_uid => $hta_uid,
                fs_gid => $hta_gid,
            ]
        );
    }
    return 1;
}

=head2 _virtual_dir(DIR) [PRIVATE]

Trim out the users home folder and leading / from directory.

These virtual directories are used in various storage systems.

=head3 ARGUMENTS

=over

=item DIR - string

Full path to the desired directory you want to calculate the virtual directory for.

=back

=head3 RETURNS

string - relative directory from the users home directory

=cut

sub _virtual_dir {
    my $vdir = shift;
    $vdir =~ s/^\Q$Cpanel::homedir\E//;
    $vdir =~ s/^\/+//;
    return $vdir;
}

=head2 _ensure_passwd_file_location(DIR) [PRIVATE]

Build the path to the passwd file storage location. Create any
missing folders along that path.

=head3 ARGUMENTS

=over

=item DIR - string

User owned directory to secure with a password.

=back

=head3 RETURNS

string - Path where the passwd file will be placed or read from. Does not include the filename.

=head3 SIDE EFFECTS

Any missing directories along the returned path will be created under the users home folder.

=cut

sub _ensure_passwd_file_location {
    my ($dir) = @_;
    my $store_dir = "$Cpanel::homedir/.htpasswds";
    if ( !-e $store_dir ) {
        Cpanel::SafeDir::MK::safemkdir_or_die($store_dir);
        Cpanel::AdminBin::Call::call( 'Cpanel', 'file_protect', 'PROTECT_DIRECTORY', $store_dir );
    }

    my $vdir = _virtual_dir($dir);
    $store_dir = "$store_dir/$vdir";
    if ( !-e $store_dir ) {
        Cpanel::SafeDir::MK::safemkdir_or_die($store_dir);
        Cpanel::AdminBin::Call::call( 'Cpanel', 'file_protect', 'PROTECT_DIRECTORY', $store_dir );
    }

    $store_dir .= "/" unless $store_dir =~ m</$>;
    return $store_dir;
}

=head2 get_path(DOCROOT)

Get the password file path in /home/<user>/.htpasswds/... based on the requested docroot

=head3 ARGUMENTS

=over

=item DOCROOT - string

User owned directory to secure with a password.

=back

=head3 RETURNS

string - Path where the passwd file will be placed or read from. Does not include the filename.

=head3 SIDE EFFECTS

Any missing directories along the returned path will be created under the users home folder.

=cut

sub get_path {
    my ($docroot) = @_;
    return _ensure_passwd_file_location($docroot);
}

=head2 open(DOCROOT, MODE)

Safely open the file for the given mode.

=head3 ARGUMENTS

=over

=item DOCROOT - string

User owned path to the directory being secured.

=item MODE - one of the values in the MODES hash above. Defaults to the READONLY class.

For readonly file access:

  my $transaction = Cpanel::HttpUtils::Htpasswd::open(
    '/home/tommy/public_html',
    $Cpanel::HttpUtils::Htpasswd::MODES{READONLY}
  );

  ...

For read/write file access:

  my $transaction = Cpanel::HttpUtils::Htpasswd::open(
    '/home/tommy/public_html',
    $Cpanel::HttpUtils::Htpasswd::MODES{READWRITE}
  );

...

=back

=head3 RETURNS

One of the following types depending on the mode requested:

=over

=item Cpanel::Transaction::File::RawReader

When requesting readonly file access

=item Cpanel::Transaction::File::Raw

When requesting readwrite file access.

=back

=head3 THROWS

=over

=item When the file can not be opened in the mode.

=item When the file does not have the correct permissions for the mode.

=back

=cut

sub open {
    my ( $docroot, $mode ) = @_;
    $mode = $MODES{READONLY} if !$mode;
    my $path = get_path($docroot);
    _validate_ownership($path) if $mode eq $MODES{READWRITE};

    my $module   = $mode;
    my $htpasswd = "${path}passwd";

    my $transaction = "$module"->new( path => $htpasswd, permissions => $HTPASSWD_PERMS, 'restore_original_permissions' => 1 );
    return $transaction;
}

=head2 _validate_user(USER) [PRIVATE]

Validate the user does not violate any rules for .htpasswd files

=head3 ARGUMENTS

=over

=item USER - string

User we want to validate against the rules for htpasswd file usage. See:
L<https://httpd.apache.org/docs/2.4/programs/htpasswd.html#restrictions>

=back

=cut

sub _validate_user {
    my $user = shift;
    if ( length $user > 255 ) {
        die Cpanel::Exception::create( 'InvalidParameter', 'The “[_1]” argument cannot be longer than [quant,_2,character,characters].', [ 'user', 255 ] );
    }
    if ( $user =~ m{[:<>\s]} ) {
        die Cpanel::Exception::create(
            'InvalidParameter',
            'The “[_1]” argument cannot include: [list_or_quoted,_2]',
            [
                'user',
                [ ':', '<', '>', ' ' ]
            ]
        );
    }
    return 1;
}

=head2 _validate_password(PASSWORD) [PRIVATE]

Validate the PASSWORD does not violate any rules for .htpasswd files

=head3 ARGUMENTS

=over

=item PASSWORD - string

The password to check the strength of.

=back

=cut

sub _validate_password_strength {
    my $password = shift;

    require Cpanel::PasswdStrength::Check;
    Cpanel::PasswdStrength::Check::verify_or_die( app => 'virtual', pw => $password );
    return 1;
}

=head2 _validate_password_strength(PASSWORD)

Validate that the password is strong enough.

=head3 ARGUMENTS

=over

=item PASSWORD - string

Password we want to validate against the rules for htpasswd file usage. See:
L<https://httpd.apache.org/docs/2.4/programs/htpasswd.html#restrictions>

=back

=cut

sub _validate_password {
    my $password = shift;
    if ( length $password > 255 ) {
        die Cpanel::Exception::create( 'InvalidParameter', 'The “[_1]” argument cannot be longer than [quant,_2,character,characters].', [ 'password', 255 ] );
    }
    return 1;
}

=head2 _validate_directory(DIR)

Checks if the passed in directory is valid.

=head3 ARGUMENTS

=over

=item DIR - string

A directory path to target.

=back

=cut

sub _validate_directory {
    my $directory = shift;
    if ( !-e $directory ) {
        die Cpanel::Exception::create( 'DirectoryDoesNotExist', [ dir => $directory ] );
    }

    if ( !-d _ ) {
        die Cpanel::Exception::create( 'InvalidParameter', '“[_1]” is not a directory.', [$directory] );
    }

    require Cpanel::Validate::Homedir;
    Cpanel::Validate::Homedir::path_is_in_homedir_or_die($directory);

    return 1;
}

1;
