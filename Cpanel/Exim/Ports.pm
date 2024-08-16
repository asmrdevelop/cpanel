package Cpanel::Exim::Ports;

# cpanel - Cpanel/Exim/Ports.pm                    Copyright 2022 cPanel, L.L.C.
#                                                           All rights reserved.
# copyright@cpanel.net                                         http://cpanel.net
# This code is subject to the cPanel license. Unauthorized copying is prohibited

use strict;
use warnings;

use Cpanel::Chkservd::Config ();
use Cpanel::Debug            ();

my $default_exim_ssl_port = 465;
my $default_exim_port     = 25;

sub get_insecure_ports {
    my @ports = sort { $a <=> $b } ( split( m{,}, _get_exim_ports_str() ) );

    return @ports;
}

sub get_secure_ports {
    return ($default_exim_ssl_port);
}

sub _get_exim_ports_str {
    if ( opendir( my $dh, $Cpanel::Chkservd::Config::chkservd_dir ) ) {
        my @drivers = readdir($dh);
        my ( $found_default_port, $other_ports );
        foreach my $service (@drivers) {
            if ( $service eq 'exim' ) {
                $found_default_port = 1;
            }
            elsif ( index( $service, 'exim-' ) == 0 ) {
                my $trailer = ( split( m{-}, $service ) )[1];
                if ( $trailer !~ tr{0-9,}{}c ) {
                    $other_ports = $trailer;
                }
            }
            if ( $found_default_port && $other_ports ) {
                return "$default_exim_port," . $other_ports;
            }
        }

        if ($other_ports) {
            return $other_ports;
        }
    }
    elsif ( !$ENV{'CPANEL_BASE_INSTALL'} ) {

        # Warn in every case but during install (as it won't actually exist then and that's fine)
        Cpanel::Debug::log_warn("Failed to open “$Cpanel::Chkservd::Config::chkservd_dir”: $!");
    }
    return $default_exim_port;
}

1;
