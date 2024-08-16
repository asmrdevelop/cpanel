package Cpanel::SQLite::RootData;

# cpanel - Cpanel/SQLite/RootData.pm               Copyright 2023 cPanel, L.L.C.
#                                                           All rights reserved.
# copyright@cpanel.net                                         http://cpanel.net
# This code is subject to the cPanel license. Unauthorized copying is prohibited

use cPstrict;

use Cpanel::Exception ();

use parent qw{ Cpanel::SQLite::MojoBase };

=encoding utf8

=head1 NAME

Cpanel::NameServer::Remote::CDN::DB

=head1 SYNOPSIS

    package MyRootSQLiteDB;

    use cPstrict;

    use parent qw{ Cpanel::SQLite::RootData };

    use constant FILENAME => q[/var/mydatabase.sqlite];

    __DATA__

    @@ migrations

    -- 1 up

    create table mytable (
        id          INTEGER PRIMARY KEY,
        name        TEXT NOT NULL UNIQUE,
    );

    -- 1 down

    drop table mytable;

=head1 DESCRIPTION

Cpanel::SQLite::RootData is providing a base class to manipulate one SQLite database stored
to one path location defined by FILENAME.

This is using C<Mojo::SQLite> backend, which will automatically track your migrations

=head1 FUNCTIONS

=cut

sub _before_build ( $self, %opts ) {

    _root_required();

    return $self->SUPER::_before_build( $self, %opts ) if $self->can('SUPER::_before_build');
    return $self;
}

sub _build_db_file ($self) {
    return $self->FILENAME;
}

sub _root_required {
    die Cpanel::Exception::create('RootRequired') if $>;
    return;
}

1;
