package Cpanel::Exception::Database::TableInsertionFailed;

# cpanel - Cpanel/Exception/Database/TableInsertionFailed.pm
#                                                  Copyright 2022 cPanel, L.L.C.
#                                                           All rights reserved.
# copyright@cpanel.net                                         http://cpanel.net
# This code is subject to the cPanel license. Unauthorized copying is prohibited

use strict;
use warnings;

use parent qw( Cpanel::Exception );

use Cpanel::LocaleString ();

#Metadata propreties:
#   table
#   database
#   error
sub _default_phrase {
    my ($self) = @_;

    return Cpanel::LocaleString->new(
        'The system failed to insert into the table “[_1]” of the database “[_2]” because of an error: [_3]',
        @{ $self->{'_metadata'} }{qw(table database error)},
    );
}

1;
