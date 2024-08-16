package Cpanel::CommandStream::Client::WebSocket::Base::APIToken;

# cpanel - Cpanel/CommandStream/Client/WebSocket/Base/APIToken.pm
#                                                  Copyright 2022 cPanel, L.L.C.
#                                                           All rights reserved.
# copyright@cpanel.net                                         http://cpanel.net
# This code is subject to the cPanel license. Unauthorized copying is prohibited

use cPstrict;

=encoding utf-8

=head1 NAME

Cpanel::CommandStream::Client::WebSocket::Base::APIToken

=head1 SYNOPSIS

See subclasses.

=head1 DESCRIPTION

This class provides API-token-authentication logic for
L<Cpanel::CommandStream::Client::WebSocket::Base>.

C<new()> for this class requires the C<api_token> parameter.

=cut

#--------------------------------------------------------------------------------

use parent 'Cpanel::CommandStream::Client::WebSocket::Base';

use constant _REQUIRED => (
    __PACKAGE__->SUPER::_REQUIRED(),
    'api_token',
);

#----------------------------------------------------------------------

sub _get_http_authn_header ($self) {
    return (
        'Authorization',
        "whm $self->{'username'}:$self->{'api_token'}",
    );
}

1;
