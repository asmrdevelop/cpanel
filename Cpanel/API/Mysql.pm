package Cpanel::API::Mysql;

# cpanel - Cpanel/API/Mysql.pm                     Copyright 2022 cPanel, L.L.C.
#                                                           All rights reserved.
# copyright@cpanel.net                                         http://cpanel.net
# This code is subject to the cPanel license. Unauthorized copying is prohibited

#----------------------------------------------------------------------
# DEVELOPER NOTE:
# 1) The UAPI MySQL functions should *never* add the DB prefix.
# 2) On database and database user creation, if the name doesn't
#    contain the correct prefix, the call should error out.
#----------------------------------------------------------------------
# TODO:
# 1) Finish adding POD for the methods in this module [DUCK-351]
#----------------------------------------------------------------------

=encoding utf8

=head1 NAME

Cpanel::API::Mysql

=head1 DESCRIPTION

This module contains UAPI methods related to Mysql.

=head1 FUNCTIONS

=cut

use cPstrict;

use Cpanel::AdminBin                 ();
use Cpanel::AdminBin::Call           ();
use Cpanel::DB::Prefix               ();
use Cpanel::DB::Prefix::Conf         ();
use Cpanel::DB::Utils                ();
use Cpanel::Exception                ();
use Cpanel::LoadModule               ();
use Cpanel::MysqlFE                  ();
use Cpanel::MysqlUtils::MyCnf::Basic ();
use Cpanel::Validate::DB::User       ();
use Cpanel::Validate::DB::Name       ();

my $non_mutating = { allow_demo => 1 };
my $mutating     = {};

our %API = (
    _needs_role                => 'MySQLClient',
    _needs_feature             => 'mysql',
    add_host                   => $mutating,
    add_host_note              => $mutating,
    check_database             => $mutating,
    create_database            => $mutating,
    create_user                => $mutating,
    delete_database            => $mutating,
    delete_host                => $mutating,
    delete_user                => $mutating,
    dump_database_schema       => $non_mutating,
    get_host_notes             => $non_mutating,
    get_privileges_on_database => $non_mutating,
    get_restrictions           => $non_mutating,
    get_server_information     => $non_mutating,
    list_databases             => $non_mutating,
    list_routines              => $non_mutating,
    list_users                 => $non_mutating,
    locate_server              => $non_mutating,
    rename_database            => $mutating,
    rename_user                => $mutating,
    repair_database            => $mutating,
    revoke_access_to_database  => $mutating,
    set_password               => $mutating,
    set_privileges_on_database => $mutating,
    update_privileges          => $mutating,
);

sub _cpanel_user {
    return $Cpanel::user;
}

sub get_restrictions {
    my ( $args, $result ) = @_;

    my $prefix;
    if ( Cpanel::DB::Prefix::Conf::use_prefix() ) {
        $prefix = Cpanel::DB::Prefix::username_to_prefix( _cpanel_user() ) . '_';
    }

    $result->data(
        {
            prefix                   => $prefix,
            max_database_name_length => $Cpanel::Validate::DB::Name::max_mysql_dbname_length,
            max_username_length      => Cpanel::Validate::DB::User::get_max_mysql_dbuser_length(),
        }
    );

    return 1;
}

#params (optional):
# prefix
#
sub setup_db_and_user ( $args, $result ) {
    my $prefix = $args->get('prefix') // '';

    my ( $db_name, $db_user, $db_password, $host, $port ) = Cpanel::AdminBin::Call::call( 'Cpanel', 'mysql', 'SETUP_DATABASE_AND_USER', $prefix );

    return $result->data(
        {
            "database"               => $db_name,
            "database_user"          => $db_user,
            "database_user_password" => $db_password,
            "hostname"               => $host,
            "port"                   => $port,
        }
    );
}

#params:
#   name
#
sub create_database {
    my ($args) = @_;

    my $prefixsize = _handle_prefixsize_arg( $args->get('prefix-size') );
    Cpanel::AdminBin::Call::call( 'Cpanel', 'mysql', 'CREATE_DATABASE', $args->get_length_required('name'), $prefixsize );

    return 1;
}

#params:
#   name
#
sub delete_database {
    my ($args) = @_;

    Cpanel::AdminBin::Call::call( 'Cpanel', 'mysql', 'DELETE_DATABASE', $args->get_length_required('name') );

    return 1;
}

#params:
#   name
#
sub check_database {
    my ( $args, $result ) = @_;

    return _maintain_db( $args, $result, 'CHECK_DATABASE' );
}

#params:
#   name
#
sub repair_database {
    my ( $args, $result ) = @_;

    return _maintain_db( $args, $result, 'REPAIR_DATABASE' );
}

sub _maintain_db {
    my ( $args, $result, $op ) = @_;

    my @res = Cpanel::AdminBin::Call::call( 'Cpanel', 'mysql', $op, $args->get_length_required('name') );

    for my $r (@res) {
        my %named_r;
        @named_r{qw(table  msg_type  msg_text)} = @$r;
        $r = \%named_r;
    }

    $result->data( \@res );

    return 1;
}

#params:
#   name
#   password
#
sub create_user {
    my ($args) = @_;

    my $prefixsize = _handle_prefixsize_arg( $args->get('prefix-size') );
    Cpanel::AdminBin::Call::call( 'Cpanel', 'mysql', 'CREATE_USER', $args->get_length_required( 'name', 'password' ), $prefixsize );

    return 1;
}

#params:
#   name
#
sub delete_user {
    my ($args) = @_;

    _adminrun_or_die( 'DELUSER', $args->get_length_required('name') );

    return 1;
}

#params:
#   user
#   database
#   privileges  (optional, comma-separated)
#
sub set_privileges_on_database {
    my ( $args, $result ) = @_;

    my ($privs) = $args->get('privileges');

    if ( !defined $privs ) {
        $privs = q<>;
    }

    _db_privs_logic(
        $args,
        $result,
        'SET_USER_PRIVILEGES_ON_DATABASE',
        [ split( m<,>, $privs ) ],
    );

    return 1;
}

#params:
#   user
#   database
#
sub get_privileges_on_database {
    my ( $args, $result ) = @_;

    my @privs = _db_privs_logic( $args, $result, 'GET_USER_PRIVILEGES_ON_DATABASE' );

    $result->data( [ sort @privs ] );

    return 1;
}

sub _db_privs_logic {
    my ( $args, $result, $admin_func, @admin_args ) = @_;

    my ( $user, $db ) = $args->get_length_required(qw(user database));

    return Cpanel::AdminBin::Call::call(
        'Cpanel',
        'mysql',
        $admin_func,
        $user,
        $db,
        @admin_args,
    );
}

#params:
#   user
#   database
#
sub revoke_access_to_database {
    my ( $args, $result ) = @_;

    _db_privs_logic(
        $args,
        $result,
        'REVOKE_USER_ACCESS_TO_DATABASE',
    );

    return 1;
}

#params:
#   user
#   password
#
sub set_password {
    my ( $args, $result ) = @_;

    my ( $user, $pw ) = $args->get_length_required(qw(user password));

    $result->data( Cpanel::AdminBin::Call::call( 'Cpanel', 'mysql', 'SET_PASSWORD', $user, $pw ) );

    return 1;
}

#params:
#   oldname
#   newname
#
sub rename_user {
    my ( $args, $result ) = @_;

    # We allow the old name to contain these characters so that people can
    # rename themselves out of a hole.  Throws an exception on error.
    Cpanel::Validate::DB::User::verify_mysql_dbuser_name( $args->get_length_required('newname') );

    _do_admin_rename( $args, $result, 'RENAME_USER' );

    return 1;
}

#params:
#   oldname
#   newname
#
sub rename_database {
    my ( $args, $result ) = @_;

    # We allow the old name to contain these characters so that people can
    # rename themselves out of a hole.  Throws an exception on error.
    #
    # XXX: This doesn’t work unless we have root privileges because of the
    # need to know the MySQL version.
    #Cpanel::Validate::DB::Name::verify_mysql_database_name( $args->get_length_required('newname') );

    my $why_not_valid = Cpanel::AdminBin::Call::call( 'Cpanel', 'mysql', 'REASON_WHY_DB_NAME_IS_INVALID', $args->get_length_required('newname') );
    die $why_not_valid if $why_not_valid;

    my $payload = _do_admin_rename( $args, $result, 'RENAME_DATABASE' );

    return 1;
}

#params:
#   host
#
sub add_host {
    my ($args)   = @_;
    my ($host)   = $args->get_length_required('host');
    my $adminrun = _adminrun_or_die( 'ADDHOST', $host );
    return 1;
}

#params:
#   host
#
sub delete_host {
    my ($args) = @_;
    my ($host) = $args->get_length_required('host');

    if ( $host eq 'localhost' ) {
        die Cpanel::Exception::create( 'InvalidParameter', 'You cannot remove the entry for “localhost”.' );
    }

    my $adminrun = _adminrun_or_die( 'DELHOST', $host );
    return 1;
}

#returns:
#   remote_host: the host on which your MySQL server lives
#   is_remote
#
sub locate_server {
    my ( $args, $result ) = @_;
    my $host = _adminrun_or_die('GETHOST');
    $result->data(
        {
            'remote_host' => $host->{'data'},
            'is_remote'   => Cpanel::MysqlUtils::MyCnf::Basic::is_remote_mysql( $host->{'data'} )
        }
    );
    return 1;
}

sub get_server_information {
    my ( $args, $result ) = @_;

    Cpanel::LoadModule::load_perl_module('Cpanel::Mysql::Version');
    $result->data( Cpanel::Mysql::Version::get_server_information() );

    return 1;
}

#params:
#   host: the host for the MySQL server
#   note: a short (<256 character, will be truncated by database) note
#         describing the host
#
sub add_host_note {
    my ( $args, $result ) = @_;
    my $host = $args->get_length_required('host');
    my $note = $args->get_required('note');

    Cpanel::AdminBin::Call::call( 'Cpanel', 'mysql', 'ADD_HOST_NOTE', $host, $note );

    return 1;
}

#returns:
#   hash with hosts as keys and notes as values
#
sub get_host_notes {
    my ( $args, $result ) = @_;

    $result->data( Cpanel::AdminBin::Call::call( 'Cpanel', 'mysql', 'GET_HOST_NOTES' ) );

    return 1;
}

#----------------------------------------------------------------------

=head2 dump_database_schema

L<https://go.cpanel.net/dump_database_schema>

=cut

sub dump_database_schema {
    my ( $args, $result ) = @_;

    my $dbname = $args->get_length_required('dbname');

    require Cpanel::DB::Map::Reader;
    my $rdr = Cpanel::DB::Map::Reader->new(
        cpuser => $Cpanel::user,
        engine => 'mysql',
    );

    if ( !$rdr->database_exists($dbname) ) {
        die Cpanel::Exception::create( 'Database::DatabaseNotFound', [ name => $dbname, engine => 'mysql' ] );
    }

    $result->data( Cpanel::AdminBin::Call::call( 'Cpanel', 'mysql', 'DUMP_SCHEMA', $dbname ) );

    return 1;
}

#----------------------------------------------------------------------

=head2 list_databases

Provides a list of all databases available to the current cPanel user.

=head3 RETURNS

On success, the method returns an array of hashes in the data field one hash per database.

The hash for each database has the following format:

=over

=item database - string

The database name

=item users - string[]

List of databases user names that have some kind of access to this database.

=item disk_usage - integer

Disk usage in bytes

=back

=head3 EXCEPTIONS

=over

=item When you can not connect to the MySql server.

=item When the cpanel account is out of diskspace.

=item Possibly others.

=back

=head3 EXAMPLES

=head4 Command line usage

    uapi --user=cpuser --output=jsonpretty Mysql list_databases

The returned data will contain a structure similar to the JSON below:

    "data" : [
       {
          "users" : [
             "cpuser_mrsuccess",
             "cpuser_megabucks"
          ],
          "database" : "cpuser_mega_bucks",
          "disk_usage" : 172800,
       },
       {
          "database" : "cpuser_secret_recipes",
          "users" : [
             "cpuser_alfonso"
          ],
          "disk_usage: 0,
       }
    ]

=head4 Command line usage limit to specific columns

    uapi --user=cpusr --output=jsonpretty Mysql list_databases api.columns_1=database api.columns_1=disk_usage

The returned data will contain a structure similar to the JSON below:

    "data" : [
       {
          "database" : "cpuser_mega_bucks",
          "disk_usage" : 172800,
       },
       {
          "database" : "cpuser_secret_recipes",
          "disk_usage: 0,
       }
    ]

Note, by limiting the columns you can increase the performance of the API since it does not
have to gather the more expensive data for certain columns.

=head4 Template Toolkit - Get all databases

    [%
    SET result = execute('Mysql', 'list_databases');
    IF result.status;
        FOREACH item IN result.data %]
        Database: [% item.database %]
        Users:
        [% FOREACH user in item.users %]
          * [% user %]
        [% END %]
        Disk Usage (Bytes): [% item.disk_usage %]
        [% END %]
    [% END %]

=head4 Template Toolkit - Get a page of database

    [%
    SET result = execute('Mysql', 'list_databases', {
        'api.paginate_size'  => 10,
        'api.paginate_start' => 0,
    });
    %]
    ...

=head4 Template Toolkit - Get a database that match a filter

    [%
    SET result = execute('Mysql', 'list_databases', {
        'api.filter_column'  => '*',
        'api.filter_type'    => 'contains',
        'api.filter_term'    => 'mine',
    });
    %]
    ...

=head4 Template Toolkit - Get all the databases, but don't request the expensive columns.

    [%
    SET result = execute('Mysql', 'list_databases', {
        'api.columns_1' => 'database'
    });
    IF result.status;
        FOREACH item IN result.data %]
        [% item.database %]
        [% END %]
    [% END %]

Note, by limiting the columns you can increase the performance of the API since it does not
have to gather the more expensive data for certain columns.

=cut

sub list_databases {
    my ( $args, $result ) = @_;

    # Figure out what expensive stuff is needed
    my $include_diskusage = $args->has_column('disk_usage');
    my $include_users     = $args->has_column('users');

    # Gather the various parts of the data
    my @databases;
    my $disk_usage = {};
    my %users_by_database;

    if ($include_diskusage) {
        $disk_usage = Cpanel::AdminBin::Call::call( 'Cpanel', 'mysql', 'GET_DISK_USAGE' );
        @databases  = keys %{$disk_usage};
    }
    else {
        require Cpanel::MysqlFE::DB;
        my %dbs = Cpanel::MysqlFE::DB::listdbs();
        @databases = keys %dbs;
    }

    if ($include_users) {
        %users_by_database = Cpanel::MysqlFE::_listusersinalldbs();
    }

    # Build the response
    my @response;
    foreach my $database ( sort @databases ) {
        my $usage = $disk_usage->{$database};
        $usage = defined $usage ? $usage + 0 : 0;
        push(
            @response,
            {
                database => $database,
                ( $include_users     ? ( users      => ( $users_by_database{$database} || [] ) ) : () ),
                ( $include_diskusage ? ( disk_usage => $usage )                                  : () ),
            }
        );
    }

    $result->data( \@response );

    return 1;
}

=head2 list_users

Provides a list of all database users available to the current cPanel user.

=head3 RETURNS

On success, the method returns an array of hashes in the data field one hash per database user.

The hash for each user has the following format:

=over

=item user - string

Full user name.

=item shortuser - string

Username without the added prefix.

=item databases - string[]

List of database names associated with the user

=back

=head3 EXCEPTIONS

=over

=item When you can not connect to the MySql server.

=item When the cPanel account is out of diskspace.

=item Possibly others.

=back

=head3 EXAMPLES

=head4 Command line usage

    uapi --user=cpuser Mysql list_users --output=jsonpretty

The returned data will contain a structure similar to this JSON:

    "data" : [
         {
            "databases" : [
               "cpuser_db1",
               "cpuser_db2"
            ],
            "user" : "cpuser_user1",
            "shortuser" : "user1"
         },
         {
            "databases" : [
               "cpuser_db2",
               "cpuser_db3"
            ],
            "shortuser" : "user2",
            "user" : "cpuser_user2"
         }
      ],

=head4 Template Toolkit

    [%
    SET result = execute('Mysql', 'list_users');
    IF result.status;
        FOREACH item IN result.data %]
        <h1>[% item.shortuser %]</h1>
        <h2>Databases:</h2>
        <ul>
        [% FOREACH database IN item.databases %]
            <li>[% database %]</li>
        [% END %]
        </ul>
        [% END %]
    [% END %]

=cut

sub list_users {
    my ( $args, $result ) = @_;
    my @users = Cpanel::MysqlFE::_listusers();

    # Map of databases -> users list.
    my %db_to_user = Cpanel::MysqlFE::_listusersinalldbs();
    my $dbowner    = Cpanel::DB::Utils::username_to_dbowner($Cpanel::user);

    # Create a user -> databases list map.
    my %user_to_db;
    foreach my $db ( sort keys %db_to_user ) {
        foreach my $user ( @{ $db_to_user{$db} } ) {
            push( @{ $user_to_db{$user} }, $db );
        }
    }

    # Build a complete list of users where each user includes
    # a list of the database they can access.
    my @ul;
    foreach my $user ( sort @users ) {
        my @databases;
        if ( ref( $user_to_db{$user} ) eq 'ARRAY' ) {
            foreach my $database ( @{ $user_to_db{$user} } ) {
                push( @databases, $database );
            }
        }

        my $shortuser = $user;
        $shortuser =~ s/^\Q$dbowner\E_//g;
        push @ul, {
            user      => $user,
            shortuser => $shortuser,
            databases => \@databases,
        };
    }

    $result->data( \@ul );

    return 1;
}

=head2 update_privileges

Update privileges for all users and databases, including active sessions.

=head3 EXCEPTIONS

=over

=item When you can not connect to the MySql server.

=item Possibly others.

=back

=head3 EXAMPLES

=head4 Command line usage

    uapi --user=cpuser Mysql update_privileges

=head4 Template Toolkit

    [%
        SET result = execute('Mysql', 'update_privilges');
        IF result.status;
          # everything was updated
        ELSE;
          # failed, output the errors.
          USE Dumper;
          Dumper.dump(result.errors);
        END;
    %]

=cut

sub update_privileges {
    my ( $args, $result ) = @_;
    _adminrun_or_die("UPDATEPRIVS");
    return 1;
}

=head2 list_routines

Provides a list of the database routines available to the cPanel account.

If the database_user argument is provided, this function will only return the database routines accessible by the specific user.

=head3 ARGUMENTS

=over

=item database_user - string - OPTIONAL

Valid database user. When passed, only routines available to that user are returned.

=back

=head3 RETURNS

string[] - The list of routines prefixed with the database name they are associated with.

=head3 EXCEPTIONS

=over

=item When you can not connect to the MySql server.

=item Possibly others.

=back

=head3 EXAMPLES

=head4 Command line usage: Get all routines for the current cPanel account.

    uapi --user=cpuser Mysql list_routines --output=jsonpretty

On success, the result will contain a structure similar to the below (as JSON):

    "data" : [
         "user_table_name.routine1",
         "user_table_name.routine2"
     ]

=head4 Command line usage: Get routines for the current cPanel account that are accessible by the specified database user.

    uapi --user=cpuser Mysql list_routines database_user=username --output=jsonpretty

=head4 Template Toolkit

    [%
        SET result = execute('Mysql', 'list_routines');
        IF result.status;
            FOREACH routine IN result.data;
    %]
            <h3>[% routine %]</h3>
            ...
    [%      END;
        END;
    %]
=cut

sub list_routines {
    my ( $args, $result ) = @_;

    my $routines = Cpanel::AdminBin::Call::call( 'Cpanel', 'mysql', 'LIST_ROUTINES', $args->get('database_user') );

    $result->data($routines);

    return 1;
}

#----------------------------------------------------------------------

sub _handle_prefixsize_arg ( $size = undef ) {

    return '16' unless length $size;

    my $allowed_prefix_sizes = [ '8', '16' ];

    if ( !grep { $size eq $_ } @$allowed_prefix_sizes ) {
        require Cpanel::Locale;
        my $lh = Cpanel::Locale->get_handle();
        die Cpanel::Exception::create( 'InvalidParameter', $lh->maketext( 'Database prefix size can only be the values [list_or_quoted,_1].', $allowed_prefix_sizes ) );
    }

    return $size;
}

sub _do_admin_rename {
    my ( $args, $result, $admin_func ) = @_;

    my ( $oldname, $newname ) = $args->get_length_required(qw(oldname newname));

    #"courtesy" validation. The admin backend will still bug out without this,
    #but the error message is "scarier".
    if ( $newname eq $oldname ) {
        die Cpanel::Exception::create( 'InvalidParameter', 'The “[_1]” and “[_2]” parameters cannot be the same value.', [qw(oldname newname)] );
    }

    return Cpanel::AdminBin::Call::call( 'Cpanel', 'mysql', $admin_func, $oldname, $newname );
}

#Args go to Cpanel::AdminBin::run_adminbin_with_status( 'cpmysql', ...).
sub _adminrun_or_die {
    my @args = @_;

    my $adminrun = Cpanel::AdminBin::run_adminbin_with_status( 'cpmysql', @args );

    if ( !$adminrun->{'status'} ) {
        chomp @{$adminrun}{qw( error statusmsg )};
        die Cpanel::Exception->create_raw( $adminrun->{'error'} || $adminrun->{'statusmsg'} );
    }

    return $adminrun;
}

1;
