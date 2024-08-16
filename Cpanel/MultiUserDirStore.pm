package Cpanel::MultiUserDirStore;

# cpanel - Cpanel/MultiUserDirStore.pm             Copyright 2022 cPanel, L.L.C.
#                                                           All rights reserved.
# copyright@cpanel.net                                         http://cpanel.net
# This code is subject to the cPanel license. Unauthorized copying is prohibited

use strict;
use warnings;

use Cpanel::Exception                    ();
use Cpanel::PwCache                      ();
use Cpanel::LoadModule                   ();
use Cpanel::Validate::FilesystemNodeName ();
use Cpanel::Validate::FilesystemPath     ();

###########################################################################
#
# Method:
#   new
#
# Description:
#   This module provides a simple filesystem store for root
#   to store data for a specific system per user.
#
# Parameters:
#   dir    - The directory to store the data in
#   user   - The user to store the data for
#   subdir - The subdirectory to store the cache in
#
# Exceptions:
#   MissingParameter         - provided when the dir parameter is missing.
#   IO::DirectoryCreateError - provided if the directory that stores the cache cannot be created.
#   IO::ChownError           - provided if the chown of the user directory fails.
#   Any Exceptions from the following modules:
#       Cpanel::Validate::FilesystemNodeName
#
# Returns:
#   A Cpanel::MultiUserDirStore object
#
sub new {
    my ( $class, %OPTS ) = @_;

    foreach my $param (qw(dir subdir user)) {
        die Cpanel::Exception::create( 'MissingParameter', 'The required parameter “[_1]” is missing.', [$param] ) if !$OPTS{$param};
    }

    my $dir    = $OPTS{'dir'};
    my $user   = $OPTS{'user'};
    my $subdir = $OPTS{'subdir'};    # Should we name this something else?

    Cpanel::Validate::FilesystemNodeName::validate_or_die($subdir);
    Cpanel::Validate::FilesystemNodeName::validate_or_die($user);
    Cpanel::Validate::FilesystemPath::die_if_any_relative_nodes($dir);

    my $user_gid = ( Cpanel::PwCache::getpwnam($user) )[3];
    if ( !defined $user_gid ) {
        die Cpanel::Exception::create( 'InvalidParameter', 'The parameter “[_1]” with a value of “[_2]” must be a valid system user.', [ 'user', $user ] );
    }

    my $user_dir = "$dir/$user";
    if ( !-d $user_dir ) {
        if ( !-d $dir ) {
            Cpanel::LoadModule::load_perl_module('Cpanel::SafeDir::MK');
            Cpanel::SafeDir::MK::safemkdir( $dir, 0751 ) || die Cpanel::Exception::create( 'IO::DirectoryCreateError', [ path => $dir, error => $! ] );
        }

        Cpanel::LoadModule::load_perl_module('Cpanel::SafeDir::MK');
        Cpanel::SafeDir::MK::safemkdir( $user_dir, 0750 ) || die Cpanel::Exception::create( 'IO::DirectoryCreateError', [ path => $user_dir, error => $! ] );
        chown( 0, $user_gid, $user_dir ) || die Cpanel::Exception::create( 'IO::ChownError', [ path => [$user_dir], uid => 0, gid => $user_gid, error => $! ] );
    }

    my $path = $class->_init_path(%OPTS);

    return bless { 'dir' => $dir, 'subdir' => $subdir, 'user' => $user, 'path' => $path }, $class;
}

sub _init_path {
    my ( $class, %OPTS ) = @_;

    my ( $dir, $user, $subdir ) = @OPTS{qw(dir user subdir)};

    my $path = "$dir/$user/$subdir";

    if ( !-d $path ) {
        Cpanel::LoadModule::load_perl_module('Cpanel::SafeDir::MK');
        Cpanel::SafeDir::MK::safemkdir( $path, 0755 ) || die Cpanel::Exception::create( 'IO::DirectoryCreateError', [ path => $path, error => $! ] );
    }

    return $path;
}

1;
