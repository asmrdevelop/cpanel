package Cpanel::CLI::DsyncCpsrvdClient;

# cpanel - Cpanel/CLI/DsyncCpsrvdClient.pm         Copyright 2022 cPanel, L.L.C.
#                                                           All rights reserved.
# copyright@cpanel.net                                         http://cpanel.net
# This code is subject to the cPanel license. Unauthorized copying is prohibited

use cPstrict;

=encoding utf-8

=head1 NAME

Cpanel::CLI::DsyncCpsrvdClient

=head1 DESCRIPTION

This module implements common logic for dsync-invoked scripts
(i.e., the scripts that dsync itself calls, not what humans usually run).

See subclasses for usage info.

=head1 SUBCLASS INTERFACE

Subclasses B<MUST> define methods/constants:

=over

=item * C<_SERVICE> - to give to L<Cpanel::CpXferClient>

=item * C<_create_url($account_name)>

=back

=cut

#----------------------------------------------------------------------

use parent qw( Cpanel::HelpfulScript );

use Cpanel::CpXferClient ();
use Cpanel::Interconnect ();

use constant _OPTIONS => ();

use constant _ACCEPT_UNNAMED => 1;

#----------------------------------------------------------------------

sub run ($self) {
    my ( $peer, $authn_user, $api_token, $account ) = $self->getopt_unnamed();

    my $cpxfer = Cpanel::CpXferClient->new(
        service    => $self->_SERVICE(),
        host       => $peer,
        user       => $authn_user,
        accesshash => $api_token,
    );

    $cpxfer->get_connection();

    $cpxfer->make_request( $self->_create_url($account) );

    () = $cpxfer->read_headers_from_socket();

    my $socket = $cpxfer->get_socket() or die 'no socket?';

    my $ic = Cpanel::Interconnect->new(
        'handles' => [
            $socket,
            [ \*STDIN, \*STDOUT ],
        ],
    );

    $ic->connect();

    return;
}

1;
