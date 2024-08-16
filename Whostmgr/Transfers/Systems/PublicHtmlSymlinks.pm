package Whostmgr::Transfers::Systems::PublicHtmlSymlinks;

# cpanel - Whostmgr/Transfers/Systems/PublicHtmlSymlinks.pm
#                                                  Copyright 2022 cPanel, L.L.C.
#                                                           All rights reserved.
# copyright@cpanel.net                                         http://cpanel.net
# This code is subject to the cPanel license. Unauthorized copying is prohibited

use strict;

# RR Audit: JNK

use Cpanel::AccessIds::ReducedPrivileges ();
use Cpanel::LoadFile                     ();
use Cpanel::Locale                       ();
use Cpanel::PwCache                      ();
use Cpanel::UserFiles                    ();
use Cpanel::SafeDir::MK                  ();

use base qw(
  Whostmgr::Transfers::SystemsBase::LinkDirBase
);

# Use 'meta/html_paths', if necessary, for backwards compatibility.  Otherwise,
# the default location of userconfig/public_html_symlinks will be assumed.
#
# This special case is necessary to handle any cpmove archives which place the
# public_html directory symlinks in the legacy location, meta/html_paths, which
# is the current behavior for pkgacct-enXim-v3.0.3-g92165d.
#
my @PATHS_TO_CHECK_FOR_SYMLINKS = qw(
  userconfig/public_html_symlinks
  meta/html_paths
);

sub get_summary {
    my ($self) = @_;
    return [ $self->_locale()->maketext('This creates symbolic links to former web root directory paths.') ];
}

sub get_restricted_available {
    return 1;
}

sub get_restricted_summary {
    my ($self) = @_;
    return [ $self->_locale()->maketext('The system does not recreate symbolic links outside of the account’s home directory in restricted mode.') ];
}

sub get_notes {
    my ($self) = @_;
    return [ $self->_locale()->maketext('Symbolic links for former web root directories ensure that applications with hard-coded paths will continue to work when transferred between servers.') ];
}

*restricted_restore = \&unrestricted_restore;

sub unrestricted_restore {
    my ($self) = @_;

    my $newuser = $self->{'_utils'}->local_username();

    my $extractdir = $self->{'_archive_manager'}->trusted_archive_contents_dir();

    my ( $uid, $gid, $user_homedir ) = ( $self->{'_utils'}->pwnam() )[ 2, 3, 7 ];

    my $abshomedir  = Cpanel::PwCache::gethomedir($newuser);
    my $public_html = "$abshomedir/public_html";

    my $public_html_symlinks = ( grep { -f "$extractdir/$_" } @PATHS_TO_CHECK_FOR_SYMLINKS )[0];

    return 1 if !$public_html_symlinks;    #Nothing to do!

    $public_html_symlinks = "$extractdir/$public_html_symlinks";

    $self->start_action('Linking old document roots');

    my $oldhtmldirs_r = Cpanel::LoadFile::loadfile_r($public_html_symlinks) or do {
        return ( 0, $self->_locale()->maketext( 'The system failed to load the file “[_1]” because of an error: [_2]', $public_html_symlinks, $! ) );
    };

    my @oldhtmldirs = split m{\n}, $$oldhtmldirs_r;

    my $userconfig_path = Cpanel::UserFiles::userconfig_path($newuser);

    Cpanel::SafeDir::MK::safemkdir( $userconfig_path, '0750' ) or do {
        return ( 0, $self->_locale()->maketext( 'The system failed to create the directory “[_1]” because of an error: [_2]', $userconfig_path, $! ) );
    };

    my $new_symlinks_file = Cpanel::UserFiles::public_html_symlinks_file($newuser);
    open( my $fh, '>', $new_symlinks_file ) or do {
        return ( 0, $self->_locale()->maketext( 'The system failed to open the file “[_1]” for writing because of an error: [_2]', $new_symlinks_file, $! ) );
    };

    foreach my $oldhtmldir (@oldhtmldirs) {
        $oldhtmldir =~ s!/+!/!g;
        ## note: this split handles trailing slash correctly, which surprised me
        my @htmlpath = split( /\//, $oldhtmldir );

        next if ( $#htmlpath <= 0 );

        my $linkfile = pop @htmlpath;
        my $linkdir  = join( '/', @htmlpath );

        next if ( !$linkfile || !$linkdir );

        my $linkpath = "$linkdir/$linkfile";
        if ( !$self->is_valid_path_for_old_dir_symlink_for_uid( $linkpath, $uid ) ) {
            $self->{'_utils'}->add_skipped_item( $self->_locale()->maketext( '“[_1]” is not a valid path for a html directory symbolic link in this restore type.', $linkpath ) );
            next;
        }

        my $symlink_coderef = sub {
            #
            # Prevent clobbering of any existing convenience symlinks if one already
            # physically exists on this system.
            #
            if ( !lstat($linkpath) ) {
                symlink( $public_html, $linkpath ) or do {
                    $self->warn( $self->_locale()->maketext( 'The system failed to create create a symbolic link “[_1]” to “[_2]” because of an error: [_3]', $linkpath, $public_html, $! ) );
                };

                print {$fh} "$linkpath\n" or do {
                    $self->warn( $self->_locale()->maketext( 'The system failed to write to the file “[_1]” because of an error: [_2]', $new_symlinks_file, $! ) );
                };
            }
        };

        #If the symlink is to be created within the home directory,
        #then we need to create it as the user.
        if ( $linkdir =~ m{\A\Q$abshomedir\E(?:/|\z)} ) {
            Cpanel::AccessIds::ReducedPrivileges::call_as_user(
                $newuser,
                sub {
                    # Create parent dir as the user
                    if ( !-e $linkdir ) {
                        Cpanel::SafeDir::MK::safemkdir( $linkdir, '0755' ) or do {
                            $self->warn( $self->_locale()->maketext( 'The system failed to create the directory “[_1]” because of an error: [_2]', $linkdir, $! ) );
                            return;
                        };
                    }
                    return $symlink_coderef->();
                }
            );
        }
        elsif ( !$self->{'_utils'}->is_unrestricted_restore() ) {
            $self->{'_utils'}->add_skipped_item( $self->_locale()->maketext( 'The system cannot create the directory “[_1]” in restricted mode.', $linkdir ) );
            next;
        }
        else {
            # Create parent dir as root
            Cpanel::SafeDir::MK::safemkdir( $linkdir, '0755' ) or do {
                $self->warn( $self->_locale()->maketext( 'The system failed to create the directory “[_1]” because of an error: [_2]', $linkdir, $! ) );
                next;
            };
            $symlink_coderef->();
        }
    }

    close($fh) or do {
        return ( 0, $self->_locale()->maketext( 'The system failed to close the file “[_1]” because of an error: [_2]', $new_symlinks_file, $! ) );
    };

    return 1;
}

1;
