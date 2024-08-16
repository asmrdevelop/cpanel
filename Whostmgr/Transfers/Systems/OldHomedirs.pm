package Whostmgr::Transfers::Systems::OldHomedirs;

# cpanel - Whostmgr/Transfers/Systems/OldHomedirs.pm
#                                                  Copyright 2022 cPanel, L.L.C.
#                                                           All rights reserved.
# copyright@cpanel.net                                         http://cpanel.net
# This code is subject to the cPanel license. Unauthorized copying is prohibited

use strict;

# RR Audit: JNK

use Cwd                         ();
use Cpanel::Path::Normalize     ();
use Cpanel::Locale              ();
use Cpanel::SafeDir::MK         ();
use Cpanel::Config::CpUserGuard ();

our $MAX_HOMEDIR_STREAM_ATTEMPTS = 5;

use base qw(
  Whostmgr::Transfers::SystemsBase::LinkDirBase
);

sub get_phase {
    return 15;
}

sub get_summary {
    my ($self) = @_;
    return [ $self->_locale()->maketext('This creates symbolic links to former home directory paths.') ];
}

sub get_restricted_available {
    return 0;
}

sub get_notes {
    my ($self) = @_;
    return [ $self->_locale()->maketext('Symbolic links for former home directories ensure that applications with hard-coded paths continue to work when transferred between servers.') ];
}

#NOTE: We do NOT run this module during restricted mode.

sub restricted_restore {
    my ($self) = @_;

    my $oldhomedirs_ref = $self->_get_old_homedirs_from_archive();
    if (@$oldhomedirs_ref) {
        return ( $Whostmgr::Transfers::Systems::UNSUPPORTED_ACTION, $self->_locale()->maketext( 'Restricted restorations do not allow running the “[_1]” module.', 'OldHomedirs' ) );
    }

    return 1;
}

sub unrestricted_restore {
    my ($self) = @_;

    my $newuser = $self->{'_utils'}->local_username();
    my $homedir = $self->{'_utils'}->homedir();

    return ( 0, $self->_locale()->maketext( 'The system failed to find the home directory for the user “[_1]”.', $newuser ) ) if !length $homedir;

    my $abshomedir      = Cwd::abs_path($homedir);
    my $oldhomedirs_ref = $self->_get_old_homedirs_from_archive();
    my ( $uid, $gid, $user_homedir ) = ( $self->{'_utils'}->pwnam() )[ 2, 3, 7 ];

    return 1 if !@$oldhomedirs_ref;

    my @valid_old_homedirs;
    foreach my $unprocessed_oldhomedir (@$oldhomedirs_ref) {
        my $oldhomedir = Cpanel::Path::Normalize::normalize($unprocessed_oldhomedir);    # This will collapse any duplicate //s and remove the trailing slash if needed
        next if !$oldhomedir || $oldhomedir eq $abshomedir;

        $self->out( $self->_locale()->maketext( 'The system will restore the old home directory link “[_1]” …', $oldhomedir ) );

        if ( !$self->is_valid_path_for_old_dir_symlink_for_uid( $oldhomedir, $uid ) ) {
            $self->{'_utils'}->add_skipped_item( $self->_locale()->maketext( '“[_1]” is not a valid path for a home directory symbolic link in this restore type.', $oldhomedir ) );
            next;
        }

        my ( $linkfile, $oldhome_parent_dir ) = File::Basename::fileparse($oldhomedir);
        $oldhome_parent_dir =~ s{\/$}{};

        next if !$linkfile || !$oldhome_parent_dir;

        if ( -l $oldhomedir ) {
            my $link_target = readlink($oldhomedir) or $self->warn( $self->_locale()->maketext( 'The system failed to read the symbolic link “[_1]” because of an error: [_2]', $oldhomedir, $! ) );
            if ( $link_target eq $abshomedir ) {

                # already exists
                push @valid_old_homedirs, $oldhomedir;
            }
            else {
                $self->{'_utils'}->add_skipped_item( $self->_locale()->maketext( 'The system could not link “[_1]” to the user’s home directory because it already links to “[_2]”.', $oldhomedir, $link_target ) );
            }
        }
        else {
            if ( !-e $oldhome_parent_dir ) {
                Cpanel::SafeDir::MK::safemkdir( $oldhome_parent_dir, '0755' ) or do {
                    $self->warn( $self->_locale()->maketext( 'The system failed to initialize the directory “[_1]” with permissions “[_2]” because of an error: [_3]', $oldhome_parent_dir, '0755', $! ) );
                    next;
                };
            }

            # If the directory that the old homedir link is about to be created in
            # exists but is not a directory we cannot create a symlink as a subdir
            # of a file or other non-directory
            if ( !-d $oldhome_parent_dir ) {
                $self->warn( $self->_locale()->maketext( 'The system failed to initialize the directory “[_1]” with permissions “[_2]” because it already exists and is not a directory.', $oldhome_parent_dir, '0755' ) );
                next;
            }
            elsif ( symlink( $abshomedir, $oldhomedir ) ) {
                push @valid_old_homedirs, $oldhomedir;
            }
            else {    # May already exist
                $self->warn( $self->_locale()->maketext( 'The system failed to create a symbolic link “[_1]” to “[_2]” because of an error: [_3]', $oldhomedir, $abshomedir, $! ) );
            }
        }

        $self->out( $self->_locale()->maketext('Done.') );
    }

    my $cpuser_guard = Cpanel::Config::CpUserGuard->new($newuser) or do {
        return ( 0, $self->_locale()->maketext( 'The system failed to read the user file for “[_1]” because of an error: [_2]', $newuser, $! ) );
    };

    $cpuser_guard->{'data'}{'HOMEDIRLINKS'} = \@valid_old_homedirs;

    $cpuser_guard->save() or do {
        return ( 0, $self->_locale()->maketext( 'The system failed to save the user file for “[_1]” because of an error: [_2]', $newuser, $! ) );
    };

    return 1;
}

sub _get_old_homedirs_from_archive {
    my ($self) = @_;

    my $extractdir = $self->{'_archive_manager'}->trusted_archive_contents_dir();
    my $homedir    = $self->{'_utils'}->homedir();
    my $abshomedir = Cwd::abs_path($homedir);

    my ( $old_ok, $oldhomedirs_ref ) = $self->{'_archive_manager'}->get_old_homedirs();
    return ( 0, $oldhomedirs_ref ) if !$old_ok;

    $self->start_action("Linking old home directories");

    my ($cpuser_ref) = $self->{'_utils'}->get_cpuser_data();
    if ( $cpuser_ref && $cpuser_ref->{'HOMEDIRLINKS'} ) {
        push @$oldhomedirs_ref, @{ $cpuser_ref->{'HOMEDIRLINKS'} };
    }

    return [ grep { $_ ne $abshomedir && $_ ne $homedir } @$oldhomedirs_ref ];

}

1;
