package Cpanel::LinkedNode::User::Configuration;

# cpanel - Cpanel/LinkedNode/User/Configuration.pm Copyright 2022 cPanel, L.L.C.
#                                                           All rights reserved.
# copyright@cpanel.net                                         http://cpanel.net
# This code is subject to the cPanel license. Unauthorized copying is prohibited

use strict;
use warnings;

=encoding utf-8

=head1 NAME

Cpanel::LinkedNode::User::Configuration

=head1 DESCRIPTION

This module represents a linked node configuration as
an unprivileged user sees it.

NB: There currently exists no equivalent module for the privileged-user
linked node configuration view, but it’s the hash reference that
functions in L<Cpanel::LinkedNode> like C<get_linked_server_node()> return.

=head1 CONSTRUCTOR

=head2 I<CLASS>->new( %OPTS )

%OPTS should contain C<hostname> and C<allow_bad_tls>.

=head1 ACCESSORS

This class exposes the following accessors:

=over

=item * C<hostname()> - The hostname to use to contact the linked node.

=item * C<allow_bad_tls()> - Whether to proceed with TLS connections that
fail verification (e.g., from an expired certificate, domain mismatch, etc.).

=back

=cut

use Class::XSAccessor (
    constructor => 'new',
    getters     => [
        'hostname',
        'allow_bad_tls',
    ],
);

1;
