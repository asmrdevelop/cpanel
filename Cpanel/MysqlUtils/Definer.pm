package Cpanel::MysqlUtils::Definer;

# cpanel - Cpanel/MysqlUtils/Definer.pm            Copyright 2022 cPanel, L.L.C.
#                                                           All rights reserved.
# copyright@cpanel.net                                         http://cpanel.net
# This code is subject to the cPanel license. Unauthorized copying is prohibited

use strict;
use warnings;

use Cpanel::MysqlUtils::Support ();

=encoding utf-8

=head1 NAME

Cpanel::MysqlUtils::Definer - Extract MySQL data by definer

=cut

=head2 get_functions_by_definer($dbh, $definer)

These functions get the MySQL functions, procedures, triggers, or views that have the specified definer.

NOTE: Triggers can be created with a definer in MySQL 5.0 cf. http://dev.mysql.com/doc/refman/5.0/en/create-trigger.html

=over 2

=item Input

=over 3

=item * $dbh     - A database handle with an active MySQL connection.

=item * $definer - The MySQL username to search as the definer of the functions, procedures, triggers, or views to return. This maps only to the user part of the full user@host definer name.

=back

=item Exceptions

=over 3

=item * die - Thrown if the database query fails.

=back

=item Returns

=over 3

This method returns an empty arrayref if no procedures are found that have a definer that matches
the passed in definer. If procedures are found, the method will return an arrayref containing hashrefs
representing the matching functions, procedures, triggers, or views. Expect the following form:

 [
   {
     'database_name' - The name of the database in which the procedure is defined.
     'name'          - The name of the function, procedure, trigger, or view.
   }
 ]

=back

=back

=head2 get_procedures_by_definer($dbh, $definer)

See above

=head2 get_triggers_by_definer($dbh, $definer)

See above

=head2 get_views_by_definer($dbh, $definer)

See above

=cut

sub get_procedures_by_definer {
    my ( $dbh, $definer ) = @_;

    return $dbh->selectall_arrayref( q<SELECT ROUTINE_SCHEMA as database_name, ROUTINE_NAME name FROM INFORMATION_SCHEMA.ROUTINES WHERE ROUTINE_TYPE='PROCEDURE' AND SUBSTRING_INDEX(DEFINER,'@',1) = ?>, { Slice => {} }, $definer );
}

sub get_functions_by_definer {
    my ( $dbh, $definer ) = @_;

    return $dbh->selectall_arrayref( q<SELECT ROUTINE_SCHEMA as database_name, ROUTINE_NAME as name FROM INFORMATION_SCHEMA.ROUTINES WHERE ROUTINE_TYPE='FUNCTION' AND SUBSTRING_INDEX(DEFINER,'@',1) = ?>, { Slice => {} }, $definer );
}

sub get_views_by_definer {
    my ( $dbh, $definer ) = @_;

    #NOTE: The below query can crash the server because it will scan ALL databases.
    #return $dbh->selectall_arrayref( qq<SELECT TABLE_SCHEMA as database_name, TABLE_NAME as name FROM INFORMATION_SCHEMA.VIEWS WHERE $match_information_schema_to_definer>, { Slice => {} }, $definer, $definer );

    #cf. http://www.pythian.com/blog/how-to-tell-when-using-information_schema-might-crash-your-database/

    #Let's assume, for this query, that we only care about DBs where the user has privileges.
    my $dbs_ar = _get_dbs_for_dbuser( $dbh, $definer );

    my @payload;
    for my $db (@$dbs_ar) {

        #The below query will only scan one database.
        #It needs to use INFORMATION_SCHEMA because of the DEFINER lookup.
        my $views_ar = $dbh->selectcol_arrayref( q<SELECT TABLE_NAME FROM INFORMATION_SCHEMA.VIEWS WHERE TABLE_SCHEMA = ? and SUBSTRING_INDEX(DEFINER,'@',1) = ?>, { Slice => {} }, $db, $definer );
        push @payload, map { { database_name => $db, name => $_ } } @$views_ar;
    }

    return \@payload;
}

sub get_triggers_by_definer {
    my ( $dbh, $definer ) = @_;

    #NOTE: The below query can crash the server because it will scan ALL databases.
    #return $dbh->selectall_arrayref( qq<SELECT TRIGGER_SCHEMA as database_name, TRIGGER_NAME as name FROM INFORMATION_SCHEMA.TRIGGERS WHERE $match_information_schema_to_definer>, { Slice => {} }, $definer, $definer );

    #cf. http://www.pythian.com/blog/how-to-tell-when-using-information_schema-might-crash-your-database/

    #Let's assume, for this query, that we only care about DBs where the user has privileges.
    my $dbs_ar = _get_dbs_for_dbuser( $dbh, $definer );

    my @payload;
    for my $db (@$dbs_ar) {
        my $quoted_db = $dbh->quote_identifier($db);
        my $views_ar  = $dbh->selectcol_arrayref( qq<SHOW TRIGGERS IN $quoted_db WHERE SUBSTRING(DEFINER,1,1 + LENGTH(?)) = CONCAT(?, '\@')>, { Slice => {} }, $definer, $definer );
        push @payload, map { { database_name => $db, name => $_ } } @$views_ar;
    }

    return \@payload;
}

sub _get_dbs_for_dbuser {
    my ( $dbh, $dbuser ) = @_;

    return $dbh->selectcol_arrayref( q<SELECT DISTINCT SCHEMA_NAME FROM INFORMATION_SCHEMA.SCHEMATA, mysql.db WHERE SCHEMA_NAME LIKE mysql.db.db AND mysql.db.user = ?>, undef, $dbuser );
}

=head2 get_events_by_definer($dbh, $definer)

This function gets the MySQL events that have the specified definer. If the MySQL server does not support
events, then an empty arrayref is returned.

=over 2

=item Input

=over 3

=item * $dbh     - A database handle with an active MySQL connection.

=item * $definer - The MySQL username to search as the definer of the events to return.

=back

=item Exceptions

=over 3

=item * die - Thrown if the database query fails.

=back

=item Returns:

=over 3

This method returns an empty arrayref if no events are found that have a definer that matches
the passed in definer or the MySQL server does not support events. If events are found, the
method will return an arrayref containing hashrefs representing the matching events. Expect the following form:

 [
   {
     'database_name' - The name of the database in which the event is defined.
     'name'          - The name of the event.
   }
 ]

=back

=back

=cut

sub get_events_by_definer {
    my ( $dbh, $definer ) = @_;

    if ( !Cpanel::MysqlUtils::Support::server_supports_events($dbh) ) {
        return [];
    }

    return $dbh->selectall_arrayref( q<SELECT EVENT_SCHEMA as database_name, EVENT_NAME as name FROM INFORMATION_SCHEMA.EVENTS WHERE SUBSTRING_INDEX(DEFINER,'@',1) = ?>, { Slice => {} }, $definer );
}

1;
