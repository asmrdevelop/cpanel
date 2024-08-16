
# cpanel - Cpanel/iContact/History.pm              Copyright 2022 cPanel, L.L.C.
#                                                           All rights reserved.
# copyright@cpanel.net                                         http://cpanel.net
# This code is subject to the cPanel license. Unauthorized copying is prohibited

package Cpanel::iContact::History;

use strict;

use Cpanel::ConfigFiles                                     ();
use Cpanel::MultiUserDirStore::TimeIndexedData              ();
use Cpanel::MultiUserDirStore::VirtualUser::TimeIndexedData ();

our $USER_NOTIFICATIONS_HISTORY_STORAGE_DIR = 'history';
our $SECONDS_TO_KEEP_HISTORY_FOR_EACH_USER  = ( 10 * 86400 );    # 10 DAYS

###########################################################################
#
# Method:
#   get_user_contact_history
#
# Description:
#   This factory method creates a Cpanel::MultiUserDirStore::TimeIndexedData
#   object that stores data in the $USER_NOTIFICATIONS_DIR history
#   storage directory.
#
# Parameters:
#   user      - The user to store the data for
#
# Exceptions:
#   MissingParameter         - provided when the user, dir, or keep_time parameter is missing.
#   InvalidParameter         - provided when the keep_time parameter is invalid.
#   IO::DirectoryCreateError - provided if the directory that stores the cache cannot be created.
#   IO::ChownError           - provided if the chown of the user directory fails.
#   Any Exceptions from the following modules:
#       Cpanel::Validate::FilesystemNodeName
#
# Returns:
#   A Cpanel::MultiUserDirStore::TimeIndexedData object
#
sub get_user_contact_history {
    my (%OPTS) = @_;

    return Cpanel::MultiUserDirStore::TimeIndexedData->new(
        'keep_time' => $SECONDS_TO_KEEP_HISTORY_FOR_EACH_USER,
        'dir'       => $Cpanel::ConfigFiles::USER_NOTIFICATIONS_DIR,
        'subdir'    => $USER_NOTIFICATIONS_HISTORY_STORAGE_DIR,
        %OPTS,
    );
}

###########################################################################
#
# Method:
#   get_virtual_user_contact_history
#
# Description:
#   This factory method creates a Cpanel::MultiUserDirStore::VirtualUser::TimeIndexedData
#   object that stores data in the $USER_NOTIFICATIONS_DIR history
#   storage directory.
#
# Parameters:
#   user         - The user to store the data for
#   service      - The service for which to create the contact history.
#   domain       - The domain of the virtual user.
#   virtual_user - The name of the virtual user for which to store contact history.
#
# Exceptions:
#   MissingParameter         - provided when the user, service, domain, virtual_user, dir, or keep_time parameter is missing.
#   InvalidParameter         - provided when the keep_time parameter is invalid.
#   DomainOwnership          - provided when the supplied user does not own the supplied domain.
#   UserNotFound             - provided when the supplied virtual_user@domain does not exist.
#   IO::DirectoryCreateError - provided if the directory that stores the cache cannot be created.
#   IO::ChownError           - provided if the chown of the user directory fails.
#   Any Exceptions from the following modules:
#       Cpanel::Validate::FilesystemNodeName
#
# Returns:
#   A Cpanel::MultiUserDirStore::VirtualUser::TimeIndexedData object
#
sub get_virtual_user_contact_history {
    my (%OPTS) = @_;

    return Cpanel::MultiUserDirStore::VirtualUser::TimeIndexedData->new(
        'keep_time' => $SECONDS_TO_KEEP_HISTORY_FOR_EACH_USER,
        'dir'       => $Cpanel::ConfigFiles::USER_NOTIFICATIONS_DIR,
        'subdir'    => $USER_NOTIFICATIONS_HISTORY_STORAGE_DIR,
        %OPTS,
    );
}

1;
