package Whostmgr::Transfers::ConvertAddon::MigrateData::WebDiskAccounts;

# cpanel - Whostmgr/Transfers/ConvertAddon/MigrateData/WebDiskAccounts.pm
#                                                  Copyright 2022 cPanel, L.L.C.
#                                                           All rights reserved.
# copyright@cpanel.net                                         http://cpanel.net
# This code is subject to the cPanel license. Unauthorized copying is prohibited

#
use strict;
use warnings;

use parent qw(Whostmgr::Transfers::ConvertAddon::MigrateData::PasswdAccounts);

use Cpanel::AccessIds::ReducedPrivileges ();
use Cpanel::Exception                    ();
use Cpanel::PwCache                      ();
use Cpanel::SafeDir::MK                  ();
use Cpanel::SafeFile                     ();
use File::Spec                           ();

sub _copy_users {
    my ( $self, $domain, $docroot ) = @_;

    # If there is no etc/webdav/passwd file in the source account, we have
    # nothing to do.
    return 1 if !-f File::Spec->catfile( Cpanel::PwCache::gethomedir( $self->{from_username} ), 'etc', 'webdav', 'passwd' );

    my ( $passwd_src, $shadow_src ) = _open_filehandles( $self->{from_username}, '<' );
    my ( $passwd_dst, $shadow_dst ) = _open_filehandles( $self->{to_username},   '>>' );

    my $new_docroot = File::Spec->catdir( Cpanel::PwCache::gethomedir( $self->{'to_username'} ), 'public_html' );

    my ( $skipped_accts, $missing_homedir ) = $self->_copy_valid_users(
        $domain,
        $docroot        => $new_docroot,
        $passwd_src->fh => $passwd_dst->fh,
        $shadow_src->fh => $shadow_dst->fh,
    );

    foreach my $user (@$skipped_accts) {
        $self->add_warning( 'Skipped copying the following Web Disk account since it is outside the addon docroot: ' . $user );
    }
    foreach (@$missing_homedir) {
        $self->add_warning("The home directory of the Web Disk account “$_->{user}” does not exist: $_->{directory}");
    }

    return 1;
}

sub _open_filehandles {
    my ( $user, $mode ) = @_;

    my $dir = File::Spec->catfile( Cpanel::PwCache::gethomedir($user), 'etc', 'webdav' );

    my $passwd = File::Spec->catfile( $dir, 'passwd' );
    my $shadow = File::Spec->catfile( $dir, 'shadow' );

    my ( $passwd_fh, $shadow_fh );
    my ( $uid,       $gid ) = ( Cpanel::PwCache::getpwnam($user) )[ 2, 3 ];
    Cpanel::AccessIds::ReducedPrivileges::call_as_user(
        sub {
            Cpanel::SafeDir::MK::safemkdir( $dir, '0700' );    # See Cpanel::WebDisk::_setupdirs
            $passwd_fh = Cpanel::SafeFile::AutoUnlock->new( $passwd, $mode );
            $shadow_fh = Cpanel::SafeFile::AutoUnlock->new( $shadow, $mode );
        },
        $uid,
        $gid,
    );

    return $passwd_fh, $shadow_fh;
}

{

    package Cpanel::SafeFile::AutoUnlock;

    sub new {
        my ( $class, $filename, $mode ) = @_;

        my $lock = Cpanel::SafeFile::safeopen( my $fh, $mode, $filename );
        die Cpanel::Exception::create( 'IO::FileOpenError', [ path => $filename, error => $!, mode => $mode ] ) if !$lock;

        my $self = {
            lock     => $lock,
            fh       => $fh,
            filename => $filename,
            mode     => $mode,
        };
        bless $self, $class;
        return $self;
    }

    sub fh { return $_[0]->{fh} }

    sub DESTROY {
        my ($self) = @_;
        Cpanel::SafeFile::safeclose( $self->{fh}, $self->{lock} );
        return;
    }
}

1;
