package Cpanel::FileUtils::Write::JSON::Lazy;

# cpanel - Cpanel/FileUtils/Write/JSON/Lazy.pm     Copyright 2022 cPanel, L.L.C.
#                                                           All rights reserved.
# copyright@cpanel.net                                         http://cpanel.net
# This code is subject to the cPanel license. Unauthorized copying is prohibited

use strict;
use warnings;

# This module needs a small memory
# footprint.  Avoid adding use statements
###########################################################################
#
# Method:
#   write_file
#
# Description:
#   This module writes a serializes and object into a JSON stream
#   and writes it to a file handle or file
#
# Parameters:
#
#   $file_to_fh - The file or file handle to write the JSON stream to
#
#   $data       - The unserialized data structure
#
#   $perms      - optional, filesystem perms. Defaults to 0600.
#
# Returns:
#   The result from the Cpanel::FileUtils::Write:: function or 0
#   if Cpanel::JSON is not loaded
#

sub write_file {
    my ( $file_or_fh, $data, $perms ) = @_;

    if ( exists $INC{'Cpanel/JSON.pm'} && exists $INC{'JSON/XS.pm'} && ( my $Dump = 'Cpanel::JSON'->can('Dump') ) ) {    # PPI NO PARSE -- check earlier - must be quoted or it ends up in the stash
                                                                                                                         # need to check for both for updatenow.static
                                                                                                                         # only required if JSON::XS is already preloaded
        require Cpanel::FileUtils::Write if !$INC{'Cpanel/FileUtils/Write.pm'};
        require Cpanel::FHUtils::Tiny    if !$INC{'Cpanel/FHUtils/Tiny.pm'};
        my $func = Cpanel::FHUtils::Tiny::is_a($file_or_fh) ? 'write_fh' : 'overwrite';

        #NOTE: write_fh() doesn't actually take $perms as an argument.
        if ( $func eq 'write_fh' ) {
            if ( !defined $perms ) {
                $perms = 0600;
            }

            chmod( $perms, $file_or_fh ) or die "Failed to set permissions on the file handle passed to Cpanel::FileUtils::Write::JSON::Lazy::write_file because of an error: $!";
        }

        return Cpanel::FileUtils::Write->can($func)->(
            $file_or_fh,
            $Dump->($data),
            $perms
        );
    }
    return 0;
}

###########################################################################
#
# Method:
#   write_file_pretty
#
# Description:
#   This module writes a serializes and object into a JSON stream
#   and writes it to a file handle or file in a human readable form.
#
# Parameters:
#
#   $file_to_fh - The file or file handle to write the JSON stream to
#
#   $data       - The unserialized data structure
#
#   $perms      - optional, filesystem perms. Defaults to 0600.
#
# Returns:
#   The result from the Cpanel::FileUtils::Write:: function or 0
#   if Cpanel::JSON is not loaded
#

sub write_file_pretty {
    my ( $file_or_fh, $data, $perms ) = @_;

    if ( exists $INC{'Cpanel/JSON.pm'} && exists $INC{'JSON/XS.pm'} && ( my $Dump = 'Cpanel::JSON'->can('pretty_dump') ) ) {    # PPI NO PARSE -- check earlier - must be quoted or it ends up in the stash
                                                                                                                                # need to check for both for updatenow.static
                                                                                                                                # only required if JSON::XS is already preloaded
        require Cpanel::FileUtils::Write if !$INC{'Cpanel/FileUtils/Write.pm'};
        require Cpanel::FHUtils::Tiny    if !$INC{'Cpanel/FHUtils/Tiny.pm'};
        my $func = Cpanel::FHUtils::Tiny::is_a($file_or_fh) ? 'write_fh' : 'overwrite';

        #NOTE: write_fh() doesn't actually take $perms as an argument.
        if ( $func eq 'write_fh' ) {
            if ( !defined $perms ) {
                $perms = 0600;
            }

            chmod( $perms, $file_or_fh ) or die "Failed to set permissions on the file handle passed to Cpanel::FileUtils::Write::JSON::Lazy::write_file because of an error: $!";
        }

        return Cpanel::FileUtils::Write->can($func)->(
            $file_or_fh,
            $Dump->($data),
            $perms
        );
    }
    return 0;
}

1;
