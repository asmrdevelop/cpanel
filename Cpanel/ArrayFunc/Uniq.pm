package Cpanel::ArrayFunc::Uniq;

# cpanel - Cpanel/ArrayFunc/Uniq.pm                Copyright 2022 cPanel, L.L.C.
#                                                           All rights reserved.
# copyright@cpanel.net                                         http://cpanel.net
# This code is subject to the cPanel license. Unauthorized copying is prohibited

use cPstrict;

sub uniq (@list) {

    # If List::Util is loaded we can use the
    # XS version which is faster.  We generally
    # avoid loading List::Util here because
    # its a large module to load in memory
    # for a very small function.
    if ( $INC{'List/Util.pm'} ) {
        no warnings 'redefine';
        *uniq = *List::Util::uniq;
        return List::Util::uniq(@list);
    }
    my %seen;
    return grep { !$seen{$_}++ } @list;
}

1;
