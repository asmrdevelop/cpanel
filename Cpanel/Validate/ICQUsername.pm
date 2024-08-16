package Cpanel::Validate::ICQUsername;

# cpanel - Cpanel/Validate/ICQUsername.pm          Copyright 2022 cPanel, L.L.C.
#                                                           All rights reserved.
# copyright@cpanel.net                                         http://cpanel.net
# This code is subject to the cPanel license. Unauthorized copying is prohibited

use strict;
use warnings;

sub is_valid {
    my ($name) = @_;

    #Only allows UINs here. ICQ does allow logons with (now dead) AIM usernames and
    #maybe email addresses.
    my $valid = qr'\A\d+\z';

    return defined $name && $name =~ $valid;
}

1;
