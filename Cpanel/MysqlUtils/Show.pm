package Cpanel::MysqlUtils::Show;

# cpanel - Cpanel/MysqlUtils/Show.pm               Copyright 2022 cPanel, L.L.C.
#                                                           All rights reserved.
# copyright@cpanel.net                                         http://cpanel.net
# This code is subject to the cPanel license. Unauthorized copying is prohibited

use strict;
use warnings;

use Try::Tiny;

use Cpanel::Exception           ();
use Cpanel::Mysql::Error        ();
use Cpanel::MysqlUtils::Grants  ();
use Cpanel::MysqlUtils::Quote   ();
use Cpanel::MysqlUtils::Support ();
use Cpanel::MysqlUtils::Unquote ();

use Try::Tiny;

#Depending on the server version, this will construct its result
#based on SHOW CREATE TRIGGER or the INFORMATION_SCHEMA.
#TODO: Once MySQL 5.0 is gone, remove this.
sub show_create_trigger {
    my ( $dbh, $trigger_db, $trigger_name ) = @_;

    if ( Cpanel::MysqlUtils::Support::server_supports_show_create_trigger($dbh) ) {
        my $full_name_q     = Cpanel::MysqlUtils::Quote::quote_db_and_name( $trigger_db, $trigger_name );
        my $the_easy_way_ar = $dbh->selectrow_arrayref("SHOW CREATE TRIGGER $full_name_q");
        return $the_easy_way_ar;
    }

    return _manual_show_create_trigger( $dbh, $trigger_db, $trigger_name );
}

sub _manual_show_create_trigger {
    my ( $dbh, $trigger_db, $trigger_name ) = @_;

    my $trigger_hr = $dbh->selectrow_hashref(
        'SELECT * FROM INFORMATION_SCHEMA.TRIGGERS WHERE TRIGGER_SCHEMA=? AND TRIGGER_NAME=?',
        { Slice => {} },
        $trigger_db,
        $trigger_name,
    );

    my $full_trigger_name_q = Cpanel::MysqlUtils::Quote::quote_db_and_name( $trigger_db, $trigger_name );

    die "Trigger $full_trigger_name_q does not exist!" if !$trigger_hr;

    my $create_stmt = join ' ', (

        'CREATE',

        'DEFINER=' . join(
            '@',
            map { $dbh->quote_identifier($_) }
              split m<@>, $trigger_hr->{'DEFINER'}
        ),

        'TRIGGER',

        $full_trigger_name_q,

        $trigger_hr->{'ACTION_TIMING'},

        $trigger_hr->{'EVENT_MANIPULATION'},

        'ON',

        Cpanel::MysqlUtils::Quote::quote_db_and_name( @{$trigger_hr}{qw(EVENT_OBJECT_SCHEMA EVENT_OBJECT_TABLE)} ),

        'FOR EACH ROW',

        $trigger_hr->{'ACTION_STATEMENT'},
    );

    return [
        $trigger_name,
        $trigger_hr->{'SQL_MODE'},
        $create_stmt,

        #NOTE: It does no good to return these because they weren't added until
        #the same MySQL version that added SHOW CREATE TRIGGER. They're left in
        #as an FYI, were there some need to emulate SHOW CREATE TRIGGER
        #more perfectly.
        #
        #@{$trigger_hr}{
        #    qw(
        #      CHARACTER_SET_CLIENT
        #      COLLATION_CONNECTION
        #      DATABASE_COLLATION
        #      )
        #},
    ];
}

#MySQL's SHOW GRANTS only gives us the grants for a given user.
#We frequently need all of the grants on a particular DATABASE,
#so this function wraps up that need into a single call.
#
#NOTE This is a bit tricky because MySQL doesn't give us anything that does,
#"give me all privileges on this database." So, to replicate that, and to
#ensure that we restore table- and column-specific grants as well:
#
#1) Grab all user/host pairs for the given databases.
#2) SHOW GRANTS for each user/host pair.
#3) Weed out any grants that don't involve one of the given databases.
#
#Input is a db handle, and a list of database names.
#
#Output is an arrayref of Cpanel::MysqlUtils::Grants objects.
#NOTE: This will include USAGE grants.
#
sub show_grants_on_dbs {
    my ( $dbh, @dbs ) = @_;

    my @tables_to_query = qw(
      SCHEMA_PRIVILEGES
      TABLE_PRIVILEGES
      COLUMN_PRIVILEGES
    );

    #NOTE: TABLE_SCHEMA values are patterns, as a result of which
    #we actually treat the DB as the object of the pattern match.
    my $where_clause = join(
        q{ OR },
        map {
            my $quoted_db = $dbh->quote($_);
            "($quoted_db LIKE TABLE_SCHEMA)"
        } @dbs
    );

    $where_clause ||= '0';

    my $user_host_query = join( ' UNION ', map { "SELECT DISTINCT GRANTEE FROM INFORMATION_SCHEMA.$_ WHERE $where_clause" } @tables_to_query );

    my $user_host_ar = $dbh->selectcol_arrayref($user_host_query);

    #NOTE: The DB handle should have thrown an exception on error normally.
    #The below is just in case there is some non-RaiseError's DBI handle given:
    if ( $dbh->err() ) {
        die Cpanel::Exception->create( 'The query “[_1]” failed because of an error: [_2]', $user_host_query, $dbh->errstr() );
    }

    my @grants;

    my $user_host_regexp = qr{\A($Cpanel::MysqlUtils::Unquote::QUOTED_STRING_REGEXP)\@($Cpanel::MysqlUtils::Unquote::QUOTED_STRING_REGEXP)\z}ox;

    local $dbh->{'RaiseError'} = 1;

    #Use this construct to avoid the try/catch overhead for each user/host.
    while (@$user_host_ar) {
        try {
            while ( my $user_host = shift @$user_host_ar ) {
                my ( $user, $host_pattern ) = map { Cpanel::MysqlUtils::Unquote::unquote($_) } ( $user_host =~ $user_host_regexp );

                my @grant_txts = $dbh->show_grants( $user, $host_pattern ) or do {
                    die Cpanel::Exception::create_raw( $dbh->errstr() );
                };

                for my $grant_txt (@grant_txts) {
                    my $grant_obj = Cpanel::MysqlUtils::Grants::parse($grant_txt) or next;

                    if ( grep { $grant_obj->matches_db_name($_) } @dbs ) {
                        push @grants, $grant_obj;
                    }
                }
            }
        }
        catch {

            #ER_NONEXISTING_GRANT happens if the grant that we read is was
            #for a user that doesn't actually exist. In this case, we don't
            #care about the error and just want to keep going.
            die $_ if $dbh->err() ne Cpanel::Mysql::Error::ER_NONEXISTING_GRANT();
        };
    }

    return \@grants;
}

1;
