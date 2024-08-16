package Cpanel::MultiUserDirStore::TimeIndexedData;

# cpanel - Cpanel/MultiUserDirStore/TimeIndexedData.pm
#                                                  Copyright 2022 cPanel, L.L.C.
#                                                           All rights reserved.
# copyright@cpanel.net                                         http://cpanel.net
# This code is subject to the cPanel license. Unauthorized copying is prohibited

use strict;
use Cpanel::Validate::FilesystemNodeName ();
use Cpanel::Exception                    ();
use Cpanel::FileUtils::Open              ();

use base 'Cpanel::MultiUserDirStore';

###########################################################################
#
# Method:
#   new
#
# Description:
#   This module provides a simple filesystem store for root
#   to store time-indexed data for a specific system per user.
#
# Parameters:
#   dir       - The directory to store the data in
#   user      - The user to store the data for
#   subdir    - The subdirectory to store the cache in
#   keep_time - The time is seconds that data should be kept in the store before it expires.
#
# Exceptions:
#   MissingParameter         - provided when the dir or keep_time parameter is missing.
#   InvalidParameter         - provided when the keep_time parameter is invalid.
#   IO::DirectoryCreateError - provided if the directory that stores the cache cannot be created.
#   IO::ChownError           - provided if the chown of the user directory fails.
#   Any Exceptions from the following modules:
#       Cpanel::Validate::FilesystemNodeName
#
# Returns:
#   A Cpanel::MultiUserDirStore::TimeIndexedData object
#
sub new {
    my ( $class, %OPTS ) = @_;

    die Cpanel::Exception::create( 'MissingParameter', 'The required parameter “[_1]” is missing.',    ['keep_time'] ) if !$OPTS{'keep_time'};
    die Cpanel::Exception::create( 'InvalidParameter', 'The parameter “[_1]” must be a whole number.', ['keep_time'] ) if $OPTS{'keep_time'} !~ m{^[1-9][0-9]*$};

    my $obj = $class->SUPER::new(%OPTS);

    $obj->{'keep_time'} = $OPTS{'keep_time'};

    return $obj;
}

##########################################################################
#
# Method:
#   purge_expired
#
# Description:
#   Removes expired entries from the datastore.
#
# Parameters:
#   None
#
# Exceptions:
#   IO::DirectoryOpenError
#
# Returns:
#   1 - The expired entries were purged
#   0 - The expired entries were not purged
#
sub purge_expired {
    my ($self) = @_;

    my $expiretime = ( time() - $self->{'keep_time'} );
    my $path       = $self->{'path'};

    if ( opendir( my $dh, $path ) ) {
        my $cruntime;
        my @expired_files = map {
            $cruntime = ( split( m/_/, $_ ) )[0] || $expiretime;
            $cruntime < $expiretime ? "$path/$_" : ();
        } grep { substr( $_, 0, 1 ) =~ tr{0-9}{} } readdir($dh);

        unlink(@expired_files) if @expired_files;

        closedir($dh);

        return 1;
    }
    else {
        die Cpanel::Exception::create( 'IO::DirectoryOpenError', [ path => $path, error => $! ] );
    }

    return 0;
}

##########################################################################
#
# Method:
#   get_entry_target
#
# Description:
#   Return a filehandle and path for an entry in the data store
#
# Parameters:
#   time - The time the entry was created
#   fields - All the fields for entry in an arrayref
#   type - The type of entry
#
# Exceptions:
#   MissingParameter
#   IO::FileOpenError
#   Empty/Reserved/TooManyBytes/InvalidCharacters (validate_or_die)
#
# Returns:
#   A hashref in the following format:
#   {
#     'fh' =>   $fh   - A file handle that references the entry
#               undef - Could not create the file handle -- Undef $fh likely won't be returned in practice, as it looks like most likely would throw in that instance.
#     'path' => The path to the file in the datastore
#   }

sub get_entry_target {
    my ( $self, %OPTS ) = @_;

    foreach my $param (qw(fields type)) {
        if ( !$OPTS{$param} ) {
            die Cpanel::Exception::create( 'MissingParameter', 'The required parameter “[_1]” is missing.', [$param] );
        }
    }

    my $time   = $OPTS{'time'} || time();
    my $fields = $OPTS{'fields'};
    my $type   = $OPTS{'type'};

    if ( ref $fields ne 'ARRAY' ) {
        die Cpanel::Exception::create( 'InvalidParameter', 'The parameter “[_1]” must be an arrayref.', ['fields'] );
    }
    Cpanel::Validate::FilesystemNodeName::validate_or_die($time);
    foreach my $field ( @{$fields} ) {
        Cpanel::Validate::FilesystemNodeName::validate_or_die($field) if length $field;
    }
    Cpanel::Validate::FilesystemNodeName::validate_or_die($type);

    my $filename  = join( '_', $self->_strip_underscores( $time, @{$fields} ) ) . '.' . $type;
    my $file_path = "$self->{'path'}/$filename";
    my $fh;

    Cpanel::FileUtils::Open::sysopen_with_real_perms( $fh, $file_path, 'O_WRONLY|O_CREAT', 0644 ) or die Cpanel::Exception::create( 'IO::FileOpenError', [ path => $file_path, error => $! ] );

    return {
        'fh'   => $fh,
        'path' => $file_path,
    };
}

sub _strip_underscores {
    my ( $self, @data ) = @_;

    tr<_><>d for @data;

    return @data;
}

1;
