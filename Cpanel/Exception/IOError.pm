package Cpanel::Exception::IOError;

# cpanel - Cpanel/Exception/IOError.pm             Copyright 2022 cPanel, L.L.C.
#                                                           All rights reserved.
# copyright@cpanel.net                                         http://cpanel.net
# This code is subject to the cPanel license. Unauthorized copying is prohibited

use strict;
use warnings;

#----------------------------------------------------------------------
#A base class. Do not instantiate directly.
#----------------------------------------------------------------------

use parent qw(Cpanel::Exception::ErrnoBase);

sub error {
    my ($self) = @_;

    return $self->{'_metadata'}{'error'};
}

sub _default_phrase { die 'Unimplemented' }

1;
