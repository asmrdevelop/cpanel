package Cpanel::Server::Type::Role::PostgresClient;

# cpanel - Cpanel/Server/Type/Role/PostgresClient.pm
#                                                  Copyright 2022 cPanel, L.L.C.
#                                                           All rights reserved.
# copyright@cpanel.net                                         http://cpanel.net
# This code is subject to the cPanel license. Unauthorized copying is prohibited

use strict;
use warnings;

=encoding utf-8

=head1 NAME

Cpanel::Server::Type::Role::PostgresClient

=head1 SYNOPSIS

    if ( Cpanel::Server::Type::Role::PostgresClient->is_enabled() ) { .. }

=head1 DESCRIPTION

This role serves the same abstracted purpose for PostgreSQL that
L<Cpanel::Server::Type::Role::MySQLClient> serves for MySQL/MariaDB.

=cut

#----------------------------------------------------------------------

use parent 'Cpanel::Server::Type::Role';

use Cpanel::Server::Type::Role::Postgres ();

#----------------------------------------------------------------------

=head1 METHODS

=head2 I<CLASS>->is_enabled()

Similar to L<Cpanel::Server::Type::Role::MySQLClient>’s method of the
same name.

Note that remote PostgreSQL is not supported as of v76, so
this check is equivalent to whether the PostgreSQL service is enabled.

=cut

sub is_enabled {
    return Cpanel::Server::Type::Role::Postgres->is_enabled();
}

#----------------------------------------------------------------------

sub _NAME {
    eval 'require Cpanel::LocaleString' or die;    ## no critic qw(ProhibitStringyEval)
    return Cpanel::LocaleString->new('PostgreSQL Client');
}

sub _DESCRIPTION {
    eval 'require Cpanel::LocaleString' or die;    ## no critic qw(ProhibitStringyEval)
    return Cpanel::LocaleString->new('PostgreSQL client functionality. (pseudo-role)');
}

1;
