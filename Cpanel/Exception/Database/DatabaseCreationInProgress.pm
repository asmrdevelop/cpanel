package Cpanel::Exception::Database::DatabaseCreationInProgress;

# cpanel - Cpanel/Exception/Database/DatabaseCreationInProgress.pm
#                                                  Copyright 2022 cPanel, L.L.C.
#                                                           All rights reserved.
# copyright@cpanel.net                                         http://cpanel.net
# This code is subject to the cPanel license. Unauthorized copying is prohibited

use strict;
use warnings;

use parent qw( Cpanel::Exception );

use Cpanel::LocaleString ();

#Metadata propreties:
#   database
#   error
sub _default_phrase {
    my ($self) = @_;

    return Cpanel::LocaleString->new(
        'The system cannot open the database “[_1]” because another process has created it but has not yet completed its initialization.',
        @{ $self->{'_metadata'} }{qw(database)},
    );
}

1;
