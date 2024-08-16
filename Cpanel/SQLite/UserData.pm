package Cpanel::SQLite::UserData;

# cpanel - Cpanel/SQLite/UserData.pm               Copyright 2023 cPanel, L.L.C.
#                                                           All rights reserved.
# copyright@cpanel.net                                         http://cpanel.net
# This code is subject to the cPanel license. Unauthorized copying is prohibited

use cPstrict;

use Cpanel            ();
use Cpanel::Exception ();

use Simple::Accessor qw{
  user
};

use parent qw{ Cpanel::SQLite::MojoBase };

=encoding utf8

=head1 NAME

Cpanel::SQLite::UserData

=head1 SYNOPSIS

    package MyCustomSQLite::Storage;

    use cPstrict;

    use parent qw{ Cpanel::SQLite::UserData };

    use constant FILENAME => q[mydatabase.sqlite]; # stored in ~/.cpanel directory

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

Cpanel::SQLite::UserData is providing a base class to manipulate one SQLite database stored
in a cPanel user home directory.

This is using C<Mojo::SQLite> backend via Cpanel::SQLite::MojoBase, which automatically tracks
your migrations.

=head1 FUNCTIONS

=cut

sub _build_user {
    return Cpanel::current_username();
}

sub _build_db ($self) {

    my $db;
    eval { $db = $self->SUPER::_build_db(); 1 } or do {
        my $error = $@;

        # check if we ran out of quota and provide a better error message when it occurs
        require Cpanel::Quota;
        Cpanel::Quota::die_if_has_reached_quota();

        die $error;
    };

    return $db;
}

sub _build_db_file ($self) {

    Cpanel::initcp() unless length $Cpanel::abshomedir;

    die unless length $Cpanel::abshomedir;

    return sprintf( "%s/.cpanel/%s", $Cpanel::abshomedir, $self->filename );
}

sub _build_sqlite ($self) {

    _root_prohibited();

    return $self->SUPER::_build_sqlite();
}

sub _root_prohibited {

    return unless $> == 0;

    die Cpanel::Exception::create( 'RootProhibited', 'This code forbids “[_1]” as the effective user [asis,EUID].', ['root'] );
}

1;
