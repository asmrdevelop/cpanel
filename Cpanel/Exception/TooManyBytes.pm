package Cpanel::Exception::TooManyBytes;

# cpanel - Cpanel/Exception/TooManyBytes.pm        Copyright 2022 cPanel, L.L.C.
#                                                           All rights reserved.
# copyright@cpanel.net                                         http://cpanel.net
# This code is subject to the cPanel license. Unauthorized copying is prohibited

use strict;
use warnings;

use parent qw( Cpanel::Exception );

use Cpanel::LocaleString ();

#Named arguments:
#   key (optional)
#   value
#   maxlength
#
sub _default_phrase {
    my ($self) = @_;

    if ( $self->get('key') ) {
        return Cpanel::LocaleString->new(
            'The value “[_1]” for “[_2]” is too long by [quant,_3,byte,bytes]. The maximum allowed length is [quant,_4,byte,bytes].',
            $self->get('value'),
            $self->get('key'),
            $self->excess(),
            $self->{'_metadata'}{'maxlength'},
        );

    }
    return Cpanel::LocaleString->new(
        'The “[_1]” value exceeds the maximum length by [quant,_2,byte,bytes]. The maximum allowed length is [quant,_3,byte,bytes].',
        $self->get('value'),
        $self->excess(),
        $self->{'_metadata'}{'maxlength'},
    );
}

sub excess {
    my ($self) = @_;

    return length( $self->{'_metadata'}{'value'} ) - $self->{'_metadata'}{'maxlength'};
}

1;
