package Cpanel::FHUtils::Blocking;

# cpanel - Cpanel/FHUtils/Blocking.pm              Copyright 2022 cPanel, L.L.C.
#                                                           All rights reserved.
# copyright@cpanel.net                                         http://cpanel.net
# This code is subject to the cPanel license. Unauthorized copying is prohibited

use strict;
use warnings;

use Cpanel::Fcntl::Constants ();
use Cpanel::Autodie          qw(fcntl);

# $_[0] = $fh
sub set_non_blocking {
    return Cpanel::Autodie::fcntl( $_[0], $Cpanel::Fcntl::Constants::F_SETFL, _get_fl_flags( $_[0] ) | $Cpanel::Fcntl::Constants::O_NONBLOCK ) && 1;
}

# $_[0] = $fh
sub set_blocking {
    return Cpanel::Autodie::fcntl( $_[0], $Cpanel::Fcntl::Constants::F_SETFL, _get_fl_flags( $_[0] ) & ~$Cpanel::Fcntl::Constants::O_NONBLOCK ) && 1;
}

# $_[0] = $fh
sub is_set_to_block {
    return !( _get_fl_flags( $_[0] ) & $Cpanel::Fcntl::Constants::O_NONBLOCK ) ? 1 : 0;
}

# $_[0] = $fh
sub _get_fl_flags {

    # force numeric context
    return int Cpanel::Autodie::fcntl( $_[0], $Cpanel::Fcntl::Constants::F_GETFL, 0 );
}

1;
