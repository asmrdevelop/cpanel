package Cpanel::Exception::DomainNameNotRfcCompliant;

# cpanel - Cpanel/Exception/DomainNameNotRfcCompliant.pm
#                                                  Copyright 2022 cPanel, L.L.C.
#                                                           All rights reserved.
# copyright@cpanel.net                                         http://cpanel.net
# This code is subject to the cPanel license. Unauthorized copying is prohibited

use strict;
use warnings;

use parent qw( Cpanel::Exception );

use Cpanel::LocaleString ();

my $RFC_1035_URL = 'http://tools.ietf.org/html/rfc1035';

#Parameters:
#   - given: the text that we are saying is not a valid domain name
#   - why: (optional) why it's not
#
sub _default_phrase {
    my ($self) = @_;

    my ( $given, $why ) = map { $self->get($_) } qw(given why);

    if ( length $why ) {
        return Cpanel::LocaleString->new(
            '“[_1]” is not a valid domain name per [output,url,_2,RFC 1035] ([_3]).',
            $given,
            $RFC_1035_URL,
            $why,
        );
    }

    return Cpanel::LocaleString->new(
        '“[_1]” is not a valid domain name per [output,url,_2,RFC 1035].',
        $given,
        $RFC_1035_URL,
    );
}

1;
