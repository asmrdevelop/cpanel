package Cpanel::Exception::Transfers::SessionAborted;

# cpanel - Cpanel/Exception/Transfers/SessionAborted.pm
#                                                  Copyright 2022 cPanel, L.L.C.
#                                                           All rights reserved.
# copyright@cpanel.net                                         http://cpanel.net
# This code is subject to the cPanel license. Unauthorized copying is prohibited

use strict;
use warnings;

use parent               qw( Cpanel::Exception );
use Cpanel::LocaleString ();

#Metadata propreties:
#   sessionid
sub _default_phrase {
    my ($self) = @_;

    return Cpanel::LocaleString->new(
        'The system failed to start the session with ID “[_1]” because that session has been aborted.',
        @{ $self->{'_metadata'} }{qw(sessionid)},
    );
}

1;
