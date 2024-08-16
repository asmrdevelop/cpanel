package Cpanel::SSH::Port;

# cpanel - Cpanel/SSH/Port.pm                      Copyright 2022 cPanel, L.L.C.
#                                                           All rights reserved.
# copyright@cpanel.net                                         http://cpanel.net
# This code is subject to the cPanel license. Unauthorized copying is prohibited

use strict;

our $DEFAULT_SSH_PORT = 22;

sub getport {
    my @SSHDC = qw( /etc/ssh/sshd_config /usr/local/etc/ssh/sshd_config  );
    if ( $> != 0 && !$ENV{'PORTSADMIN'} ) {
        require Cpanel::AdminBin;
        return Cpanel::AdminBin::adminfetch( 'ports', \@SSHDC, 'GETSSHPORT', 'scalar', '0' );
    }
    my $port = $DEFAULT_SSH_PORT;
  SSH_PORT_FL:
    foreach my $sshf (@SSHDC) {
        if ( open my $sshcf_fh, '<', $sshf ) {
            while ( my $line = readline($sshcf_fh) ) {
                if ( $line =~ m/^\s*Port\s(\d+)/ ) {
                    $port = $1;
                    close $sshcf_fh;
                    last SSH_PORT_FL;
                }
            }
            close $sshcf_fh;
        }
    }
    return $port;
}

1;
