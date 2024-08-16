package Cpanel::Exception::InvalidCharacters;

# cpanel - Cpanel/Exception/InvalidCharacters.pm   Copyright 2022 cPanel, L.L.C.
#                                                           All rights reserved.
# copyright@cpanel.net                                         http://cpanel.net
# This code is subject to the cPanel license. Unauthorized copying is prohibited

use strict;
use warnings;

use parent qw( Cpanel::Exception::InvalidParameter );

use Cpanel::LocaleString ();

sub _default_phrase {
    my ($self) = @_;

    my $invalid_ar = $self->{'_metadata'}{'invalid_characters'};

    if ( @$invalid_ar == 1 ) {
        return Cpanel::LocaleString->new(
            'This value may not contain the character “[_1]”.',
            $invalid_ar->[0],
        );
    }

    return Cpanel::LocaleString->new(
        'This value may not contain any of the following [quant,_1,character,characters]: [join, ,_2]',
        scalar(@$invalid_ar),
        $invalid_ar,
    );
}

sub get_invalid_characters {
    my ($self) = @_;

    return [ @{ $self->{'_metadata'}{'invalid_characters'} } ];
}

1;
