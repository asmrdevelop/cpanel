package Cpanel::MultiUserDirStore::Flags;

# cpanel - Cpanel/MultiUserDirStore/Flags.pm       Copyright 2022 cPanel, L.L.C.
#                                                           All rights reserved.
# copyright@cpanel.net                                         http://cpanel.net
# This code is subject to the cPanel license. Unauthorized copying is prohibited

use strict;
use Cpanel::Validate::FilesystemNodeName ();
use Cpanel::FileUtils::TouchFile         ();

use base 'Cpanel::MultiUserDirStore';

##########################################################################
#
# Method:
#   get_state
#
# Description:
#   Gets the state a flag.
#
# Parameters:
#   $flag   - The name of the flag
#
# Exceptions:
#   Any Exceptions from the following modules:
#       Cpanel::Validate::FilesystemNodeName
#
# Returns:
#   1 - The flag is enabled
#   0 - The flag is disabled
#
sub get_state {
    my ( $self, $flag ) = @_;

    Cpanel::Validate::FilesystemNodeName::validate_or_die($flag);

    return -e "$self->{'path'}/$flag" ? 1 : 0;
}

##########################################################################
#
# Method:
#   set_state
#
# Description:
#   Sets the state a flag.
#
# Parameters:
#   $flag     - The name of the flag
#   $enabled  - 1 or 0 depending on the flag being enabled
#
# Exceptions:
#   Any Exceptions from the following modules:
#       Cpanel::Validate::FilesystemNodeName
#
# Returns:
#   1 - The state has been changed
#   0 - The state could not be changed
#

sub set_state {
    my ( $self, $flag, $enabled ) = @_;

    Cpanel::Validate::FilesystemNodeName::validate_or_die($flag);

    die "The parameter “enabled” may only be “0” or “1”." if $enabled !~ m{^[01]+$};

    if ($enabled) {
        return 1 if -e "$self->{'path'}/$flag";
        Cpanel::FileUtils::TouchFile::touchfile("$self->{'path'}/$flag") || return 0;
    }
    else {
        return 1 if !-e "$self->{'path'}/$flag";
        unlink("$self->{'path'}/$flag") || return 0;
    }

    return 1;
}

1;
