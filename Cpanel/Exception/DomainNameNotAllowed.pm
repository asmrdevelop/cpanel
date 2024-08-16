package Cpanel::Exception::DomainNameNotAllowed;

# cpanel - Cpanel/Exception/DomainNameNotAllowed.pm
#                                                  Copyright 2022 cPanel, L.L.C.
#                                                           All rights reserved.
# copyright@cpanel.net                                         http://cpanel.net
# This code is subject to the cPanel license. Unauthorized copying is prohibited

use strict;
use warnings;

use parent qw( Cpanel::Exception );

use Cpanel::LocaleString ();

#Parameters:
#   - given: the text that we are saying is not permitted
#   - why: (optional) why it's not
#
sub _default_phrase {
    my ($self) = @_;

    my ( $given, $why ) = map { $self->get($_) } qw(given why);

    if ( length $why ) {
        return Cpanel::LocaleString->new(
            'The system cannot accept “[_1]” as a domain name ([_2]).',
            $given,
            $why,
        );
    }

    return Cpanel::LocaleString->new(
        'The system cannot accept “[_1]” as a domain name.',
        $given,
    );
}

1;
