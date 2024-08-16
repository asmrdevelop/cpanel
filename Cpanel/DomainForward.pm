package Cpanel::DomainForward;

# cpanel - Cpanel/DomainForward.pm                 Copyright 2022 cPanel, L.L.C.
#                                                           All rights reserved.
# copyright@cpanel.net                                         http://cpanel.net
# This code is subject to the cPanel license. Unauthorized copying is prohibited

use Cpanel::Validate::IP ();

sub get_domain_fwd_ip {
    if ( -f '/var/cpanel/domainfwdip' ) {
        open( my $dfwdip_fh, '<', '/var/cpanel/domainfwdip' );
        chomp( my $dfwdip = <$dfwdip_fh> );
        close($dfwdip_fh);
        return $dfwdip if Cpanel::Validate::IP::is_valid_ip($dfwdip);
    }
    return;
}

sub clear_ip {
    unlink '/var/cpanel/domainfwdip';
}

sub set_ip {
    my $ip = shift;
    chomp($ip);
    return 0 if !Cpanel::Validate::IP::is_valid_ip($ip);
    if ( open( my $fh, '>', '/var/cpanel/domainfwdip' ) ) {
        print {$fh} $ip;
        close($fh);
        return 1;
    }
    return 0;
}

1;
