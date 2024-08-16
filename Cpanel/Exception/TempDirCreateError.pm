package Cpanel::Exception::TempDirCreateError;

# cpanel - Cpanel/Exception/TempDirCreateError.pm  Copyright 2022 cPanel, L.L.C.
#                                                           All rights reserved.
# copyright@cpanel.net                                         http://cpanel.net
# This code is subject to the cPanel license. Unauthorized copying is prohibited

use strict;
use warnings;

use parent qw( Cpanel::Exception::TempCreateError );

use Cpanel::LocaleString ();

sub _default_phrase {
    my ($self) = @_;

    return Cpanel::LocaleString->new(
        'The system failed to create the temporary directory “[_1]” because of an error: [_2]',
        @{ $self->{'_metadata'} }{qw(path error)},
    );
}

1;
