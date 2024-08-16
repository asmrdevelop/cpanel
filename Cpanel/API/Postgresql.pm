package Cpanel::API::Postgresql;

# cpanel - Cpanel/API/Postgresql.pm                Copyright 2022 cPanel, L.L.C.
#                                                           All rights reserved.
# copyright@cpanel.net                                         http://cpanel.net
# This code is subject to the cPanel license. Unauthorized copying is prohibited

use strict;
use warnings;

=head1 MODULE

C<Cpanel::API::Postgres>

=head1 DESCRIPTION

C<Cpanel::API::Postgres> provides APIs related to managing PostgreSQL databases in
the product.

=head1 SYNOPSIS

  use Cpanel::API::Postgresql ();
  use Cpanel::Args            ();
  use Cpanel::Result          ();

  my $args = Cpanel::Args->new({ name => 'cpuser_dbuser1' });
  my $result = Cpanel::Result->new();

  my $status = eval { Cpanel::API::Postgresql::delete_user($args, $result) };
  if (my $exception = $@) {
    # failed
  } else {
    # success
  }

  $args = Cpanel::Args->new();
  $result = Cpanel::Result->new();

  $status = eval { Cpanel::API::Postgreslq::list_users($args, $result)};
  if (my $exception = $@) {
    # failed
  } else {
    # success
    foreach my $user ( $result->data() ) {
        # do something with the user.
    }
  }

=cut

use Cpanel::AdminBin           ();
use Cpanel::AdminBin::Call     ();
use Cpanel::DB::Prefix         ();
use Cpanel::DB::Prefix::Conf   ();
use Cpanel::Exception          ();
use Cpanel::Postgres           ();
use Capture::Tiny              ();
use Cpanel::Validate::DB::Name ();
use Cpanel::Validate::DB::User ();

=head1 GLOBALS

=head2 C<%API> - hash

API access rules for the module.

=cut

my $allow_demo = { allow_demo => 1 };

our %API = (
    _needs_role             => 'PostgresClient',
    _needs_feature          => 'postgres',
    get_restrictions        => $allow_demo,
    create_database         => {},
    delete_database         => {},
    create_user             => {},
    rename_user             => {},
    rename_database         => {},
    set_password            => {},
    grant_all_privileges    => {},
    update_privileges       => {},
    revoke_all_privileges   => {},
    rename_user_no_password => {},
    list_databases          => $allow_demo,
    list_users              => $allow_demo,
    delete_user             => {},
);

=head1 FUNCTIONS

=head2 list_databases

Provides a list of all databases available to the current cPanel user.

=head3 RETURNS

On success, the method returns an array of hashes in the data field, one hash per database.

The hash for each database has the following format:

=over

=item database - string

The database name.

=item users - string[]

List of databases user names that have some kind of access to this database.

=item disk_usage - integer

Disk usage in bytes.

=back

=head3 EXCEPTIONS

=over

=item When you cannot connect to the PostgreSQL server.

=item When the cPanel account is out of disk space.

=item Possibly others.

=back

=head3 EXAMPLES

=head4 Command line usage

    uapi --user=cpuser --output=jsonpretty Postgresql list_databases

The returned data will contain a structure similar to the JSON below:

    "data" : [
       {
          "users" : [
             "cpuser_mrsuccess",
             "cpuser_megabucks"
          ],
          "database" : "cpuser_gis_polygons",
          "disk_usage" : 172800,
       },
       {
          "database" : "cpuser_gis_points",
          "users" : [
             "cpuser_alfonso"
          ],
          "disk_usage: 0,
       }
    ]

=head4 Template Toolkit - Get all databases

    [%
    SET result = execute('Postgresql', 'list_databases');
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
    SET result = execute('Postgresql', 'list_databases', {
        'api.paginate_size'  => 10,
        'api.paginate_start' => 0,
    });
    %]
    ...

=head4 Template Toolkit - Get a database that match a filter

    [%
    SET result = execute('Postgresql', 'list_databases', {
        'api.filter_column'  => '*',
        'api.filter_type'    => 'contains',
        'api.filter_term'    => 'mine',
    });
    %]
    ...

=head4 Template Toolkit - Get all the databases, but don't request the expensive columns.

    [%
    SET result = execute('Postgresql', 'list_databases', {
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

    Cpanel::Postgres::Postgres_initcache();

    my ( $stdout, $stderr, $data ) = Capture::Tiny::capture {
        return Cpanel::Postgres::list_databases(
            {
                'users' => $args->has_column('users'),
                'usage' => $args->has_column('disk_usage')
            }
        )
    };

    die Cpanel::Exception->create("The system failed to retrieve the database list.") if $stderr;
    $result->data($data);

    return 1;
}

=head2 list_users()

List the PostgreSQL user for this account.

=head3 RETURNS

Arrayref of strings - each string is the name of an existing PostgreSQL user.

=head3 EXAMPLES

=head4 Command line usage

    uapi --user=cpuser --output=jsonpretty Postgresql list_users

=head4 Template Toolkit

    [% SET result = execute('Postgresql', 'list_users', {}) %]
    [% IF result.status %]
    Available Users:
    [% FOR user IN result.data %]
    * [% user %]
    [% END %]
    [% ELSE %]
    Could not list PostgreSQL user with the following error: [% result.errors.item(0) %]
    [% END %]

=cut

sub list_users {
    my ( $args, $result ) = @_;
    Cpanel::Postgres::Postgres_initcache();
    my @users = Cpanel::Postgres::_listusers();
    $result->data( [ sort @users ] );
    return 1;
}

=head2 update_privileges()

Syncronize PostgreSQL grants.

=head3 RETURNS

    Does not return data.

=head3 EXAMPLES

=head4 Command line usage

    uapi --user=cpuser --output=jsonpretty Postgresql update_privileges

=head4 Template Toolkit

    [% SET result = execute('Postgresql', 'update_privileges', {}) %]
    [% IF result.status %]
        Success
    [% ELSE %]
    Error: [% result.errors.item(0) %]
    [% END %]

=cut

sub update_privileges {
    my ( $args, $result ) = @_;
    _is_server_running_or_die();
    _run_adminbin_or_die( 'postgres', 'UPDATEPRIVS' );
    return 1;
}

=head2 delete_user(name => ...)

Delete a PostgreSQL user owned by the current cPanel user.

=head3 ARGUMENTS

=over

=item name - string

The database user you want to delete.

=back

=head3 THROWS

=over

=item When the user is not provided.

=item When the Postgres service is not running.

=item When the user does not exists.

=item When the user does not belong to the cPanel user.

=item Possibly other less common exceptions.

=back

=head3 EXAMPLES

=head4 Command line usage

    uapi --user=cpuser --output=jsonpretty Postgresql delete_user name=cpuser_dbuser1

=head4 Template Toolkit

    [%
    SET result = execute('Postgresql', 'delete_user', {
        name => 'cpuser_dbuser1'
    });
    IF result.status; %]
    The user was successfully deleted.
    [% ELSE %]
    Could not delete the user with the following error: [% result.errors.item(0) %]
    [% END %]

=cut

sub delete_user {
    my ( $args, $result ) = @_;

    my $user = $args->get_length_required('name');
    _is_server_running_or_die();
    _run_adminbin_or_die( 'postgres', 'DELUSER', $user );

    return 1;
}

sub get_restrictions {
    my ( $args, $result ) = @_;

    my $prefix;
    if ( Cpanel::DB::Prefix::Conf::use_prefix() ) {
        $prefix = Cpanel::DB::Prefix::username_to_prefix($Cpanel::user) . '_';
    }

    $result->data(
        {
            prefix                   => $prefix,
            max_database_name_length => $Cpanel::Validate::DB::Name::max_pgsql_dbname_length,
            max_username_length      => $Cpanel::Validate::DB::User::max_pgsql_dbuser_length,
        }
    );

    return 1;
}

#params:
#   name
#
sub create_database {
    my ($args) = @_;

    my $name = $args->get_length_required('name');
    if ( Cpanel::DB::Prefix::Conf::use_prefix() ) {
        $name = Cpanel::DB::Prefix::add_prefix_if_name_needs( $Cpanel::user, $name );
    }
    Cpanel::AdminBin::Call::call( 'Cpanel', 'postgresql', 'CREATE_DATABASE', $name );

    return 1;
}

#params:
#   name
#
sub delete_database {
    my ($args) = @_;

    Cpanel::AdminBin::Call::call( 'Cpanel', 'postgresql', 'DELETE_DATABASE', $args->get_length_required('name') );

    return 1;
}

#params:
#   name
#   password
#
sub create_user {
    my ($args) = @_;

    my ( $name, $password ) = $args->get_length_required(qw(name password));
    if ( Cpanel::DB::Prefix::Conf::use_prefix() ) {
        $name = Cpanel::DB::Prefix::add_prefix_if_name_needs( $Cpanel::user, $name );
    }
    Cpanel::AdminBin::Call::call( 'Cpanel', 'postgresql', 'CREATE_USER', $name, $password );

    return 1;
}

#params:
#   oldname
#   newname
#   password
#
sub rename_user {
    my ( $args, $result ) = @_;

    # We allow the old name to contain these characters so that people can
    # rename themselves out of a hole.  Throws an exception on error.
    Cpanel::Validate::DB::User::verify_pgsql_dbuser_name( $args->get_length_required('newname') );

    return _do_admin_rename( $args, $result, 'RENAME_USER', 'password' );
}

#params:
#   oldname
#   newname
#
sub rename_database {
    my ( $args, $result ) = @_;

    # We allow the old name to contain these characters so that people can
    # rename themselves out of a hole.  Throws an exception on error.
    Cpanel::Validate::DB::Name::verify_pgsql_database_name( $args->get_length_required('newname') );

    return _do_admin_rename( $args, $result, 'RENAME_DATABASE' );
}

#params:
#   user
#   password
#
sub set_password {
    my ($args) = @_;

    my ( $user, $pw ) = $args->get_length_required(qw(user password));

    Cpanel::AdminBin::Call::call( 'Cpanel', 'postgresql', 'SET_PASSWORD', $user, $pw );

    return 1;
}

#params:
#   user
#   database
sub grant_all_privileges {
    my ($args) = @_;

    Cpanel::AdminBin::Call::call(
        'Cpanel',
        'postgresql',
        'GRANT_ALL_PRIVILEGES_ON_DATABASE_TO_USER',
        $args->get_length_required(qw(database user)),
    );

    return 1;
}

#params:
#   user
#   database
sub revoke_all_privileges {
    my ($args) = @_;

    Cpanel::AdminBin::Call::call(
        'Cpanel',
        'postgresql',
        'REVOKE_ALL_PRIVILEGES_ON_DATABASE_FROM_USER',
        $args->get_length_required(qw(database user)),
    );

    return 1;
}

#----------------------------------------------------------------------

#params:
#   oldname
#   newname
#
#NOTE: Avoid this call unless it is absolutely necessary since it WILL
#lock the DB user out until it gets a new password!
#
sub rename_user_no_password {
    my ( $args, $result ) = @_;

    return _do_admin_rename( $args, $result, 'RENAME_USER_NO_PASSWORD' );
}

#----------------------------------------------------------------------

=head2 _is_server_running() [PRIVATE]

Checks if the PostgreSQL server is installed and running.

=head3 RETURNS

1 if the server is installed and running, 0 otherwise.

=cut

sub _is_server_running {
    return Cpanel::AdminBin::adminrun( 'postgres', 'PING' ) ? 1 : 0;
}

=head2 _is_server_running_or_die() [PRIVATE]

Checks if the PostgreSQL server is installed and running.

=head3 THROWS

=over

=item When the PostgreSQL service can not be reached.

=back

=cut

sub _is_server_running_or_die {
    Cpanel::Exception->create('The [asis,PostgreSQL] server is currently offline.') if !_is_server_running();
    return;
}

=head2 _run_adminbin_or_die(MODULE, METHOD, ARGS) [PRIVATE]

=head3 ARGUMENTS

=over

=item MODULE - string

Adminbin module name.

=item METHOD - string

Method name to call.

=item ARGS - list

Additional arguments for the adminbin call.

=back

=head3 THROWS

=over

=item When the adminbin reports a failure

=back

=cut

sub _run_adminbin_or_die {
    my ( $module, $method, @args ) = @_;

    # Using Capture::Tiny to suppress the logger warn() from
    # run_adminbin_with_status() call when called from the CLI.
    Capture::Tiny::capture {
        my $adminrun = Cpanel::AdminBin::run_adminbin_with_status( $module, $method, @args );
        if ( !$adminrun->{status} ) {
            chomp @{$adminrun}{qw( error statusmsg )};
            die Cpanel::Exception->create_raw( $adminrun->{'error'} || $adminrun->{'statusmsg'} );
        }
    };
    return 1;
}

sub _do_admin_rename {
    my ( $args, $result, $admin_func, @extra_keys ) = @_;

    my ( $oldname, $newname, @extra ) = $args->get_length_required( qw(oldname newname), @extra_keys );

    #"courtesy" validation. The admin backend will still bug out without this,
    #but the error message is "scarier".
    if ( $newname eq $oldname ) {
        die Cpanel::Exception::create( 'InvalidParameter', 'The “[_1]” and “[_2]” parameters cannot be the same value.', [qw(oldname newname)] );
    }

    Cpanel::AdminBin::Call::call( 'Cpanel', 'postgresql', $admin_func, $oldname, $newname, @extra );

    return 1;
}

1;
