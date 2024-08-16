package Cpanel::Server::Type::Role::CloudController;

# cpanel - Cpanel/Server/Type/Role/CloudController.pm
#                                                  Copyright 2022 cPanel, L.L.C.
#                                                           All rights reserved.
# copyright@cpanel.net                                         http://cpanel.net
# This code is subject to the cPanel license. Unauthorized copying is prohibited

use cPstrict;

=encoding utf-8

=head1 NAME

Cpanel::Server::Type::Role::CloudController

=head1 SYNOPSIS

    if ( Cpanel::Server::Type::Role::CloudController->is_enabled() ) { .. }

=head1 DESCRIPTION

This is a “pseudo-role” that abstracts over whether the local cP server
controls a cPanel Cloud instance.

B<NOTE:> This role cannot be enabled or disabled directly,
and controls for such should not be exposed.

=cut

#----------------------------------------------------------------------

use parent 'Cpanel::Server::Type::Role';

use Cpanel::License::Cloud ();

#----------------------------------------------------------------------

=head1 METHODS

=head2 I<CLASS>->_is_enabled()

If the any of the roles that need custom SSL certs are enabled this
returns true.

=cut

sub _is_enabled {
    return Cpanel::License::Cloud::is_on();
}

#----------------------------------------------------------------------

sub _NAME {
    eval 'require Cpanel::LocaleString' or die;    ## no critic qw(ProhibitStringyEval)
    return 'Cpanel::LocaleString'->new('High Availability');
}

sub _DESCRIPTION {
    eval 'require Cpanel::LocaleString' or die;    ## no critic qw(ProhibitStringyEval)
    return 'Cpanel::LocaleString'->new('This role indicates whether this is a high-availability [asis,cPanel amp() WHM] server.');
}

1;
