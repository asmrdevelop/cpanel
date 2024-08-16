package Cpanel::ArrayFunc::Map;

# cpanel - Cpanel/ArrayFunc/Map.pm                 Copyright 2022 cPanel, L.L.C.
#                                                           All rights reserved.
# copyright@cpanel.net                                         http://cpanel.net
# This code is subject to the cPanel license. Unauthorized copying is prohibited

use cPstrict;

#SIMILAR TO (AND ADAPTED FROM) List::Util::first,
#BUT GIVES THE RESULT, NOT THE LIST ITEM.

# Notice that in mapfirst() below we call the code reference by passing it
# $_ ; this is different from the implementation of first() above, where we
# pass nothing, and rely on the code reference subroutine to inspect $_
# directly. That conforms to the implementation of List::Util::first() on
# which this module's first() is based, and also its official documentation.
# There is also a performance win for large arrays.
#
# A case could therefore be made for consistency to modify mapfirst() to
# likewise not pass $_ ; however, we know of at least one instance in Cpanel
# code that relies on the current mapfirst() implementation, so we will let
# it be. But users and potential users of these two functions would do well
# to heed their distinctions.  (Reference: case 45964)

sub mapfirst ( $code, @list ) {

    foreach (@list) {
        my $val = &{$code}($_);    # see comment above
        return $val if $val;
    }

    return undef;
}

1;
