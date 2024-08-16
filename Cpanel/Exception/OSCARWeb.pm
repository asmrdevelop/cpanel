package Cpanel::Exception::OSCARWeb;

# cpanel - Cpanel/Exception/OSCARWeb.pm            Copyright 2022 cPanel, L.L.C.
#                                                           All rights reserved.
# copyright@cpanel.net                                         http://cpanel.net
# This code is subject to the cPanel license. Unauthorized copying is prohibited

#----------------------------------------------------------------------
# This class represents errors specifically from dealing with the REST APIs
# that are used in Cpanel::OSCAR. Do not try to use it for errors that arise
# from the OSCAR protocol itself (which we shouldn’t need to do anymore).
#----------------------------------------------------------------------

use strict;
use warnings;

use parent qw( Cpanel::Exception );

use Cpanel::LocaleString ();

#opts:
#
#   service     - i.e., ICQ
#   response    - HTTP::Tiny::UA::Response instance
#
sub _default_phrase {
    my ($self) = @_;

    return Cpanel::LocaleString->new(
        'The system received an error from “[_1]” for the service “[_2]”: [_3]',
        $self->get('response')->url(),
        $self->get('service'),
        $self->get('response')->content(),
    );
}

1;
