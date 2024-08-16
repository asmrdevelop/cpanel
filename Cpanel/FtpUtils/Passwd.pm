
# cpanel - Cpanel/FtpUtils/Passwd.pm               Copyright 2022 cPanel, L.L.C.
#                                                           All rights reserved.
# copyright@cpanel.net                                         http://cpanel.net
# This code is subject to the cPanel license. Unauthorized copying is prohibited

package Cpanel::FtpUtils::Passwd;

use strict;
use warnings;

use Cpanel::ConfigFiles       ();
use Cpanel::SafeFile          ();
use Cpanel::StringFunc::Match ();

use Try::Tiny;

=head1 NAME

Cpanel::FtpUtils::Passwd

=head1 DESCRIPTION

Utility functions for interacting with FTP password storage files.

=head1 FUNCTIONS

=head2 line_matches_user

Given a single line from an FTP passwd file, this function determine
whether the line represents the user we are looking for. It handles
the compatibility with the old-style FTP passwd files before the
user field had a domain in it.

This function may also be used for lookups from FTP quota files, as
they follow the same format for the username field, and the remaining
fields are ignored.

=head3 Arguments

  - %args - Hash - Named parameters
      - line - String - The line being examined
      - user - String - The username without the domain
      - domain - String - The domain of the user
      - maindomain - String - The main domain of the cPanel account that owns this user.
                              This is used to determine whether an entry lacking a domain
                              could be a match or not.

=head3 Returns

This function returns a boolean value indicating whether there was a match.

=head3 Throws

This function does not throw exceptions.

=cut

sub line_matches_user {
    my %args = @_;
    my ( $line, $user, $domain, $maindomain ) = @args{qw(line user domain maindomain)};

    # match the full name, for any domain
    my $fullname_match = Cpanel::StringFunc::Match::ibeginmatch( $line, "${user}\@${domain}:" );

    # or match both of these
    my $partname_match = Cpanel::StringFunc::Match::ibeginmatch( $line, "${user}:" );
    my $domain_match   = $domain eq $maindomain;

    return 1 if ( $fullname_match || ( $partname_match && $domain_match ) );
    return 0;
}

=head2 edit_passwd_file

Edit a password file

=head3 Arguments

  - $file - The file to edit
  - $edit_cr - A CODE ref pointing to the function you want to apply
               to each line of the file. This function must behave as
               follows:
                   1. Accept a single array ref representing the colon-delimited
                      fields of a line.
                   2. Modify the array values in-place if edits are needed.
                   3. Return true if edits were made, false otherwise.

=head3 Returns

No return value.

=head3 Throws

This function does not emit exceptions directly, but it relies on Cpanel::Transaction::File::Raw
for the file reading and writing functionality. Cpanel::Transaction::File::Raw throws exceptions
of various types for all failure conditions.

=cut

sub edit_passwd_file {
    my ( $file, $edit_cr ) = @_;

    require Cpanel::Transaction::File::Raw;

    my $txn      = Cpanel::Transaction::File::Raw->new( path => $file, restore_original_permissions => 1 );
    my @contents = split /\n/, $txn->get_data->$*;

    my $any_changes = 0;
    for (@contents) {
        chomp;
        my @fields = split /:/;
        if ( $edit_cr->( \@fields ) ) {
            $any_changes = 1;
            $_           = join( ':', @fields );
        }
        $_ .= "\n";
    }

    if ($any_changes) {
        $txn->set_data( \join( '', @contents ) );
        $txn->save_or_die;
    }
    else {
        $txn->close_or_die;
    }

    return;
}

=head2 touch_userpw_file_if_exists

Set the FTP storage file mtime a user to the current second.



=head3 Arguments

  - $user - The cPanel account to update.

=head3 Returns

This function returns 1 regardless of outcome.

=head3 Throws

This function throws no exceptions.

=cut

sub touch_userpw_file_if_exists {
    my $cpanel_user = shift;

    my $pwfile = "$Cpanel::ConfigFiles::FTP_PASSWD_DIR/$cpanel_user";
    if ( -e $pwfile ) {
        require Cpanel::FileUtils::TouchFile;
        Cpanel::FileUtils::TouchFile::touchfile($pwfile);
    }

    return 1;
}

=head2 create

Creates the FTP storage file for a cPanel account if it does not already exist.

It also created the outer storage directory if needed.
Errors during the creation process are logged using Perl's warn(), or returned.

=head3 Arguments

  - $user           - The cPanel account.
  - %options        - Optional settings to control the behavior during storage creation.
    - unsuspend     - Boolean value that indicates whether or not the storage should be
                      unsuspended during creation if it is in a suspended state (default false.)
    - content       - A string of FTP Password file content to insert into the storage file.
                      If provided, this string will replace any existing content in the file.
                      If not provided, any existing content in the file will be preserved.
                      (default undef)
    - return_errors - Boolean value to specify that trapped exceptions should be returned
                      rather than logged with warn().

=head3 Returns

This function returns a status value of 1 if the FTP storage exists after the operation and 0
if the operation failed.

When the "return_errors" option is true, any trapped exception will be returned after the
status code. IE: (0, $exception)

=head3 Throws

This function throws no exceptions.

=cut

sub create {
    my ( $user, %options ) = @_;

    my $file;
    my $locks_ar;
    my $storage_created = 0;
    my $errors;

    try {
        _create_ftp_dir_if_missing();

        # Lock out competing changes to this user's storage and determine which filename it's using.
        ( $file, $locks_ar ) = lock_storage_ex($user);

        if ( $options{unsuspend} && is_suspended_file($file) ) {

            # account is currently in a suspended state and this caller wants an unsuspended state.
            my $suspended = $file;
            $file = _ftp_user_file($user);
            rename( $suspended, $file ) or die "Could not unsuspended FTP storage for $user: $!";
        }

        if ( defined $options{content} || !-e $file ) {

            # File needs to be created or overwritten
            require Cpanel::FileUtils::Write;
            my $ftp_group = _ftp_storage_group();
            local $) = "$ftp_group $ftp_group";
            Cpanel::FileUtils::Write::overwrite( $file, ( $options{content} // "" ), 0640 );
        }

        $storage_created = 1;
    }
    catch {
        if ( $options{return_errors} ) {
            $errors = $_;
        }
        else {
            warn "Error creating FTP storage for $user. $_";
        }
    }
    finally {
        unlock_storage($locks_ar);
    };

    return ( $storage_created, $errors );
}

=head2 remove

Removes the FTP storage file for a cPanel account if it exists.

If an IP address for the account is also specified, IP to docroot mapping symlinks
for the account are also removed.

Errors during the removal process are logged using Perl's warn().

=head3 Arguments

  - $user       - The cPanel account.
  - $ip_address - An optional IP address to check for symlinks to the account.

=head3 Returns

This function returns a status value of 1 if removal operation succeeded without errors
and 0 if any errors were encountered.

=head3 Throws

This function throws no exceptions.

=cut

sub remove {
    my ( $user, $ip ) = @_;

    my $files_ar;
    my $locks_ar;
    my $storage_removed = 0;
    try {
        # Delete actual user storage
        ( $files_ar, $locks_ar ) = lock_storage_ex( $user, all => 1 );
        my @errors;
        foreach my $file (@$files_ar) {
            unlink($file) or push @errors, "Failed to unlink $file: $!";
        }
        die \@errors if @errors;

        # Remove dedicated IP symlink if needed.
        if ( defined $ip ) {
            my $ip_file = $Cpanel::ConfigFiles::FTP_SYMLINKS_DIR . '/' . $ip;
            if ( -l $ip_file && readlink($ip_file) =~ m{/\Q$user\E/public_ftp\z} ) {
                require Cpanel::IP::Loopback;
                if ( !Cpanel::IP::Loopback::is_loopback($ip) ) {
                    unlink $ip_file or die "Failed to remove dedicated IP symlink $ip_file: $!";
                }
            }
        }

        $storage_removed = 1;
    }
    catch {
        foreach my $error ( ref $_ eq 'ARRAY' ? @{$_} : ($_) ) {
            warn "Error removing FTP storage for $user. $error";
        }
    }
    finally {
        unlock_storage($locks_ar);
    };
    return $storage_removed;
}

=head2 lock_storage

Locks the FTP storage for a cPanel account and identifies which of the two possible
storage filenames should be used.

Errors during the locking process are logged using Perl's warn().

=head3 Arguments

  - $user    - The cPanel account.
  - %options - Optional settings to control the locking behavior.
    - all    - Boolean value. When set, an arrayref will be returned in place of
               the filename as described below.

=head3 Returns

When the "all" option is not set, the correct storage filename will be returned followed by
an arrayref with the locks that were created.

When the "all" option is set, two arrayrefs will be returned. The first arrayref will
contain the paths to all existing storage locations (the canonical "suspended" path is first
if both locations exist), followed by an arrayref with the locks that were created.

=head3 Throws

This function throws no exceptions.

=cut

sub lock_storage {
    my @args = @_;
    my @result;
    try {
        @result = lock_storage_ex(@args);
    }
    catch {
        warn "Error while locking FTP storage for user $_";
    };
    return @result;
}

=head2 lock_storage_ex

This function is identical to lock_storage() except that errors are thrown
as exceptions after unwinding the locks.

Errors that arise during the unwinding process will be logged.

=cut

sub lock_storage_ex {
    my ( $user, %options ) = @_;
    my $file      = _ftp_user_file($user);
    my $suspended = _ftp_user_suspended_file($user);
    my @locks;
    my @storage;

    # safelock() exceptions are trapped unwind from partial locking.
    try {
        push @locks, ( Cpanel::SafeFile::safelock($file)      || die "Could not lock $file" );
        push @locks, ( Cpanel::SafeFile::safelock($suspended) || die "Could not lock $suspended" );
    }
    catch {
        my $err = $_;
        unlock_storage( \@locks );
        die $err;
    };

    if ( $options{all} ) {
        push @storage, $suspended if ( -e $suspended );
        push @storage, $file      if ( -e $file );
        return ( \@storage, \@locks );
    }
    return ( ( -e $suspended ? $suspended : $file ), \@locks );
}

=head2 unlock_storage

Unlocks the FTP storage locks created by the lock_storage() function.

Errors during the unlocking process are logged using Perl's warn().

=head3 Arguments

  - @locks - The locks produced by a previous lock_storage() or lock_storage_ex()
             call. The locks can be provided as a list or arrayref.

=head3 Returns

No return value.

=head3 Throws

This function throws no exceptions.

=cut

sub unlock_storage {
    my @locks = @_;
    try {
        unlock_storage_ex(@locks);
    }
    catch {
        warn "Error during FTP storage unlocking for user $_";
    };
    return;
}

=head2 unlock_storage_ex

This function is identical to unlock_storage() except that errors are thrown
as exceptions.

=cut

sub unlock_storage_ex {
    my @locks = ref $_[0] eq 'ARRAY' ? @{ $_[0] } : @_;
    Cpanel::SafeFile::safeunlock($_) foreach reverse @locks;
    return;
}

=head2 open_storage_for_reading

Locks and opens the FTP storage file for a cPanel user.

Errors are logged using Perl's warn().

=head3 Arguments

  - $user    - The cPanel account.

=head3 Returns

If the file exists and can be opened, a list is returned containing:
  - the full file path opened
  - the filehandle
  - 1 if the storage is suspended, 0 otherwise
  - an arrayref with locks for the storage

If the file can not be opened or errors are encountered, the return
is empty.

=head3 Throws

This function throws no exceptions.

=cut

sub open_storage_for_reading {
    my ($user) = @_;
    my ( $file, $locks_ar ) = lock_storage($user);
    return unless ( defined $file );
    if ( open my $fh, '<', $file ) {
        return ( $file, $fh, is_suspended_file($file), $locks_ar );
    }
    else {
        my $errno_val = $!;
        require Errno;
        warn "Unable to open $file for reading: $errno_val" unless ( $errno_val == Errno::ENOENT() );
    }
    unlock_storage($locks_ar);
    return;
}

=head2 unlock_storage_ex

This function determines if a filename represents a suspended state or
unsuspended state.

=head3 Arguments

  - $file - The filename to check.

=head3 Returns

1 if the filename is for a suspended account.
0 if the filename is for an unsuspended account.

=head3 Throws

This function throws no exceptions.

=cut

sub is_suspended_file {
    return ( substr( $_[0], -10 ) eq '.suspended' ? 1 : 0 );
}

sub _ftp_user_file {
    return $Cpanel::ConfigFiles::FTP_PASSWD_DIR . '/' . $_[0];
}

sub _ftp_user_suspended_file {
    return $Cpanel::ConfigFiles::FTP_PASSWD_DIR . '/' . $_[0] . '.suspended';
}

sub _ftp_storage_group {
    return ( getgrnam("proftpd") // getgrnam("ftp") // 0 );
}

sub _create_ftp_dir_if_missing {

    # Create main storage directory if missing
    if ( !-e $Cpanel::ConfigFiles::FTP_PASSWD_DIR ) {
        my $original_umask = umask(022);
        my $created        = mkdir( $Cpanel::ConfigFiles::FTP_PASSWD_DIR, 0751 );
        umask($original_umask);
        die "Could not create $Cpanel::ConfigFiles::FTP_PASSWD_DIR: $!" unless $created;
    }
    return;
}

1;
