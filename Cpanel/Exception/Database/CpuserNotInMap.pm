package Cpanel::Exception::Database::CpuserNotInMap;

# cpanel - Cpanel/Exception/Database/CpuserNotInMap.pm
#                                                  Copyright 2022 cPanel, L.L.C.
#                                                           All rights reserved.
# copyright@cpanel.net                                         http://cpanel.net
# This code is subject to the cPanel license. Unauthorized copying is prohibited

use strict;
use warnings;

use parent qw( Cpanel::Exception );

use Cpanel::LocaleString ();

#Metadata parameters:
#   name - required
#
sub _default_phrase {
    my ($self) = @_;

    return Cpanel::LocaleString->new(
        'The [asis,cPanel] user “[_1]” does not exist in the database map.',
        $self->get('name'),
    );
}

1;
