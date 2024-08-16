
# cpanel - Cpanel/Analytics.pm                     Copyright 2022 cPanel, L.L.C.
#                                                           All rights reserved.
# copyright@cpanel.net                                         http://cpanel.net
# This code is subject to the cPanel license. Unauthorized copying is prohibited

package Cpanel::Analytics;

use strict;
use warnings;

use Cpanel::Analytics::Config    ();
use Cpanel::Autodie              ();
use Cpanel::FileUtils::TouchFile ();
use Cpanel::LoadModule           ();
use Cpanel::Sys::Chattr          ();

use Try::Tiny;

=head1 NAME

C<Cpanel::Analytics>

=head1 DESCRIPTION

Setup prerequisites for cp-analytics

=head1 SYNOPSIS

    use Cpanel::Analytics ();
    Cpanel::Analytics::prerequisites();


=head1 FUNCTIONS

=head2 C<prerequisites()>

Helper method to create the needed file system resources for the analytics system.

=head3 EXCEPTIONS

Various file related exceptions

=cut

sub prerequisites {

    # 755 is needed for the main directory since the server information
    # file is created there and users need to be able to read the file
    # from the folder.
    _setup_dir( Cpanel::Analytics::Config::ANALYTICS_DIR(), 0755 );
    my ( undef, undef, undef, $analytics_gid ) = getpwnam( Cpanel::Analytics::Config::ANALYTICS_USER() );

    _setup_dir( Cpanel::Analytics::Config::FEATURE_TOGGLES_DIR(), 0755 );

    # 710 so the analytics user can "execute" (access files underneath) but not move or delete files.
    # This is important because one of the files is written to by root, so it would be unsafe to allow
    # an unprivileged user to replace it with a symlink.
    _setup_dir( Cpanel::Analytics::Config::ANALYTICS_DATA_DIR(), 0710, $analytics_gid );
    _setup_dir( Cpanel::Analytics::Config::ANALYTICS_LOGS_DIR(), 0710, $analytics_gid );
    _setup_dir( Cpanel::Analytics::Config::ANALYTICS_RUN_DIR(),  0771, $analytics_gid );

    # It's safer to make the operations log itself owned by cpanelanalytics rather than giving the user
    # complete rwx access to the directory. Reason: The error log still needs to be written by root in
    # some cases, so we don't want that file to be subject to symlink attacks. (Highly improbable, but
    # needed for the privilege separation to be complete.)
    my $operation_log = Cpanel::Analytics::Config::OPERATIONS_LOG();
    if ( !-e $operation_log ) {
        Cpanel::FileUtils::TouchFile::touchfile($operation_log);
        _chown( 0, $analytics_gid, $operation_log );
        _chmod( 0660, $operation_log );
    }

    # Same for the error log
    my $error_log = Cpanel::Analytics::Config::ERROR_LOG();
    if ( !-e $error_log ) {
        Cpanel::FileUtils::TouchFile::touchfile($error_log);
        _chown( 0, $analytics_gid, $error_log );
        _chmod( 0660, $error_log );
    }

    write_unique_system_id();

    return 1;
}

# Setup/heal a directory
sub _setup_dir {
    my ( $dir, $perm, $owner_gid ) = @_;
    if ( !_directory_exists($dir) ) {
        require Cpanel::SafeDir::MK;
        Cpanel::SafeDir::MK::safemkdir( $dir, $perm );
    }
    _chown( 0, $owner_gid, $dir ) if $owner_gid;
    _chmod( $perm, $dir );
    return;
}

# For testing
sub _chmod {
    return chmod @_;
}

# For testing
sub _chown {
    return chown @_;
}

# For testing
sub _file_exists {
    return -e $_[0];
}

# For testing
sub _directory_exists {
    return -d $_[0];
}

# For testing
sub _file_empty {
    return -z $_[0];
}

sub _make_immutable {
    my ($path) = @_;

    try {
        Cpanel::Autodie::open( my $fh, '<', $path );
        Cpanel::Sys::Chattr::set_attribute( $fh, 'IMMUTABLE' );
    }
    catch { warn $_ };

    return;
}

=head2 C<has_unique_system_id(PATH)>

Checks if the system id file is already in place.

=head3 ARGUMENTS

=over

=item PATH - String - Optional

If provided, defines the path where analytics server_id is stored. If not defined, will use the local constant for this path.

=back

=head3 RETURNS

Boolean - if true, the file was previously generated, if false it needs to be generated.

=cut

sub has_unique_system_id {
    my $path = shift || Cpanel::Analytics::Config::SYSTEM_ID_PATH();
    return ( _file_exists($path) && !_file_empty($path) ) ? 1 : 0;
}

=head2 C<write_unique_system_id(PATH)>

Writes the unique system id to the file /var/cpanel/analytics/system_id

=over

=item PATH - String - Optional

If provided, defines the path where analytics server_id is stored. If not defined, will use the local constant for this path.

=back

=cut

sub write_unique_system_id {
    my $path = shift || Cpanel::Analytics::Config::SYSTEM_ID_PATH();

    return if has_unique_system_id($path);    # We only write this once ever

    # Reaching this point should only ever occur once per server, so don't worry too much about module bloat.
    Cpanel::LoadModule::load_perl_module('Cpanel::Logger');
    Cpanel::LoadModule::load_perl_module('Cpanel::Rand::Get');
    Cpanel::LoadModule::load_perl_module('Cpanel::Umask');

    if ( _file_exists($path) ) {

        # The server_id was tampered with, so we need to make sure its not
        # been set to immutable again or we can not repair it.

        my $ok = open( my $fh, '<', $path );
        if ( !$ok ) {
            Cpanel::Logger->new()->warn("Could not create the file '$path' with error: $!");
            return;
        }

        Cpanel::Sys::Chattr::remove_attribute( $fh, 'IMMUTABLE' );

        $ok = close($fh);
        if ( !$ok ) {
            Cpanel::Logger->new()->warn("Could not close the file '$path' with error: $!");
            return;
        }
    }

    # Generate a new system id.
    # It's a 32-digit hex string.
    my $system_id = Cpanel::Rand::Get::getranddata( 32, [ 0 .. 9, 'a' .. 'f' ] );

    # A umask of 0222 results in 444 (-r--r--r--) for files. The Cpanel::Umask object helps
    # to ensure that the umask will be restored even if one of the early returns below is hit.
    my $umask_obj = Cpanel::Umask->new(0222);

    my $ok = open( my $fh, '>', $path );
    $fh->autoflush;
    if ( !$ok ) {
        Cpanel::Logger->new()->warn("Could not create the file '$path' with error: $!");
        return;
    }

    $ok = print( {$fh} $system_id );
    if ( !$ok ) {
        Cpanel::Logger->new()->warn("Could not write to '$path' with error: $!");
        return;
    }

    $ok = close($fh);
    if ( !$ok ) {
        Cpanel::Logger->new()->warn("Could not close the file '$path' with error: $!");
        return;
    }

    # We don't want someone to accidentally delete their unique system ID if they decide to delete
    # /var/cpanel/analytics just to free up space.
    #
    # This must occur after closing the previous file handle to avoid permissions errors on CloudLinux/AlmaLinux 8
    _make_immutable($path);

    return;
}

1;
