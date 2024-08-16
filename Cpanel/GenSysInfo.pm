package Cpanel::GenSysInfo;

# cpanel - Cpanel/GenSysInfo.pm                    Copyright 2022 cPanel, L.L.C.
#                                                           All rights reserved.
# copyright@cpanel.net                                         http://cpanel.net
# This code is subject to the cPanel license. Unauthorized copying is prohibited

###############################################################################
#
#
# 8888888b.                   d8b 888                                         888    888      d8b
# 888  "Y88b                  88P 888                                         888    888      Y8P
# 888    888                  8P  888                                         888    888
# 888    888  .d88b.  88888b. "   888888      888  888 .d8888b   .d88b.       888888 88888b.  888 .d8888b
# 888    888 d88""88b 888 "88b    888         888  888 88K      d8P  Y8b      888    888 "88b 888 88K
# 888    888 888  888 888  888    888         888  888 "Y8888b. 88888888      888    888  888 888 "Y8888b.
# 888  .d88P Y88..88P 888  888    Y88b.       Y88b 888      X88 Y8b.          Y88b.  888  888 888      X88
# 8888888P"   "Y88P"  888  888     "Y888       "Y88888  88888P'  "Y8888        "Y888 888  888 888  88888P'
#
# This module is here for external legacy code which might still need to call this. Please use Cpanel::OS instead.
#
###############################################################################

use strict;
use warnings;

use Cpanel::OS    ();
use Cpanel::Debug ();

sub run {
    _log_deprecated();
    return {
        dist     => Cpanel::OS::distro(),    ## no critic(Cpanel::CpanelOS)
        rpm_dist => Cpanel::OS::distro(),    ## no critic(Cpanel::CpanelOS)

        arch     => Cpanel::OS::arch(),
        rpm_arch => Cpanel::OS::arch(),

        release => sprintf( "%s.%s", Cpanel::OS::major(), Cpanel::OS::minor() ),    ## no critic(Cpanel::CpanelOS)

        dist_ver     => Cpanel::OS::major(),                                        ## no critic(Cpanel::CpanelOS)
        rpm_dist_ver => Cpanel::OS::major(),                                        ## no critic(Cpanel::CpanelOS)
    };
}

sub get_rpm_distro {
    _log_deprecated();
    return Cpanel::OS::distro();                                                    ## no critic(Cpanel::CpanelOS)
}

sub get_rpm_arch {
    _log_deprecated();
    return Cpanel::OS::arch();
}

sub get_rpm_distro_version {
    _log_deprecated();
    return Cpanel::OS::major();                                                     ## no critic(Cpanel::CpanelOS)
}

sub _log_deprecated {
    Cpanel::Debug::log_deprecated("Cpanel::GenSysInfo has been replaced by Cpanel::OS. Please change your code to use Cpanel::OS for v100 and above.");
    return;
}

1;
