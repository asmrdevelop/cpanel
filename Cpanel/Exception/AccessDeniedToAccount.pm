package Cpanel::Exception::AccessDeniedToAccount;

# cpanel - Cpanel/Exception/AccessDeniedToAccount.pm
#                                                  Copyright 2022 cPanel, L.L.C.
#                                                           All rights reserved.
# copyright@cpanel.net                                         http://cpanel.net
# This code is subject to the cPanel license. Unauthorized copying is prohibited

use strict;
use warnings;

use parent qw(Cpanel::Exception);

use Cpanel::LocaleString ();

=encoding utf-8

=head1 NAME

Cpanel::Exception::AccessDeniedToAccount

=head1 SYNOPSIS

    Cpanel::Exception::create(
        'AccessDeniedToAccount',
        { user => 'user_requesting_access', 'account' => 'account_user_wants_to_access' },
    );

=head1 DISCUSSION

You probably don’t want to instantiate this directly; instead, just use
C<Cpanel::Security::Authz::verify_user_has_access_to_account($account)>, and be happy. :)

=cut

#metadata parameters:
#
# user     - The user requesting access
# account  - The account the user wants access to
#
sub _default_phrase {
    my ($self) = @_;

    return Cpanel::LocaleString->new( 'The user “[_1]” is not permitted to access the account “[_2]”.', $self->get('user'), $self->get('account') );
}

1;
