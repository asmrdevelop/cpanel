package Cpanel::Exception::ErrnoBase;

# cpanel - Cpanel/Exception/ErrnoBase.pm           Copyright 2022 cPanel, L.L.C.
#                                                           All rights reserved.
# copyright@cpanel.net                                         http://cpanel.net
# This code is subject to the cPanel license. Unauthorized copying is prohibited

use strict;
use warnings;

#----------------------------------------------------------------------
#A base class. Do not instantiate directly.
#----------------------------------------------------------------------

use parent qw(Cpanel::Exception);

use Cpanel::Errno     ();
use Cpanel::Exception ();

sub error_name {
    my ($self) = @_;

    return Cpanel::Errno::get_name_for_errno_number( 0 + $self->get('error') );
}

sub _default_phrase {
    die Cpanel::Exception::create( 'AbstractClass', [__PACKAGE__] );
}

1;
