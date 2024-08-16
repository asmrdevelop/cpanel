package Whostmgr::Backup::Pkgacct::Logs;

# cpanel - Whostmgr/Backup/Pkgacct/Logs.pm         Copyright 2022 cPanel, L.L.C.
#                                                           All rights reserved.
# copyright@cpanel.net                                         http://cpanel.net
# This code is subject to the cPanel license. Unauthorized copying is prohibited

use strict;
## no critic qw(TestingAndDebugging::RequireUseWarnings) - not fully vetted for warnings

use IO::Handle                        ();
use Cpanel::Exception                 ();
use Cpanel::FileUtils::Dir            ();
use Cpanel::Mkdir                     ();
use File::Path                        ();
use Whostmgr::Backup::Pkgacct::Config ();

use parent qw( Whostmgr::Transfers::Session::Logs );

our $MASTER_LOG_FILE_NAME       = "master.log";
our $MASTER_ERROR_LOG_FILE_NAME = "master.error_log";

# static
sub fetch_master_log {

    my ($session_id) = @_;

    require Cpanel::LogTailer::Renderer::Scalar;
    my $renderer = Cpanel::LogTailer::Renderer::Scalar->new();

    require Whostmgr::Backup::Pkgacct::Logs;
    my $log_obj = Whostmgr::Backup::Pkgacct::Logs->new( 'id' => $session_id, 'renderer' => $renderer );

    $log_obj->tail_log( "master.log", 0, { 'one_loop' => 1 } );

    return $$renderer;
}

sub delete_log {
    my ($self) = @_;

    my $session_id       = $self->id() || die Cpanel::Exception::create( 'AttributeNotSet', 'The system could not retrieve the attribute “[_1]” because it is not set.', ['_session_id'] );
    my $session_dir_path = "$Whostmgr::Backup::Pkgacct::Config::SESSION_DIR/$session_id";

    # Paranoia... shouldn't ever happen.
    if ( length $session_dir_path < 2 ) {
        die Cpanel::Exception::create( 'IO::DirectoryDeleteError', 'The system cannot delete the directory “[_1]”.', $session_dir_path );
    }

    if ( -d $session_dir_path ) {
        File::Path::rmtree($session_dir_path);
    }

    return 1;
}

sub _dir {
    my ($self) = @_;

    return "$Whostmgr::Backup::Pkgacct::Config::SESSION_DIR/" . $self->id();
}

#static
sub expunge_expired_logs {

    _create_session_dir();

    my $now      = time();
    my $killtime = $Whostmgr::Backup::Pkgacct::Config::MAX_SESSION_AGE;    #time in seconds

    my $session_dir = $Whostmgr::Backup::Pkgacct::Config::SESSION_DIR;

    my $sessions_ar = Cpanel::FileUtils::Dir::get_directory_nodes($session_dir);

    foreach my $session (@$sessions_ar) {
        next if $session =~ /\A\.{1,2}\z/;
        my $session_dir_path = "$session_dir/$session";

        # Paranoia... shouldn't ever happen.
        if ( length $session_dir_path < 2 ) {
            die Cpanel::Exception::create( 'IO::DirectoryDeleteError', 'The system cannot delete the directory “[_1]”.', $session_dir_path );
        }

        if ( -d $session_dir_path && ( stat _ )[9] + $killtime < $now ) {
            File::Path::rmtree($session_dir_path);
        }
    }

    return 1;
}

# static
sub _create_session_dir {
    return _safemkdir_or_die( $Whostmgr::Backup::Pkgacct::Config::SESSION_DIR, 0700 );
}

sub _safemkdir_or_die {
    my ( $dir, $mode ) = @_;

    Cpanel::Mkdir::ensure_directory_existence_and_mode( $dir, $mode );

    return 1;
}

1;
