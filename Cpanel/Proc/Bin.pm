package Cpanel::Proc::Bin;

# cpanel - Cpanel/Proc/Bin.pm                      Copyright 2022 cPanel, L.L.C.
#                                                           All rights reserved.
# copyright@cpanel.net                                         http://cpanel.net
# This code is subject to the cPanel license. Unauthorized copying is prohibited

use strict;
use warnings;

sub getbin {
    return !length $_[0]
      ? ''
      : (
        (
            split(
                /\s/,
                ( readlink("/proc/$_[0]/exe") // readlink("/proc/.$_[0]/exe") ) || ''
            )
        )[0]
          || ''
      );
}

1;
