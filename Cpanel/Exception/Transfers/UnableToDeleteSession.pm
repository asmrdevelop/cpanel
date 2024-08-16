package Cpanel::Exception::Transfers::UnableToDeleteSession;

# cpanel - Cpanel/Exception/Transfers/UnableToDeleteSession.pm
#                                                  Copyright 2022 cPanel, L.L.C.
#                                                           All rights reserved.
# copyright@cpanel.net                                         http://cpanel.net
# This code is subject to the cPanel license. Unauthorized copying is prohibited

use strict;
use warnings;

use parent qw( Cpanel::Exception );

use Cpanel::LocaleString ();

#Metadata propreties:
#   sessionid
#   error
sub _default_phrase {
    my ($self) = @_;

    return Cpanel::LocaleString->new(
        'The system failed to delete the session with ID “[_1]” due to an error: [_2]',
        @{ $self->{'_metadata'} }{qw(sessionid error)},
    );
}

1;
