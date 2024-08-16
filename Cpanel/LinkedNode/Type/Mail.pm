package Cpanel::LinkedNode::Type::Mail;

# cpanel - Cpanel/LinkedNode/Type/Mail.pm          Copyright 2022 cPanel, L.L.C.
#                                                           All rights reserved.
# copyright@cpanel.net                                         http://cpanel.net
# This code is subject to the cPanel license. Unauthorized copying is prohibited

use strict;
use warnings;

=encoding utf-8

=head1 NAME

Cpanel::LinkedNode::Type::Mail - Concrete node type implementation for a mail node

=head1 DESCRIPTION

This class is a concrete implementation of the abstract L<Cpanel::LinkedNode::Type>
parent class for a mail node.

See L<Cpanel::LinkedNode::Type> for implementation details.

=cut

use parent qw(Cpanel::LinkedNode::Type);

our $_TYPE_NAME = "Mail";

our @_REQUIRED_SERVICES = qw(
  cpdavd
  exim
  imap
  lmtp
  pop
);

sub _get_required_services {
    return @_REQUIRED_SERVICES;
}

sub _get_type_name {
    return $_TYPE_NAME;
}

1;
