
# cpanel - Cpanel/Admin/Modules/Cpanel/restore.pm  Copyright 2022 cPanel, L.L.C.
#                                                           All rights reserved.
# copyright@cpanel.net                                         http://cpanel.net
# This code is subject to the cPanel license. Unauthorized copying is prohibited

package Cpanel::Admin::Modules::Cpanel::restore;

use strict;
use warnings;

use parent qw( Cpanel::Admin::Base );

use Cpanel::Exception ();

use Try::Tiny;

sub _actions__pass_exception {
    return (
        'DIRECTORYLISTING',
        'QUERYFILEINFO',
        'RESTOREFILE',
        'GETUSERS',
    );
}

sub _actions { return _actions__pass_exception() }

sub _demo_actions {
    return ();
}

sub _feature_check {
    my ($self) = @_;

    my $caller_username = $self->get_caller_username();
    require Cpanel;
    Cpanel::initcp($caller_username);

    die Cpanel::Exception::create( 'FeatureNotEnabled', 'The File Restoration feature is disabled.' ) if ( !Cpanel::hasfeature('filerestoration') );

    return;
}

###########################################################################
#
# Method:
#   DIRECTORYLISTING
#
# Description:
#   Merges a users files from all backup meta files.
#
# Parameters:
#   dir - directory (homedir or below) to get a listing from
#
# Returns:
#   A hashref that lists a files and directories for files there is one
#   other flag that indicates if the file currently exists on the disk
#

sub DIRECTORYLISTING {
    my ( $self, $ref_hr ) = @_;
    $self->_feature_check();

    die Cpanel::Exception::create( 'MissingParameter', [ 'name' => 'path' ] ) if !$ref_hr->{'path'};

    # prevent security issue, path being relative (via ../whatever)
    die Cpanel::Exception::create( 'InvalidParameter', 'The path must begin with a forward slash (/).' ) if ( substr( $ref_hr->{'path'}, 0,                               1 ) ne '/' );
    die Cpanel::Exception::create( 'InvalidParameter', 'The path must end with a forward slash (/).' )   if ( substr( $ref_hr->{'path'}, length( $ref_hr->{'path'} ) - 1, 1 ) ne '/' );

    require Cpanel::Backup::Restore;

    my $caller_username = $self->get_caller_username();
    my $path            = $ref_hr->{'path'};
    my $paginate        = $ref_hr->{'paginate'};

    my $response_to_caller = Cpanel::Backup::Restore::directory_listing( $caller_username, $path, $paginate );

    ############################################################################################################
    ###/
    ##/ This is a temporary block until we have the UI updated to deal with numbers rather than text strings.
    #/   See case HB-3402

    if ( ref($response_to_caller) eq 'ARRAY' ) {
        foreach my $item_hr ( @{$response_to_caller} ) {
            if ( defined( $item_hr->{'type'} ) and $item_hr->{'type'} == 0 ) {
                $item_hr->{'type'} = 'file';
            }
            elsif ( defined( $item_hr->{'type'} ) and $item_hr->{'type'} == 1 ) {
                $item_hr->{'type'} = 'dir';
            }
            elsif ( defined( $item_hr->{'type'} ) and $item_hr->{'type'} == 2 ) {
                $item_hr->{'type'} = 'symlink';
            }

            if ( defined( $item_hr->{'onDiskType'} ) and $item_hr->{'onDiskType'} == 0 ) {
                $item_hr->{'type'} = 'file';
            }
            elsif ( defined( $item_hr->{'onDiskType'} ) and $item_hr->{'onDiskType'} == 1 ) {
                $item_hr->{'type'} = 'dir';
            }
            elsif ( defined( $item_hr->{'onDiskType'} ) and $item_hr->{'onDiskType'} == 2 ) {
                $item_hr->{'type'} = 'symlink';
            }
        }
    }

    #\
    ##\ This is a temporary block until we have the UI updated to deal with numbers rather than text strings
    ###\
    ############################################################################################################

    return $response_to_caller;
}

###########################################################################
#
# Method:
#   QUERYFILEINFO
#
# Description:
#   Get a list of all copies of the file in all the backups with info
#
# Parameters:
#   path - path (/ means homedir)
#
# Returns:
#   An arrayref with an hashref for each copy of the file found in the
#   backups.
#
#   Hashref includes { backupPath, backupDate, fileSize, modifiedDate }
#

sub QUERYFILEINFO {
    my ( $self, $ref_hr ) = @_;

    if ( defined $ref_hr->{'fullpath'} ) {
        $ref_hr->{'path'} = $ref_hr->{'fullpath'};
    }

    $self->_feature_check();

    die Cpanel::Exception::create( 'MissingParameter', [ 'name' => 'path' ] ) if !$ref_hr->{'path'};

    # prevent security issue, path being relative (via ../whatever)
    die Cpanel::Exception::create( 'InvalidParameter', 'The path must begin with a forward slash (/).' ) if ( substr( $ref_hr->{'path'}, 0, 1 ) ne '/' );

    require Cpanel::Backup::Restore;

    my $caller_username = $self->get_caller_username();
    my $fullpath        = $ref_hr->{'path'};

    my $return_exists_flag_to_caller = 0;
    $return_exists_flag_to_caller = $ref_hr->{'exists'} if ( exists $ref_hr->{'exists'} );

    my $response_to_caller = Cpanel::Backup::Restore::query_file_info( $caller_username, $fullpath, $return_exists_flag_to_caller );

    ############################################################################################################
    ###/
    ##/ This is a temporary block until we have the UI updated to deal with numbers rather than text strings
    #/   See case HB-3402

    if ( ref($response_to_caller) eq 'ARRAY' ) {
        foreach my $item_hr ( @{$response_to_caller} ) {
            if ( defined( $item_hr->{'type'} ) and $item_hr->{'type'} == 0 ) {
                $item_hr->{'type'} = 'file';
            }
            elsif ( defined( $item_hr->{'type'} ) and $item_hr->{'type'} == 1 ) {
                $item_hr->{'type'} = 'dir';
            }
            elsif ( defined( $item_hr->{'type'} ) and $item_hr->{'type'} == 2 ) {
                $item_hr->{'type'} = 'symlink';
            }

            if ( defined( $item_hr->{'backupType'} ) and $item_hr->{'backupType'} == 0 ) {
                $item_hr->{'backupType'} = 'uncompressed';
            }
            elsif ( defined( $item_hr->{'backupType'} ) and $item_hr->{'backupType'} == 1 ) {
                $item_hr->{'backupType'} = 'compressed';
            }
            elsif ( defined( $item_hr->{'type'} ) and $item_hr->{'backupType'} == 2 ) {
                $item_hr->{'backupType'} = 'incremental';
            }
        }
    }

    #\
    ##\ This is a temporary block until we have the UI updated to deal with numbers rather than text strings
    ###\
    ############################################################################################################

    return $response_to_caller;
}

###########################################################################
#
# Method:
#   RESTOREFILE
#
# Description:
#   Restore the file from the specific backup.
#
# Parameters:
#   backupPath - path to the top of the backup.
#   path       - path to the file in the user's directory. Must begin with a
#                slash.
#   overwrite  - 1 or 0, 1 allows the file in the user's directory to be
#                overwritten by the one in the backup.
#
# Returns:
#   Success of 1 or 0
#

sub RESTOREFILE {
    my ( $self, $ref_hr ) = @_;

    if ( defined $ref_hr->{'fullpath'} ) {
        $ref_hr->{'path'} = $ref_hr->{'fullpath'};
    }

    $self->_feature_check();

    die Cpanel::Exception::create( 'MissingParameter', [ 'name' => 'backupID' ] )  if !defined $ref_hr->{'backupID'};
    die Cpanel::Exception::create( 'MissingParameter', [ 'name' => 'path' ] )      if !defined $ref_hr->{'path'};
    die Cpanel::Exception::create( 'MissingParameter', [ 'name' => 'overwrite' ] ) if !defined $ref_hr->{'overwrite'};

    # prevent security issue, path being relative (via ../whatever)
    die Cpanel::Exception::create( 'InvalidParameter', 'The path must begin with a forward slash (/).' ) if ( substr( $ref_hr->{'path'}, 0, 1 ) ne '/' );
    die Cpanel::Exception::create( 'InvalidParameter', 'Set the overwrite flag to 1 or 0.' )             if ( $ref_hr->{'overwrite'} != 1 && $ref_hr->{'overwrite'} != 0 );

    require Cpanel::Backup::Restore;

    my $caller_username = $self->get_caller_username();
    my $backupID        = $ref_hr->{'backupID'};
    my $fullpath        = $ref_hr->{'path'};
    my $overwrite       = $ref_hr->{'overwrite'};

    my $response_to_caller = Cpanel::Backup::Restore::restore_file( $caller_username, $backupID, $fullpath, $overwrite );
    return $response_to_caller;
}

###########################################################################
#
# Method:
#   GETUSERS
#
# Description:
#   List users that you 'own' (e.g. resell) which currently have metadata.
#
# Parameters:
#   None.
#
# Returns:
#   ARRAYREF of users with backup metadata.
#

sub GETUSERS {
    my ( $self, $ref_hr ) = @_;

    $self->_feature_check();

    require Cpanel::Backup::Metadata;

    my $response_to_caller = [];
    @$response_to_caller = Cpanel::Backup::Metadata::get_all_users();    # not filtered by ownership

    do {
        local $ENV{REMOTE_USER} = $self->{caller}->{_username};          # REMOTE_USER is required for init_acls() to function correctly, and AdminBins lack REMOTE_USER
        require Whostmgr::ACLS;
        Whostmgr::ACLS::init_acls();
        return $response_to_caller if Whostmgr::ACLS::hasroot();
    };

    if ($Cpanel::isreseller) {
        require Whostmgr::AcctInfo;
        my @child_accts = Whostmgr::AcctInfo::getaccts( $self->{caller}->{_username} );

        #Make sure the reseller can restore their own stuff regardless of whether they own themselves or not
        push( @child_accts, $self->{caller}->{_username} ) unless grep { $_ eq $self->{caller}->{_username} } @child_accts;
        @$response_to_caller = grep {
            my $subject = $_;
            grep { $subject eq $_ } @child_accts
        } @$response_to_caller;
        return $response_to_caller;
    }

    #Filter out info the user should not know
    @$response_to_caller = grep { $_ eq $self->{caller}->{_username} } @$response_to_caller;
    return $response_to_caller;
}

#----------------------------------------------------------------------

1;
