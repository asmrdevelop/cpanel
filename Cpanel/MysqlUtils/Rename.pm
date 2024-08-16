package Cpanel::MysqlUtils::Rename;

# cpanel - Cpanel/MysqlUtils/Rename.pm             Copyright 2022 cPanel, L.L.C.
#                                                           All rights reserved.
# copyright@cpanel.net                                         http://cpanel.net
# This code is subject to the cPanel license. Unauthorized copying is prohibited

#----------------------------------------------------------------------
#NOTE: This module's code handles renames on the MySQL cluster only.
#It does not interact with the DB map.
#----------------------------------------------------------------------

use strict;
use warnings;

use Try::Tiny;

use Cpanel::CommandQueue::DB       ();
use Cpanel::Exception              ();
use Cpanel::Mysql::Error           ();
use Cpanel::MysqlUtils::Definer    ();
use Cpanel::MysqlUtils::Quote      ();
use Cpanel::MysqlUtils::Support    ();
use Cpanel::MysqlUtils::Statements ();
use Cpanel::MysqlUtils::Show       ();

my %SHOW_CREATE_index_of_sql_string = qw(
  VIEW        1
  PROCEDURE   2
  FUNCTION    2
  TRIGGER     2
  EVENT       3
);

my @DB_OBJECT_TYPES = ( 'VIEW', 'PROCEDURE', 'FUNCTION', 'TRIGGER', 'EVENT' );

#MySQL's RENAME USER command doesn't change ownership of any stored triggers
#or routines. This function fixes that. It also handles the rename of every
#user/host combination, not just a single one.
#
#ON SUCCESS: returns 1
#ON FAILURE: throws a Cpanel::Exception::Database::Error instance
#}
sub rename_user {
    my ( $dbh, $olduser, $newuser ) = @_;

    local $dbh->{RaiseError} = 1;

    #NOTE: Ideally we would do all of this within a transaction,
    #but MySQL doesn't support that.
    #cf.: http://dev.mysql.com/doc/refman/5.5/en/implicit-commit.html

    my $grantees_ar = $dbh->selectcol_arrayref( 'SELECT DISTINCT GRANTEE FROM INFORMATION_SCHEMA.USER_PRIVILEGES WHERE SUBSTR(GRANTEE FROM 1 FOR LENGTH(QUOTE(?))) = QUOTE(?)', undef, $olduser, $olduser );

    if ( $olduser eq $newuser ) {
        die Cpanel::Exception::create( 'InvalidParameter', 'Renaming a MySQL user, [_1], to itself, [_1], is not possible.', [$olduser] );
    }

    if ( !@$grantees_ar ) {
        die Cpanel::Exception::create( 'Database::UserNotFound', [ name => $olduser, engine => 'mysql' ] );
    }

    my $quoted_olduser = $dbh->quote($olduser);
    my $quoted_newuser = $dbh->quote($newuser);

    my %user_translation;
    for my $olduserhost (@$grantees_ar) {
        my $newuserhost = $olduserhost;
        $newuserhost =~ s<\A\Q$quoted_olduser\E><$quoted_newuser>;

        $user_translation{$olduserhost} = $newuserhost;
    }

    #This should never happen in production.
    die "Nothing to rename ($olduser, $newuser)!" if !%user_translation;

    my @statements;

    #NOTE: MySQL's response doesn't distinguish between "old username not found"
    #and "new username already exists" .. as a consequence of which we can't
    #throw a NameConflict error as we can when renaming a database.
    for my $oldname_q ( keys %user_translation ) {
        push @statements,
          {
            work           => "RENAME USER $oldname_q TO $user_translation{$oldname_q}",
            rollback       => "RENAME USER $user_translation{$oldname_q} TO $oldname_q",
            rollback_label => "Restore user: $oldname_q",
          };
    }

    my $definer_statements_ar = _statements_to_change_definer_of_database_objects(
        $dbh,
        $olduser,
        $newuser,
    );

    push @statements, @$definer_statements_ar;

    return _execute_pseudo_atomic_statements(
        $dbh,
        [ @statements, @$definer_statements_ar ],
    );
}

###########################################################################
#
# Method:
#   change_definer_of_database_objects
#
# Description:
#   This function recreates MySQL events, triggers, procedures, functions, and views owned by a specified definer
#   with a new definer.
#
# Parameters:
#   $dbh         - A database handle with an active MySQL connection.
#   $old_definer - The MySQL username to search as the definer of the events, functions, procedures, triggers, and views
#                  to recreate. This maps only to the user part of the full user@host definer name.
#   $new_definer - The MySQL username to use as the definer for the recreated events, functions, procedures, triggers,
#                  and views. This maps only to the user part of the full user@host definer name.
#   @types       - Optional. The specific database object types that we want to change the definer of.
#                  Possible values: VIEW, PROCEDURE, FUNCTION, TRIGGER, EVENT.
#                  Defaults to all possible objects.
#
#
# Exceptions:
#   die - Thrown any of the event, function, procedure, trigger, or view queries fail.
#
# Returns:
#   This method returns a hashref in the following form:
#   {
#      failures => an array reference containing a list of failures in recreating database objects. Has the following form:
#         [
#            {
#               command => The SQL statement that failed.
#               error   => A Cpanel::Exception::Database::Error object containing the failure message.
#            }
#         ]
#   }
#
sub change_definer_of_database_objects {
    my ( $dbh, $old_definer, $new_definer, @types ) = @_;

    @types = @DB_OBJECT_TYPES if !@types;

    return _execute_pseudo_atomic_statements(
        $dbh,
        _statements_to_change_definer_of_database_objects( $dbh, $old_definer, $new_definer, @types ),
    );
}

sub _statements_to_change_definer_of_database_objects {
    my ( $dbh, $old_definer, $new_definer, @types ) = @_;

    @types = @DB_OBJECT_TYPES if !@types;

    my $process_db_types = sub {
        my @func = @_;

        return sub {
            my $type = shift;
            foreach my $f (@func) {
                my ( $regex, $sub ) = @$f;
                if ( $type =~ $regex ) {
                    return $sub->();
                }
            }
        };
    };

    my $get_obj = $process_db_types->(
        [ qr/VIEW/i      => sub { return Cpanel::MysqlUtils::Definer::get_views_by_definer( $dbh, $old_definer ) } ],
        [ qr/PROCEDURE/i => sub { return Cpanel::MysqlUtils::Definer::get_procedures_by_definer( $dbh, $old_definer ) } ],
        [ qr/FUNCTION/i  => sub { return Cpanel::MysqlUtils::Definer::get_functions_by_definer( $dbh, $old_definer ) } ],
        [ qr/TRIGGER/i   => sub { return Cpanel::MysqlUtils::Definer::get_triggers_by_definer( $dbh, $old_definer ) } ],
        [ qr/EVENT/i     => sub { return Cpanel::MysqlUtils::Definer::get_events_by_definer( $dbh, $old_definer ) } ],
    );

    my %type_objects;

    foreach my $db_obj (@types) {
        $type_objects{$db_obj} = $get_obj->($db_obj);
    }

    my @statements;

    while ( my ( $type, $objs_ar ) = each %type_objects ) {
        for my $db_object_hr (@$objs_ar) {
            my ( $database_name, $object_name ) = @{$db_object_hr}{qw( database_name name )};
            push @statements, _statements_to_update_object_if_needed( $dbh, $type, $database_name, $object_name, $old_definer, $new_definer );
        }
    }

    return \@statements;
}

#This will generally die() on error.
#
#If, however, the rename succeeds but the cleanup fails, then this returns
#a hashref with the following structure:
#{
#   failures => [
#       {
#           command => '..',
#           error => Cpanel::Exception::Database::Error object
#       },
#       ..,
#   ],
#}
#
#Basically, an exception thrown here should be reported as an error, while
#anything in the "failures" array could be considered a warning--however, such
#"warning"s probably indicate serious DB problems!
#
sub rename_database {
    my ( $dbh, $oldname, $newname ) = @_;

    $dbh = $dbh->clone( { RaiseError => 1, mysql_multi_statements => 1 } );

    my ( $oldname_q, $newname_q ) = map { $dbh->quote_identifier($_) } ( $oldname, $newname );

    my $tables_ar;

    $tables_ar = $dbh->selectcol_arrayref("SHOW FULL TABLES IN $oldname_q WHERE Table_type='BASE TABLE'");

    #Renaming a corrupt table can spread the corruption,
    #depending on the table engine. Try to limit that danger.
    _verify_tables_integrity( $dbh, $oldname, $tables_ar ) if @$tables_ar;

    my @renames;
    for my $table (@$tables_ar) {
        my $table_q = $dbh->quote_identifier($table);

        my $old = "$oldname_q.$table_q";
        my $new = "$newname_q.$table_q";

        push @renames,
          {
            rollback_label => "Restore table: $table",
            work           => "RENAME TABLE $old TO $new",
            rollback       => "RENAME TABLE $new TO $old",
          };
    }

    my $non_tables_hr = get_non_tables_in_db( $dbh, $oldname );

    my @trigger_names = @{ $non_tables_hr->{'TRIGGER'} };

    while ( my ( $type, $value_ar ) = each %$non_tables_hr ) {
        for my $value_item (@$value_ar) {

            my $sql_create_cmd;

            #TODO: This logic branching is only needed for MySQL 5.0.
            if ( $type eq 'TRIGGER' ) {
                $sql_create_cmd = Cpanel::MysqlUtils::Show::show_create_trigger( $dbh, $oldname, $value_item )->[2];
            }
            else {
                my $quoted   = Cpanel::MysqlUtils::Quote::quote_db_and_name( $oldname, $value_item );
                my $shown_ar = $dbh->selectrow_arrayref("SHOW CREATE $type $quoted");

                #Replace list items with the SQL contents.
                $sql_create_cmd = $shown_ar->[ $SHOW_CREATE_index_of_sql_string{$type} ];
            }

            #Replace list items with the SQL contents.
            $value_item = {
                name => $value_item,
                work => Cpanel::MysqlUtils::Statements::rename_db_in_command( $oldname, $newname, $sql_create_cmd ),

                #Only needed for TRIGGERs, but might as well store them all
                rollback => $sql_create_cmd,
            };
        }
    }

    my $new_grants_ar = Cpanel::MysqlUtils::Show::show_grants_on_dbs( $dbh, $oldname );

    # Kick out any grants that aren't for the old DB, as '*' also matches
    # the $oldname, and show_grants_on_dbs just queries the DB for this.
    $new_grants_ar = [ grep { $_->db_name($newname) if ( $_->db_name eq $oldname ); } @$new_grants_ar ];

    my @statements;

    my $queue_dbh = $dbh->clone( { RaiseError => 1 } );

    push @statements, {
        work => sub {
            try {
                $queue_dbh->do("CREATE DATABASE $newname_q");
                $queue_dbh->do("USE $newname_q");
            }
            catch {
                if ( $_->get('error_code') eq Cpanel::Mysql::Error::ER_DB_CREATE_EXISTS() ) {
                    die Cpanel::Exception::create( 'NameConflict', 'This MySQL cluster already has a database named “[_1]”.', [$newname] );
                }

                die $_;
            };
        },
        rollback       => "DROP DATABASE $newname_q",
        rollback_label => 'Drop new database',
    };

    #Must drop triggers before renaming tables, or MySQL complains
    #about 'Trigger in wrong schema'.
    for my $trig_op ( values @{ $non_tables_hr->{'TRIGGER'} } ) {
        push @statements, {
            work     => "DROP TRIGGER $oldname_q." . $dbh->quote_identifier( $trig_op->{'name'} ),
            rollback => sub {
                my $this_dbh = $queue_dbh->clone( { db => $oldname } );
                $this_dbh->do( $trig_op->{'rollback'} );
            },
            rollback_label => "Restore trigger: $trig_op->{'name'}",
        };
    }

    #Rename/move all tables from the old DB to the new.
    push @statements, @renames;

    #Create all non-tables in the new DB.
    for my $obj_type ( keys %$non_tables_hr ) {
        for my $stmt_data ( @{ $non_tables_hr->{$obj_type} } ) {
            push @statements, {
                work => $stmt_data->{'work'},

                #No rollback here because we'll delete the new DB anyway,
                #EXCEPT for triggers because they will forestall RENAME TABLE.
                ( $obj_type eq 'TRIGGER' )
                ? (
                    rollback       => "DROP TRIGGER $newname_q." . $dbh->quote_identifier( $stmt_data->{'name'} ),
                    rollback_label => "Drop trigger from new database: $stmt_data->{'name'}",
                  )
                : (),
            };
        }
    }

    #Add grants for the new DB.
    #No rollback here because we'll delete the new DB anyway.
    # Since we don't need to change their password, don't include db_rest
    # by providing 1 to 'to_string_with_sanity'.
    push @statements, map { { work => $_->to_string_with_sanity(1) } } @$new_grants_ar;

    #DROP DATABASE does not remove grants on the renamed database. :-(
    my @cleanup_statements;
    my $grants_ar = Cpanel::MysqlUtils::Show::show_grants_on_dbs( $dbh, $oldname );
    my %unique_user_hosts;
    for my $grant_obj (@$grants_ar) {
        $unique_user_hosts{ $grant_obj->db_user() }{ $grant_obj->db_host() } = undef;
    }
    for my $user ( keys %unique_user_hosts ) {
        for ( keys %{ $unique_user_hosts{$user} } ) {
            push @cleanup_statements,
              sprintf(
                'REVOKE ALL PRIVILEGES ON %s.* FROM %s@%s',
                Cpanel::MysqlUtils::Quote::quote_pattern_identifier($oldname),
                $dbh->quote($user),
                $dbh->quote($_),
              );
        }
    }

    push @cleanup_statements, "DROP DATABASE $oldname_q";

    #----------------------------------------------------------------------
    # POINT OF NO RETURN
    #
    # Beyond here, any changes to the DB MUST include a rollback mechanism
    # in the event of failure.
    #----------------------------------------------------------------------

    _execute_pseudo_atomic_statements(
        $queue_dbh,
        \@statements,
    );

    #At this point, the new DB is (as best we know!) set up correctly.
    #Any failures beyond here are non-fatal and don't require rollback.
    #We still report them, but not as exceptions.

    my @extra_errors;
    while (@cleanup_statements) {
        my $stmt;
        try {
            while ( $stmt = shift @cleanup_statements ) {
                $dbh->do($stmt);
            }
        }
        catch {
            push @extra_errors,
              {
                command => $stmt,
                error   => Cpanel::Exception::get_string($_),
              };
        };
    }

    return {
        failures => \@extra_errors,
    };
}

sub _execute_pseudo_atomic_statements {
    my ( $dbh, $statements_ar ) = @_;

    my $queue = Cpanel::CommandQueue::DB->new($dbh);
    for (@$statements_ar) {
        $queue->add( @{$_}{qw( work  rollback  rollback_label )} );
    }

    $queue->run();

    return 1;
}

sub _verify_tables_integrity {
    my ( $dbh, $dbname, $tables_ar ) = @_;

    my $dbname_q = $dbh->quote_identifier($dbname);

    my %table_error;
    my $sth = $dbh->prepare( 'CHECK TABLE ' . join( ',', map { "$dbname_q." . $dbh->quote_identifier($_) } @$tables_ar ) );
    $sth->execute();
    while ( my $row_hr = $sth->fetchrow_hashref() ) {
        next if $row_hr->{'Msg_type'} ne 'error';
        $table_error{ $row_hr->{'Table'} } = $row_hr->{'Msg_text'};
    }

    if (%table_error) {
        die Cpanel::Exception::create( 'Database::TableCorruption', [ table_error => \%table_error ] );
    }

    return 1;
}

sub get_non_tables_in_db {
    my ( $dbh, $database ) = @_;

    my %non_tables = (
        VIEW => $dbh->selectcol_arrayref(
            'SELECT TABLE_NAME FROM INFORMATION_SCHEMA.VIEWS WHERE TABLE_SCHEMA = ?',
            undef,
            $database,
        ),
        PROCEDURE => $dbh->selectcol_arrayref(
            q<SELECT ROUTINE_NAME FROM INFORMATION_SCHEMA.ROUTINES WHERE ROUTINE_SCHEMA = ? AND ROUTINE_TYPE='PROCEDURE'>,
            undef,
            $database,
        ),
        FUNCTION => $dbh->selectcol_arrayref(
            q<SELECT ROUTINE_NAME FROM INFORMATION_SCHEMA.ROUTINES WHERE ROUTINE_SCHEMA = ? AND ROUTINE_TYPE='FUNCTION'>,
            undef,
            $database,
        ),
        TRIGGER => $dbh->selectcol_arrayref(
            'SELECT TRIGGER_NAME FROM INFORMATION_SCHEMA.TRIGGERS WHERE TRIGGER_SCHEMA = ?',
            undef,
            $database,
        ),
    );

    if ( Cpanel::MysqlUtils::Support::server_supports_events($dbh) ) {
        $non_tables{'EVENT'} = $dbh->selectcol_arrayref(
            'SELECT EVENT_NAME FROM INFORMATION_SCHEMA.EVENTS WHERE EVENT_SCHEMA = ?',
            undef,
            $database,
        );
    }

    return \%non_tables;
}

sub _statements_to_update_object_if_needed {    ## no critic qw(ProhibitManyArgs)
    my ( $dbh, $type, $db, $name, $olduser, $newuser ) = @_;

    my $quoted_db_and_name = Cpanel::MysqlUtils::Quote::quote_db_and_name( $db, $name );

    my $create_sql;
    if ( $type eq 'TRIGGER' ) {
        $create_sql = Cpanel::MysqlUtils::Show::show_create_trigger( $dbh, $db, $name )->[2];
    }
    else {
        my $shown_ar = $dbh->selectrow_arrayref("SHOW CREATE $type $quoted_db_and_name");
        $create_sql = $shown_ar->[ $SHOW_CREATE_index_of_sql_string{$type} ];
    }

    my $rollback_sql = $create_sql;

    my $id_quoted_olduser = $dbh->quote_identifier($olduser);
    my $id_quoted_newuser = $dbh->quote_identifier($newuser);

    my $needs_update = $create_sql =~ s<DEFINER\s*=\s*$id_quoted_olduser\@(`.*?`)><DEFINER=$id_quoted_newuser\@$1>;

    #MySQL 5.1 didn't record the DEFINER in CREATE EVENT strings in tests.
    if ( $create_sql =~ m<\ACREATE\s+EVENT>i ) {
        my ($definer) = $dbh->selectrow_array( 'SELECT DEFINER FROM INFORMATION_SCHEMA.EVENTS WHERE EVENT_SCHEMA = ? AND EVENT_NAME = ?', { Slice => {} }, $db, $name );

        my $definer_host   = ( split m<\@>, $definer, 2 )[1];
        my $definer_host_q = $dbh->quote_identifier($definer_host);

        $create_sql =~ s<\A(CREATE\s+)><$1DEFINER=$id_quoted_newuser\@$definer_host_q >;
        $needs_update = 1;
    }

    return if !$needs_update;

    my @statements = (
        {
            work     => "DROP $type $quoted_db_and_name",
            rollback => sub {

                #Needed because some of the CREATE events that we read from MySQL don't
                #reference objects with the DB.
                my $db_specific_dbh = $dbh->clone( { db => $db } );
                $db_specific_dbh->do($rollback_sql);
            },
            rollback_label => "Restore original DEFINER for $type: $name",
        },
        {
            work => sub {

                #Needed because some of the CREATE events that we read from MySQL don't
                #reference objects with the DB.
                my $db_specific_dbh = $dbh->clone( { db => $db } );
                $db_specific_dbh->do($create_sql);
            },
            rollback       => "DROP $type $quoted_db_and_name",
            rollback_label => "Delete updated $type: $name",
        },
    );

    return @statements;
}

1;
