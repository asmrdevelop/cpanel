package Cpanel::CommandStream::Client::WebSocket::Base::Password;

# cpanel - Cpanel/CommandStream/Client/WebSocket/Base/Password.pm
#                                                  Copyright 2022 cPanel, L.L.C.
#                                                           All rights reserved.
# copyright@cpanel.net                                         http://cpanel.net
# This code is subject to the cPanel license. Unauthorized copying is prohibited

use cPstrict;

=encoding utf-8

=head1 NAME

Cpanel::CommandStream::Client::WebSocket::Base::Password

=head1 SYNOPSIS

See subclasses.

=head1 DESCRIPTION

This class provides password-authentication logic for
L<Cpanel::CommandStream::Client::WebSocket::Base>.

C<new()> for this class requires the C<password> parameter.

=cut

#--------------------------------------------------------------------------------

use parent 'Cpanel::CommandStream::Client::WebSocket::Base';

use Cpanel::HTTP::BasicAuthn ();

use constant _REQUIRED => (
    __PACKAGE__->SUPER::_REQUIRED(),
    'password',
);

#----------------------------------------------------------------------

sub _get_http_authn_header ($self) {
    return Cpanel::HTTP::BasicAuthn::encode(
        @{$self}{ 'username', 'password' },
    );
}

1;
