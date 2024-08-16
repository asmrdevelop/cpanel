package Whostmgr::Transfers::ConvertAddon::MigrateData::FTPAccounts;

# cpanel - Whostmgr/Transfers/ConvertAddon/MigrateData/FTPAccounts.pm
#                                                  Copyright 2022 cPanel, L.L.C.
#                                                           All rights reserved.
# copyright@cpanel.net                                         http://cpanel.net
# This code is subject to the cPanel license. Unauthorized copying is prohibited

use strict;
use warnings;

use parent qw(Whostmgr::Transfers::ConvertAddon::MigrateData::PasswdAccounts);

=head1 NAME

Whostmgr::Transfers::ConvertAddon::MigrateData::FTPAccounts - Copy FTP Accounts from one account to another

=head1 SYNOPSIS

    use Whostmgr::Transfers::ConvertAddon::MigrateData::FTPAccounts;

    my $accounts_obj = Whostmgr::Transfers::ConvertAddon::MigrateData::FTPAccounts->new(
        {
            'from_username' => 'pinocchio',
            'to_username'   => 'boy',
        }
    );

    $accounts_obj->copy(
        {
            'domain'  => 'pinocchio.tld',
            'docroot' => '/home/pinocchio/public_html',
        }
    );

    $accounts_obj->copy_quotas('pinocchio.tld');

=head1 DESCRIPTION

This module provides the functionality to copy FTP accounts and the quotas for those accounts from an addon domain
to a cPanel account.

Inherits from C<Whostmgr::Transfers::ConvertAddon::MigrateData::PasswdAccounts>

=cut

use Cpanel::ConfigFiles                      ();
use Cpanel::Exception                        ();
use Cpanel::PwCache                          ();
use Cpanel::SafeFile                         ();
use Cpanel::AccessIds::ReducedPrivileges     ();
use File::Spec                               ();
use Whostmgr::Transfers::ConvertAddon::Utils ();

=head1 OBJECT METHODS

=head2 _copy_users($domain, $docroot)

Copy the FTP accounts from one account to another.

=over 3

=item C<$domain> [in, required]

The domain used to determine which FTP accounts to be copied to the new account.

=item C<$docroot> [in, required]

The document root of the source account.

=back

B<Returns>: On failure, throws an exception. On success, returns C<1>.

=cut

sub _copy_users {
    my ( $self, $domain, $docroot ) = @_;

    my $source = File::Spec->catfile( $Cpanel::ConfigFiles::FTP_PASSWD_DIR, $self->{'from_username'} );
    my $dest   = File::Spec->catfile( $Cpanel::ConfigFiles::FTP_PASSWD_DIR, $self->{'to_username'} );

    # safely open up the source account's ftp password file
    my $source_lock = Cpanel::SafeFile::safeopen( my $source_fh, '<', $source );
    unless ($source_lock) {
        die Cpanel::Exception::create( 'IO::FileOpenError', [ path => $source, error => $!, mode => '<' ] );
    }

    # safely open up the target account's ftp password file
    my $dest_lock = Cpanel::SafeFile::safeopen( my $dest_fh, '>>', $dest );
    unless ($dest_lock) {

        # release the lock on the source file if we get here
        Cpanel::SafeFile::safeclose( $source_fh, $source_lock );
        die Cpanel::Exception::create( 'IO::FileOpenError', [ path => $dest, error => $!, mode => '>>' ] );
    }

    my $new_docroot = File::Spec->catdir( Cpanel::PwCache::gethomedir( $self->{'to_username'} ), 'public_html' );

    # copy the users that belong to the target account
    my ( $skipped_accts, $missing_homedir, $conflict_accts ) = $self->_copy_valid_users( $domain, $docroot => $new_docroot, $source_fh => $dest_fh );

    Cpanel::SafeFile::safeclose( $source_fh, $source_lock );
    Cpanel::SafeFile::safeclose( $dest_fh,   $dest_lock );

    foreach my $user (@$skipped_accts) {
        $self->add_warning( 'Skipped copying the following FTP account since it is outside the addon docroot: ' . $user );
    }
    foreach my $user (@$conflict_accts) {
        $self->add_warning( 'Skipped copying the following FTP account since it conflicts with cPanel-generated accounts: ' . $user );
    }
    foreach (@$missing_homedir) {
        $self->add_warning("The home directory of the FTP account “$_->{user}” does not exist: $_->{directory}");
    }

    return 1;
}

=head2 copy_quotas($domain)

Copy the quotas for FTP accounts.

=over 3

=item C<$domain> [in, required]

The domain used to determine which FTP accounts have their quota copied to the new account.

=back

B<Returns>: On failure, throws an exception. On success, returns C<1>.

=cut

sub copy_quotas {
    my ( $self, $domain ) = @_;

    die Cpanel::Exception::create( 'MissingParameter', 'The parameter “[_1]” is required.', ['domain'] ) if !$domain;

    my $from_user_home = Whostmgr::Transfers::ConvertAddon::Utils::gethomedir_or_die( $self->{'from_username'} );
    my $from_ftp_quota = File::Spec->catfile( $from_user_home, 'etc', 'ftpquota' );

    return 1 if ( !-s $from_ftp_quota );    # there is no quota file, so just exit

    my ( $source_lock,   $from_ftp_quota_fh );
    my ( $from_user_uid, $from_user_gid ) = ( Cpanel::PwCache::getpwnam( $self->{'from_username'} ) )[ 2, 3 ];
    Cpanel::AccessIds::ReducedPrivileges::call_as_user(
        sub {
            $source_lock = Cpanel::SafeFile::safeopen( $from_ftp_quota_fh, '<', $from_ftp_quota );
            die Cpanel::Exception::create( 'IO::FileOpenError', [ path => $from_ftp_quota, error => $!, mode => '<' ] ) if !$source_lock;
        },
        $from_user_uid,
        $from_user_gid,
    );

    my $to_user_home = Whostmgr::Transfers::ConvertAddon::Utils::gethomedir_or_die( $self->{'to_username'} );
    my $to_ftp_quota = File::Spec->catfile( $to_user_home, 'etc', 'ftpquota' );

    my ( $dest_lock,   $to_ftp_quota_fh );
    my ( $to_user_uid, $to_user_gid ) = ( Cpanel::PwCache::getpwnam( $self->{'to_username'} ) )[ 2, 3 ];
    Cpanel::AccessIds::ReducedPrivileges::call_as_user(
        sub {
            $dest_lock = Cpanel::SafeFile::safeopen( $to_ftp_quota_fh, '>', $to_ftp_quota );
            die Cpanel::Exception::create( 'IO::FileOpenError', [ path => $to_ftp_quota, error => $!, mode => '>' ] ) if !$dest_lock;
        },
        $to_user_uid,
        $to_user_gid,
    );

    while ( my $line = readline $from_ftp_quota_fh ) {
        if ( $line =~ m/\@\Q$domain\E:/ ) {
            print {$to_ftp_quota_fh} $line;
        }
    }

    Cpanel::SafeFile::safeclose( $from_ftp_quota_fh, $source_lock );
    Cpanel::SafeFile::safeclose( $to_ftp_quota_fh,   $dest_lock );

    return 1;
}

1;
