package Cpanel::Chkservd;

# cpanel - Cpanel/Chkservd.pm                      Copyright 2022 cPanel, L.L.C.
#                                                           All rights reserved.
# copyright@cpanel.net                                         http://cpanel.net
# This code is subject to the cPanel license. Unauthorized copying is prohibited

use strict;

# use warnings;
use Cpanel::Exim::Ports ();

## DO NOT WRAP Cpanel::API::Chkservd due to memory concerns

our $VERSION = '0.6';

sub Chkservd_geteximport     { print geteximport(); }
sub Chkservd_geteximport_ssl { print geteximport_ssl(); }

*geteximport_ssl = \&Cpanel::Exim::Ports::get_secure_ports;

sub geteximport {
    my ($all_ports) = @_;

    my @ports = Cpanel::Exim::Ports::get_insecure_ports();

    # The API1 version of this function neglected to include port 25 as one
    # of exim's ports if exim were running on another port as well as 25.  This
    # was changed in UAPI, but we need to keep the return of this interface the
    # same.
    if ( scalar @ports > 1 && ( grep { $_ == 25 } @ports ) ) {
        @ports = grep { $_ != 25 } @ports;
    }

    return $all_ports ? join( ',', @ports ) : $ports[0];
}

1;

__END__
