package Cpanel::DBI::Mysql::Utils;

# cpanel - Cpanel/DBI/Mysql/Utils.pm               Copyright 2022 cPanel, L.L.C.
#                                                           All rights reserved.
# copyright@cpanel.net                                         http://cpanel.net
# This code is subject to the cPanel license. Unauthorized copying is prohibited

use strict;
use warnings;

use Try::Tiny;
use Cpanel::DBI::Mysql::Utils::Backend ();

#----------------------------------------------------------------------
#This is a mix-in class that includes common tasks to do with a DBI handle.
#----------------------------------------------------------------------

sub db_exists {
    my ( $self, $dbname ) = @_;

    return $self->selectrow_array( 'SELECT COUNT(*) FROM INFORMATION_SCHEMA.SCHEMATA WHERE BINARY SCHEMA_NAME=?', undef, $dbname );
}

sub user_exists {
    my ( $self, $dbuser, $host ) = @_;

    my $sql  = 'SELECT IF(COUNT(*) > 0, 1, 0) FROM mysql.user WHERE BINARY User=?';
    my @vars = ($dbuser);

    if ( length $host ) {
        $sql .= ' AND BINARY Host=?';
        push @vars, $host;
    }

    return $self->selectrow_array( $sql, undef, @vars );
}

# TODO: This returns an arrayref of 1-member arrayrefs.
# In the future we should refactor this to return
# a simple arrayref instead as it will reduce
# the complexity. However, since this is a bugfix
# for 11.46 we opted to not do that now to keep the size
# of the commit as small as possible.
#
# TODO: This also, just like MySQL's SHOW GRANTS, errors
# on a nonexistent user. Should it just return an empty list instead?
#
sub show_grants {
    my ( $self, $user, $host ) = @_;

    # There is a bug somewhere in DBI, DBD::mysql or libmariadb that causes
    # SHOW GRANTS to trip up with
    # selectall_arrayref failed: fetch() without execute()
    # To avoid this we do the prepare and execute manually
    #
    # return $dbh->selectall_arrayref( 'SHOW GRANTS FOR ?@?', undef, $user, $host );
    #
    # sha256 and caching_sha2 hashes aren't ascii and can easily corrupt a text file doing line parsing,
    # so we set it to use the hex() value instead. THIS ONLY WORKS ON MYSQL 8+
    # my $set_hex_enabled_query = $self->prepare('SET print_identified_with_as_hex = ON');
    # $set_hex_enabled_query->execute();

    # XXX Prevent "NO DATABASE SELECTED" errors
    $self->do("USE mysql");

    # Since we currently still need support for 5.6 and 6.7, we query the data directly from mysql.user
    my $useful_info_query;

    # 5.6 and lower use "password" column, 5,7 -> 8 use "authentication_string" for the password hash. While 5.6 has an authentication_string column, it seems to be unused
    # To determine which to use, we need to check and see which columns are available (5.6 has password and authentication_string, newer only have authentication_string)
    my $password_column_query = $self->prepare('select count(*) from INFORMATION_SCHEMA.COLUMNS where TABLE_SCHEMA = ? and TABLE_NAME = ? and COLUMN_NAME = ?');
    my $status                = $password_column_query->execute( "mysql", "user", "Password" );

    # MySQL 5.7+ doesn't return the password from SHOW GRANTS, so we pull the hash directly here, HEX encoded to avoid newlines and other terminal breaking, bug inducing stuff seen by certain authentication plugins
    my $password_column_exists = ( $status && !$DBI::errstr && ( @{ $password_column_query->fetchrow_arrayref() } )[0] );
    my $pw_column_maybe        = $password_column_exists ? ',Password' : '';
    $useful_info_query = $self->prepare( 'SELECT authentication_string' . $pw_column_maybe . ' FROM user WHERE User=? AND Host=?' );
    $status            = $useful_info_query->execute( $user, $host );

    my $pass_hash = '';
    if ( $status && !$DBI::errstr ) {
        my $ref = $useful_info_query->fetchrow_arrayref();

        # Attempt to grab the authentication_string first, if not set, try for
        # the Password column if it exists. If not, this user just doesn't
        # have a password set.
        if ( $ref && ref $ref eq 'ARRAY' ) {
            if ( length( @$ref[0] ) ) {
                $pass_hash = @$ref[0];
            }
            if ( !$pass_hash && length( @$ref[1] ) ) {
                $pass_hash = @$ref[1];
            }
        }
    }

    my $grants_query = $self->prepare('SHOW GRANTS FOR ?@?');
    $grants_query->execute( $user, $host );
    my @grants;
    foreach my $line ( map { $_->[0] } @{ $grants_query->fetchall_arrayref() } ) {
        if ( index( $line, 'GRANT USAGE' ) == 0 ) {

            # Pop off "old" IDENTIFIED by bits. Reasoning for this is to
            # ensure any grant here looks like a 5.6 grant, as that ensures
            # maximum compatibility with pkgacct tarball dumps.
            if ( ( my $index = index( $line, " IDENTIFIED" ) ) != -1 ) {
                $line = substr( $line, 0, index( $line, " IDENTIFIED" ) );
            }
            $line .= " IDENTIFIED BY PASSWORD '$pass_hash'";
        }

        $line = Cpanel::DBI::Mysql::Utils::Backend::quote_fix( $user, $host, $line );
        push @grants, $line;
    }
    return @grants;
}

1;
