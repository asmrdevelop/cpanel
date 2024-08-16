package Cpanel::Exception::HTTP::Network;

# cpanel - Cpanel/Exception/HTTP/Network.pm        Copyright 2022 cPanel, L.L.C.
#                                                           All rights reserved.
# copyright@cpanel.net                                         http://cpanel.net
# This code is subject to the cPanel license. Unauthorized copying is prohibited

use strict;
use warnings;

use parent qw(
  Cpanel::Exception::Base::HasUrl
  Cpanel::Exception::HTTP
);

use Cpanel::LocaleString ();

#metadata parameters:
#   error
#   method
#   url
#
sub _default_phrase {
    my ($self) = @_;

    return Cpanel::LocaleString->new(
        'The system failed to send an [output,abbr,HTTP,Hypertext Transfer Protocol] “[_1]” request to “[_2]” because of an error: [_3]',
        $self->get('method'),
        $self->get_url_without_password(),
        $self->get('error'),
    );
}

1;
