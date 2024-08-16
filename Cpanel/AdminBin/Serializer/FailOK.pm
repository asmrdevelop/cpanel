package Cpanel::AdminBin::Serializer::FailOK;

# cpanel - Cpanel/AdminBin/Serializer/FailOK.pm    Copyright 2022 cPanel, L.L.C.
#                                                           All rights reserved.
# copyright@cpanel.net                                         http://cpanel.net
# This code is subject to the cPanel license. Unauthorized copying is prohibited

use strict;
use warnings;

###########################################################################
#
# FailOK should only be used in places where its ok for an of the actions to fail.
# In this instance we are using it to load cache files and we do not care
# if it is successful since we can fallback to loading the non-cache.
#
# The caller is expected to be able to handle this module failing to load their
# data.
#
# This module provides a drop in replacement for Cpanel::JSON::FailOK without
# setting the UTF-8 flag
#
###########################################################################
#
# Method:
#   LoadModule
#
# Description:
#   Attempt to load the Cpanel::AdminBin::Serializer module and warn if it is  # PPI USE OK - ignore
#   not available except on fresh installs.
#
# Returns:
#   1 if the module was able to be loaded
#   0 upon failure
#
sub LoadModule {
    local $@;

    return 1 if $INC{'Cpanel/AdminBin/Serializer.pm'};

    # Try::Tiny cannot be used here due to
    # memory requirements
    my $load_ok = eval {
        local $SIG{'__DIE__'};     # Suppress spewage as we may be reading an invalid cache
        local $SIG{'__WARN__'};    # and since failure is ok to throw it away
        require Cpanel::AdminBin::Serializer;
        1;
    };

    if ( !$load_ok && !$ENV{'CPANEL_BASE_INSTALL'} && index( $^X, '/usr/local/cpanel' ) == 0 ) {
        warn $@;
    }

    return $load_ok ? 1 : 0;
}

###########################################################################
#
# Method:
#   LoadFile
#
# Description:
#   Attempt to read and deserialize JSON data from a file
#   or file handle.
#
# Returns:
#   A reference to the loaded JSON data
#   undef if Cpanel::AdminBin::Serializer is not available or upon failure of Cpanel::AdminBin::Serializer::LoadFile
#
#   * It's possible that a JSON file many contain simply 'null'.  In that case
#   * a successful load can be distinguished from failure by checking $@.
#
# NOTE: This will clobber $@.
#
sub LoadFile {
    my ( $file_or_fh, $path ) = @_;

    return undef if !$INC{'Cpanel/AdminBin/Serializer.pm'};

    # We cannot use Try::Tiny because this code runs in many tight loops
    return eval {
        local $SIG{'__DIE__'};     # Suppress spewage as we may be reading an invalid cache
        local $SIG{'__WARN__'};    # and since failure is ok to throw it away
        Cpanel::AdminBin::Serializer::LoadFile( $file_or_fh, undef, $path );
    };
}
1;
