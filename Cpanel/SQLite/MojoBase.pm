package Cpanel::SQLite::MojoBase;

# cpanel - Cpanel/SQLite/MojoBase.pm               Copyright 2023 cPanel, L.L.C.
#                                                           All rights reserved.
# copyright@cpanel.net                                         http://cpanel.net
# This code is subject to the cPanel license. Unauthorized copying is prohibited

use cPstrict;

use Cpanel::Exception            ();
use Cpanel::SafeDir::MK          ();
use Cpanel::FileUtils::TouchFile ();

use Mojo::SQLite   ();
use File::Basename ();

use Simple::Accessor qw{

  filename
  user
  db_file

  db
  sqlite

};

use parent qw{ Cpanel::Interface::JSON };

=encoding utf8

=head1 NAME

Cpanel::SQLite::MojoBase

=head1 SYNOPSIS

    package MyCustomSQLite::Storage;

    use cPstrict;

    use parent qw{ Cpanel::SQLite::MojoBase };

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

Cpanel::SQLite::MojoBase is providing a base class to manipulate one SQLite database stored
in a cPanel user home directory.

This is using C<Mojo::SQLite> backend, which will automatically track your migrations

=head1 FUNCTIONS

=cut

sub _build_db ($self) {

    return $self->sqlite->db;

}

sub _build_db_file ($self) {
    die q[_build_db_file is not implemented];
}

sub _build_filename ($self) {
    return $self->FILENAME;
}

#  Multiple calls to connect to sqlite are really expensive so we're going to do this once per process.
# keep track of migrations per sqlite file
my %_migrations_performed;

sub _build_sqlite ($self) {

    my $db_file = $self->db_file;

    my $needs_migrations = $_migrations_performed{$db_file} ? 0 : 1;

    if ( !-e $db_file ) {
        $needs_migrations = 1;
        my $dir = File::Basename::dirname($db_file);
        if ( !-d $dir ) {
            my $mode = 0700;
            Cpanel::SafeDir::MK::safemkdir( $dir, $mode )
              or die Cpanel::Exception::create( 'IO::DirectoryCreateError', [ error => $!, path => $dir, mask => $mode ] );
        }

        # touch the file to ensure creation with accurate owner
        Cpanel::FileUtils::TouchFile::touchfile($db_file);
    }

    my $sqlite = Mojo::SQLite->new( 'sqlite:' . $db_file );
    $sqlite->auto_migrate(0);    # control the migration just after
    if ($needs_migrations) {
        $sqlite->migrations->from_data( ref $self )->migrate;
        $_migrations_performed{$db_file} = 1;
    }

    return $sqlite;
}

=head2 $self->count_table( $table )

Simple helper to count the number of rows from a table.

=cut

sub count_table ( $self, $table ) {

    return scalar eval { $self->db->select( $table, { '-count' => '*' } )->array->[0] };
}

=head2 $self->_select_or_insert( $table, $key, $value, $ix = 'id' )

Naive helper to select or insert the row if missing.

=cut

sub _select_or_insert ( $self, $table, $key, $value, $ix = 'id' ) {

    foreach my $iter ( 1 .. 2 ) {

        if ( my $res = $self->db->select( $table, [$ix], { $key => $value } )->hash ) {
            my $id = $res->{$ix};
            return $id if $id;
        }

        last if $iter == 2;

        my $id = eval { $self->db->insert( $table, { $key => $value } )->last_insert_id };
        return $id if $id;
    }

    return;

}

# aliases
sub insert ( $self, @args ) {
    return $self->db->insert(@args);
}

sub select ( $self, @args ) {
    return $self->db->select(@args);
}

sub delete ( $self, @args ) {
    return $self->db->delete(@args);
}

sub update ( $self, @args ) {
    return $self->db->update(@args);
}

=head2 $self->_replace( $table, $key, $value, $fieldvals, $ix = 'id' )

Naive helper to update or insert data using a specific key

=cut

sub _replace ( $self, $table, $key, $value, $fieldvals, $ix = 'id' ) {    ## no critic qw(Subroutines::ProhibitManyArgs)

    my $db = $self->db;

    # select with the ix
    if ( my $res = $db->select( $table, [$ix], { $key => $value } )->hash ) {
        if ( my $id = $res->{$ix} ) {

            # found one id...
            $db->update( $table, $fieldvals, { $ix => $id }, { limit => 1 } );
            return $id;
        }
    }

    return eval { $db->insert( $table, $fieldvals )->last_insert_id };
}

1;
