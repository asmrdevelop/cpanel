package Cpanel::Server::Type::Role::UserSSL;

# cpanel - Cpanel/Server/Type/Role/UserSSL.pm      Copyright 2022 cPanel, L.L.C.
#                                                           All rights reserved.
# copyright@cpanel.net                                         http://cpanel.net
# This code is subject to the cPanel license. Unauthorized copying is prohibited

use strict;
use warnings;

=encoding utf-8

=head1 NAME

Cpanel::Server::Type::Role::UserSSL

=head1 SYNOPSIS

    if ( Cpanel::Server::Type::Role::UserSSL->is_enabled() ) { .. }

=head1 DESCRIPTION

This is a “pseudo-role” that abstracts over the configured state of
SSL. The role’s enabled-ness is equivalent to whether any of the roles
that would require SSL certificates for cPanel are enabled.

B<NOTE:> This role cannot be enabled or disabled directly,
and controls for such should not be exposed.

=cut

#----------------------------------------------------------------------

use parent 'Cpanel::Server::Type::Role';

use Cpanel::Server::Type::Role::CalendarContact ();
use Cpanel::Server::Type::Role::MailReceive     ();
use Cpanel::Server::Type::Role::WebDisk         ();
use Cpanel::Server::Type::Role::Webmail         ();
use Cpanel::Server::Type::Role::WebServer       ();

#----------------------------------------------------------------------

=head1 METHODS

=head2 I<CLASS>->_is_enabled()

If the any of the roles that need custom SSL certs are enabled this
returns true.

=cut

sub _is_enabled {
    return
         Cpanel::Server::Type::Role::CalendarContact->is_enabled()
      || Cpanel::Server::Type::Role::MailReceive->is_enabled()
      || Cpanel::Server::Type::Role::WebDisk->is_enabled()
      || Cpanel::Server::Type::Role::Webmail->is_enabled()
      || Cpanel::Server::Type::Role::WebServer->is_enabled();
}

#----------------------------------------------------------------------

sub _NAME {
    eval 'require Cpanel::LocaleString' or die;    ## no critic qw(ProhibitStringyEval)
    return 'Cpanel::LocaleString'->new('User SSL');
}

sub _DESCRIPTION {
    eval 'require Cpanel::LocaleString' or die;    ## no critic qw(ProhibitStringyEval)
    return 'Cpanel::LocaleString'->new('This role indicates whether any enabled cPanel & WHM services require SSL. (pseudo-role)');
}

1;
