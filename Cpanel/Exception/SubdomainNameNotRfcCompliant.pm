package Cpanel::Exception::SubdomainNameNotRfcCompliant;

# cpanel - Cpanel/Exception/SubdomainNameNotRfcCompliant.pm
#                                                  Copyright 2022 cPanel, L.L.C.
#                                                           All rights reserved.
# copyright@cpanel.net                                         http://cpanel.net
# This code is subject to the cPanel license. Unauthorized copying is prohibited

use strict;
use warnings;

use parent qw( Cpanel::Exception );

use Cpanel::LocaleString ();

sub _default_phrase {
    my ( $class, $mt_args_ar ) = @_;

    return Cpanel::LocaleString->new(
        '“[_1]” is not a valid subdomain name per [asis,RFC] 1035.',
        $mt_args_ar->[0],
    );
}

1;
