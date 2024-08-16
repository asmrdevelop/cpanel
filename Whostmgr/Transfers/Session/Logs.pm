package Whostmgr::Transfers::Session::Logs;

# cpanel - Whostmgr/Transfers/Session/Logs.pm      Copyright 2022 cPanel, L.L.C.
#                                                           All rights reserved.
# copyright@cpanel.net                                         http://cpanel.net
# This code is subject to the cPanel license. Unauthorized copying is prohibited

use strict;
use Cpanel::Exception                    ();
use Cpanel::Fcntl                        ();
use Cpanel::FileUtils::Dir               ();
use Cpanel::FileUtils::Open              ();
use Whostmgr::Transfers::Session::Config ();

use base 'Cpanel::LogTailer';

our $MASTER_LOG_FILE_NAME       = "master.log";
our $MASTER_ERROR_LOG_FILE_NAME = "master.error_log";

my $APPEND_MODE = Cpanel::Fcntl::or_flags(qw( O_WRONLY O_APPEND O_CREAT ));
my $READ_MODE   = Cpanel::Fcntl::or_flags(qw( O_RDONLY ));

#Parameters:
#   id          - the session ID
#   renderer    - the renderer object (defaults to a generic object that print()s)
sub new {
    my ( $class, %OPTS ) = @_;

    my $self = {};
    bless $self, $class;

    my $session_id   = $OPTS{'id'};
    my $renderer_obj = $OPTS{'renderer'} || $self->_create_default_renderer_object();

    if ( !length($session_id) || $session_id !~ m{^[0-9A-Za-z_]+$} ) {
        die Cpanel::Exception::create( 'InvalidParameter', 'The session ID “[_1]” may only contain alphanumeric characters and underscores.', [ length($session_id) ? $session_id : q<> ] );
    }

    $self->{'_session_id'}   = $session_id;
    $self->{'_renderer_obj'} = $renderer_obj;

    $self->_create_session_log_dir();

    return $self;
}

sub id {
    my ($self) = @_;

    return $self->{'_session_id'} || die Cpanel::Exception::create( 'AttributeNotSet', 'The attribute “[_1]” is not set.', ['_session_id'] );
}

sub get_log_modify_times {
    my ($self) = @_;

    my %modification_times = ();

    my $log_dir = $self->_dir();
    if ( -d $log_dir ) {
        opendir( my $log_dir_dh, $log_dir ) or die Cpanel::Exception::create( 'IO::DirectoryOpenError', [ 'path' => $log_dir, 'error' => $! ] );

        while ( my $file = readdir($log_dir_dh) ) {
            next if $file =~ /\A.{1,2}\z/;

            $modification_times{$file} = $self->_get_log_modify_time( $log_dir . '/' . $file );
        }

        closedir($log_dir_dh) or die Cpanel::Exception::create( 'IO::DirectoryCloseError', [ 'path' => $log_dir, 'error' => $! ] );
    }

    return \%modification_times;
}

#Returns a filehandle for reading (Active or Completed)
sub open_master_log_file_for_reading {
    my ($self) = @_;

    return $self->_open_for_read($MASTER_LOG_FILE_NAME);
}

#Returns a filehandle for reading (Active or Completed)
sub open_master_error_log_file_for_reading {
    my ($self) = @_;

    return $self->_open_for_read($MASTER_ERROR_LOG_FILE_NAME);
}

#Returns a filehandle for appending
sub open_master_log_file {
    my ($self) = @_;

    return $self->_open_for_append($MASTER_LOG_FILE_NAME);
}

#Returns a filehandle for appending
sub open_master_error_log_file {
    my ($self) = @_;

    return $self->_open_for_append($MASTER_ERROR_LOG_FILE_NAME);
}

#NOTE: This will die() if either the log file or the error log file is missing.
sub mark_session_completed {
    my ($self) = @_;

    return ( $self->mark_log_completed($MASTER_ERROR_LOG_FILE_NAME) && $self->mark_log_completed($MASTER_LOG_FILE_NAME) );
}

sub delete_log {
    my ($self) = @_;

    my $session_id = $self->id() || die Cpanel::Exception::create( 'AttributeNotSet', 'The system could not retrieve the attribute “[_1]” because it is not set.', ['_session_id'] );
    if ( -d "$Whostmgr::Transfers::Session::Config::SESSION_DIR/$session_id" ) {
        system '/bin/rm', '-rf', '--', "$Whostmgr::Transfers::Session::Config::SESSION_DIR/$session_id";
    }

    return 1;
}

sub _dir {
    my ($self) = @_;

    return "$Whostmgr::Transfers::Session::Config::SESSION_DIR/" . $self->id();
}

sub _get_log_modify_time {
    my ( $self, $filename ) = @_;

    if ( -f $filename ) {
        return ( stat _ )[9];
    }

    return;
}

sub _open_for_read {
    my ( $self, $filename ) = @_;

    if ( $self->is_log_completed($filename) ) {
        $filename = $self->_file_name_to_path_completed($filename);
    }
    else {
        $filename = $self->_file_name_to_path_active($filename);
    }

    local $!;
    Cpanel::FileUtils::Open::sysopen_with_real_perms( my $log_fh, $filename, $READ_MODE, 0600 ) or do {
        die Cpanel::Exception::create(
            'IO::FileOpenError',
            [
                path        => $filename,
                error       => $!,
                mode        => $READ_MODE,
                permissions => 0600,
            ]
        );
    };

    return $log_fh;
}

sub _open_for_append {
    my ( $self, $filename ) = @_;

    $filename = $self->_file_name_to_path_active($filename);

    local $!;
    Cpanel::FileUtils::Open::sysopen_with_real_perms( my $log_fh, $filename, $APPEND_MODE, 0600 ) or do {
        die Cpanel::Exception::create(
            'IO::FileOpenError',
            [
                path        => $filename,
                error       => $!,
                mode        => $APPEND_MODE,
                permissions => 0600,
            ]
        );
    };

    return $log_fh;
}

sub _create_session_log_dir {
    my ($self) = @_;

    my $id = $self->id();

    $self->_create_session_dir();
    return _safemkdir_or_die( $self->_dir(), 0700 );
}

#----------------------------------------------------------------------
#STATIC INTERFACE

#static
sub expunge_expired_logs {

    _create_session_dir();

    my $now      = time();
    my $killtime = $Whostmgr::Transfers::Session::Config::MAX_SESSION_AGE;    #time in seconds

    my $session_dir = $Whostmgr::Transfers::Session::Config::SESSION_DIR;

    my $sessions_ar = Cpanel::FileUtils::Dir::get_directory_nodes($session_dir);

    foreach my $session (@$sessions_ar) {
        next if $session =~ /\A\.{1,2}\z/;
        if ( -d "$session_dir/$session" && ( stat _ )[9] + $killtime < $now ) {
            system '/bin/rm', '-rf', '--', "$session_dir/$session";
        }
    }

    return 1;
}

# static
sub _create_session_dir {
    return _safemkdir_or_die( $Whostmgr::Transfers::Session::Config::SESSION_DIR, 0700 );
}

sub _safemkdir_or_die {
    my ($dir) = @_;

    if ( !-d $dir ) {
        local $!;
        mkdir( $dir, 0700 ) || die Cpanel::Exception::create( 'IO::DirectoryCreateError', [ path => $dir, error => $! ] );
    }

    return 1;
}

1;
