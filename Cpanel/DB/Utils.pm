package Cpanel::DB::Utils;

# cpanel - Cpanel/DB/Utils.pm                      Copyright 2022 cPanel, L.L.C.
#                                                           All rights reserved.
# copyright@cpanel.net                                         http://cpanel.net
# This code is subject to the cPanel license. Unauthorized copying is prohibited

use strict;

#Transfers and some older accounts might have underscores or periods
#in the cpusername. For historical reasons, the account's "main" database
#username always strips these characters out.
#
#In 99% of cases, this function is a no-op.
#
sub username_to_dbowner {
    my ($username) = @_;

    $username =~ tr<_.><>d if defined $username;

    return $username;
}

1;
