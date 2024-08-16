package Cpanel::Exim::Options;

# cpanel - Cpanel/Exim/Options.pm                  Copyright 2022 cPanel, L.L.C.
#                                                           All rights reserved.
# copyright@cpanel.net                                         http://cpanel.net
# This code is subject to the cPanel license. Unauthorized copying is prohibited

my $exim_config_file;

sub fetch_exim_options {
    return ( '-C', $exim_config_file ) if $exim_config_file;
    return ()                          if defined $exim_config_file;

    if ( -e '/etc/exim_outgoing.conf' ) {
        $exim_config_file = '/etc/exim_outgoing.conf';
        return ( '-C', '/etc/exim_outgoing.conf' );
    }
    $exim_config_file = '';
    return ();
}

1;
