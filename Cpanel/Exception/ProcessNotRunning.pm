package Cpanel::Exception::ProcessNotRunning;

# cpanel - Cpanel/Exception/ProcessNotRunning.pm   Copyright 2022 cPanel, L.L.C.
#                                                           All rights reserved.
# copyright@cpanel.net                                         http://cpanel.net
# This code is subject to the cPanel license. Unauthorized copying is prohibited

use strict;
use warnings;

use parent qw( Cpanel::Exception );

use Cpanel::LocaleString ();

#Parameters:
#   pid
sub _default_phrase {
    my ($self) = @_;

    return Cpanel::LocaleString->new(
        'No process with ID “[_1]” is running.',
        $self->{'_metadata'}{'pid'},
    );
}

1;
