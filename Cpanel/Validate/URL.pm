package Cpanel::Validate::URL;

# cpanel - Cpanel/Validate/URL.pm                  Copyright 2022 cPanel, L.L.C.
#                                                           All rights reserved.
# copyright@cpanel.net                                         http://cpanel.net
# This code is subject to the cPanel license. Unauthorized copying is prohibited

use warnings;
use strict;

sub is_valid_url {
    my ($url) = @_;

    # From
    # http://stackoverflow.com/questions/1547899/which-characters-make-a-url-invalid#1547940

    if ( $url =~ m{\A[A-Za-z0-9\-\._~:/\?#\[\]@!\$&'\(\)*+,;=]+\z} ) {
        return 1;
    }

    return 0;
}

sub is_valid_url_but_novars {
    my ($url) = @_;

    return 0 if !is_valid_url($url);
    return 0 if $url =~ m/\$/;         # looking for replacevars in baseurl/mirrorlist stuff

    return 1;
}

1;
