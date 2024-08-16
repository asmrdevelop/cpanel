package Cpanel::Admin::Modules::Cpanel::postgresql;

# cpanel - Cpanel/Admin/Modules/Cpanel/postgresql.pm
#                                                  Copyright 2022 cPanel, L.L.C.
#                                                           All rights reserved.
# copyright@cpanel.net                                         http://cpanel.net
# This code is subject to the cPanel license. Unauthorized copying is prohibited

use strict;
use warnings;

=encoding utf-8

=head1 NAME

Cpanel::Admin::Modules::Cpanel::postgresql - PostgreSQL admin functions

=head1 DESCRIPTION

This module subclasses L<Cpanel::Admin::Base::DB>. Additional
functionality is described below:

=cut

use parent qw( Cpanel::Admin::Base::DB );

use Cpanel::PasswdStrength::Check ();
use Cpanel::PostgresAdmin         ();

sub _actions {
    my ($self) = @_;

    return (
        $self->SUPER::_actions(),
        'RENAME_USER_NO_PASSWORD',
        'GRANT_ALL_PRIVILEGES_ON_DATABASE_TO_USER',
        'REVOKE_ALL_PRIVILEGES_ON_DATABASE_FROM_USER',
    );
}

sub _engine {
    return 'postgresql';
}

sub _password_app {
    return 'postgres';
}

sub _admin {
    my ($self) = @_;

    #TODO: Catch errors from this.
    return (
        $self->{'_admin'} ||= Cpanel::PostgresAdmin->new(
            {
                cpuser           => $self->get_caller_username(),
                ERRORS_TO_STDOUT => 0,
            }
        )
    );
}

=head1 FUNCTIONS

=head2 RENAME_USER( $OLDNAME => $NEWNAME, $PASSWORD )

Renames a user. The password is required because PostgreSQL’s password
hashing includes the username. See C<RENAME_USER_NO_PASSWORD()> if you
don’t have the user’s password.

Returns nothing.

=cut

sub RENAME_USER {
    my ( $self, $olduser, $newuser, $password ) = @_;

    $self->_verify_that_password_is_there($password);

    $self->whitelist_exception('Cpanel::Exception::PasswordIsTooWeak');
    Cpanel::PasswdStrength::Check::verify_or_die( app => $self->_password_app(), pw => $password );

    $self->SUPER::RENAME_USER( $olduser, $newuser );

    $self->_admin()->set_password( $newuser, $password );

    #Return empty in PostgreSQL.
    return;
}

=head2 RENAME_USER_NO_PASSWORD( $OLDNAME => $NEWNAME )

Renames a user without its password, which will leave the PostgreSQL
account inaccessible. Prefer C<RENAME_USER()> if it’s an option.

Returns nothing.

=cut

sub RENAME_USER_NO_PASSWORD {
    my $self = shift;

    $self->SUPER::RENAME_USER(@_);

    #Return empty in PostgreSQL.
    return;
}

=head2 RENAME_DATABASE( $OLDNAME => $NEWNAME )

Renames a database.

Returns nothing.

=cut

sub RENAME_DATABASE {
    my ( $self, $oldname, $newname ) = @_;

    $self->SUPER::RENAME_DATABASE( $oldname, $newname );

    #Return empty in PostgreSQL.
    return;
}

=head2 GRANT_ALL_PRIVILEGES_ON_DATABASE_TO_USER( $DBNAME => $DBUSERNAME )

Returns nothing.

=cut

sub GRANT_ALL_PRIVILEGES_ON_DATABASE_TO_USER {
    my ( $self, $dbname, $dbuser ) = @_;

    $self->_admin()->grant_db_to_dbuser( $dbname, $dbuser );

    return;
}

=head2 REVOKE_ALL_PRIVILEGES_ON_DATABASE_FROM_USER( $DBNAME => $DBUSERNAME )

Returns nothing.

=cut

sub REVOKE_ALL_PRIVILEGES_ON_DATABASE_FROM_USER {
    my ( $self, $dbname, $dbuser ) = @_;

    $self->_admin()->revoke_db_from_dbuser( $dbname, $dbuser );

    return;
}

1;

#----------------------------------------------------------------------

=head1 SEE ALSO

F<bin/admin/Cpanel/postgres.pl> contains the early PostgreSQL
admin logic. It would be nice to move that functionality to be callable
from this module.
