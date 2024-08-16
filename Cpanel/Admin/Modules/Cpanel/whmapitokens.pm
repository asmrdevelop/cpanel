package Cpanel::Admin::Modules::Cpanel::whmapitokens;

# cpanel - Cpanel/Admin/Modules/Cpanel/whmapitokens.pm
#                                                  Copyright 2022 cPanel, L.L.C.
#                                                           All rights Reserved.
# copyright@cpanel.net                                         http://cpanel.net
# This code is subject to the cPanel license. Unauthorized copying is prohibited

use strict;
use warnings;

=encoding utf-8

=head1 NAME

Cpanel::Admin::Modules::Cpanel::whmapitokens

=head1 DESCRIPTION

This module contains privilege-escalation logic for user code that needs
to access the WHM API tokens datastore.

=cut

use parent qw( Cpanel::Admin::Base );

use Cpanel::Security::Authn::APITokens::whostmgr ();

use constant _actions => (
    'READ',
);

# This has to be open because Pkgacct calls it,
# and we distribute an uncompiled scripts/pkgacct.
use constant _allowed_parents => '*';

=head2 READ()

A wrapper around L<Cpanel::Security::Authn::APITokens::whostmgr>’s C<read_tokens()>.

=cut

sub READ {
    my ($self) = @_;

    my $tokens_obj = Cpanel::Security::Authn::APITokens::whostmgr->new( { user => $self->get_caller_username() } );

    my $tokens_hr = $tokens_obj->read_tokens();
    $_ = $_->export() for values %$tokens_hr;

    return $tokens_hr;
}

1;
