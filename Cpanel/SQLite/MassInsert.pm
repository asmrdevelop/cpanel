package Cpanel::SQLite::MassInsert;

# cpanel - Cpanel/SQLite/MassInsert.pm             Copyright 2022 cPanel, L.L.C.
#                                                           All rights reserved.
# copyright@cpanel.net                                         http://cpanel.net
# This code is subject to the cPanel license. Unauthorized copying is prohibited

use strict;
use warnings;

use constant SQLITE_MAX_VARIABLE_NUMBER => 999;

=encoding utf-8

=head1 NAME

Cpanel::SQLite::MassInsert - Quickly insert groups of values into an sqlite database.

=head1 SYNOPSIS

    use Cpanel::SQLite::MassInsert ();

    # Single values
    my $first_run_mass_inserter = Cpanel::SQLite::MassInsert->new(
        'query'      => q{INSERT OR IGNORE INTO seen_files (path) VALUES},
        'fields_sql' => q{(?)},
        'dbh'        => $dbh
    );

    $first_run_mass_inserter->insert_fields_sql_ar( [1,2,3,4,5,6,7,8,9,10,.......] );


    my $chunk_size = $mass_inserter->chunk_size();

    # ...or multiple values
    my $mass_inserter = Cpanel::SQLite::MassInsert->new(
        'query'      => q{INSERT INTO file_changes (seen_files_id, size, type, mtime, backup_id) VALUES},
        'fields_sql' => q{( (SELECT file_id FROM seen_files WHERE path=? ), ?, ?, ?, ? )},
        'dbh'        => $dbh
    );

    my $chunk_size = $mass_inserter->chunk_size();

    # Groups of 5 will be spliced out
    $mass_inserter->insert_fields_sql_ar( [1,2,3,4,5, 6,7,8,9,10, .......] );


=head1 DESCRIPTION

This module allows you to insert a large arrayref of values with the same
insert statement.  The values will be spliced out of chunk from the arrayref
passed to insert_fields_sql_ar.

=cut

=head2 new(%OPTS)

Create a mass inserter object to insert chunks of data into an sqlite
table.

=over 2

=item Input

=over 3

=item 'dbh' C<SCALAR>

    An SQLite db handle

=item 'query' C<SCALAR>

    The insert query including the VALUES keyword.

    Example:

    'INSERT INTO file_changes (seen_files_id, size, type, mtime, backup_id) VALUES'

=item 'fields_sql' C<SCALAR>

    The fields statement with placeholders.

    Example:

    '( (SELECT file_id FROM seen_files WHERE path=? ), ?, ?, ?, ? )'

=back

=back

=cut

sub new {
    my ( $class, %OPTS ) = @_;

    my ( $dbh, $query, $fields_sql ) = @OPTS{qw(dbh query fields_sql)};

    my $field_count = scalar( $fields_sql =~ tr{?}{} );
    my $chunk_size  = int( SQLITE_MAX_VARIABLE_NUMBER() / $field_count );

    # Make sure the chunk size is the a multiple of the number of fields
    # so we can extract chunks from an array
    $chunk_size = $chunk_size - ( $chunk_size % $field_count );

    die "dbh required" if !$dbh;
    if ( index( $query, 'VALUES' ) == -1 ) { die "query must contain VALUES"; }
    if ( $fields_sql =~ tr{()}{} < 2 )     { die "fields_sql must be enclosed in ()"; }

    return bless {
        '_dbh'           => $dbh,
        '_query'         => $query,
        '_fields_sql'    => $fields_sql,
        '_field_count'   => $field_count,
        '_chunk_size'    => $chunk_size,
        '_prepare_cache' => {}
    }, $class;
}

=head2 chunk_size()

insert_fields_sql_ar will figure out how to do the inserts based on any number
of fields that is a multiple of the number of sql fields AKA the number of
'?' characters in 'fields_sql'.

If you are doing a loop to collect the data and need the ideal number of values
to collect before sending the data to insert_fields_sql_ar, this is your number.

=cut

sub chunk_size {
    return $_[0]->{'_chunk_size'};
}

=head2 insert_fields_sql_ar($fields_sql_ar)

$fields_sql_ar is a single arrayref.  This function will take care
of spliting out chunks of the arrayref for inserts.

Insert a chunk of data.  The fields must be in multples of the number of
the number of sql fields AKA the number of '?' characters in 'fields_sql'.

The values will be removed from $fields_sql_ar.

=cut

sub insert_fields_sql_ar {
    my ( $self, $fields_sql_ar ) = @_;

    while ( my @chunk = splice( @$fields_sql_ar, 0, $self->{'_chunk_size'} ) ) {
        my $cache_key = scalar @chunk;
        if ( !$self->{'_prepare_cache'}{$cache_key} ) {
            my $values_ph = join ',', ( ( $self->{'_fields_sql'} ) x ( scalar @chunk / $self->{'_field_count'} ) );
            $self->{'_prepare_cache'}{$cache_key} ||= $self->{'_dbh'}->prepare( $self->{'_query'} . $values_ph );
        }
        $self->{'_prepare_cache'}{$cache_key}->execute(@chunk);
    }
    return;
}
1;
