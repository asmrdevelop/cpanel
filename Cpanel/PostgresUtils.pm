package Cpanel::PostgresUtils;

# cpanel - Cpanel/PostgresUtils.pm                 Copyright 2022 cPanel, L.L.C.
#                                                           All rights reserved.
# copyright@cpanel.net                                         http://cpanel.net
# This code is subject to the cPanel license. Unauthorized copying is prohibited

use cPstrict;

our $VERSION = 1.0;

use Cpanel::LoadModule             ();
use Cpanel::Debug                  ();
use Cpanel::PwCache                ();
use Cpanel::DbUtils                ();
use Cpanel::DB::Map::Reader        ();
use Cpanel::PostgresUtils::PgPass  ();
use Cpanel::PostgresUtils::Quote   ();
use Cpanel::Services::Restart      ();
use Cpanel::Transaction::File::Raw ();

use Path::Tiny ();

our $POSTGRESQL_CONFIG_FILE_PATH = '/var/lib/pgsql/data/postgresql.conf';
our $POSTGRESQL_SOCKET_FILE      = '.s.PGSQL.5432';

*quote              = *Cpanel::PostgresUtils::Quote::quote;
*quote_conninfo     = *Cpanel::PostgresUtils::Quote::quote_conninfo;
*quote_identifier   = *Cpanel::PostgresUtils::Quote::quote_identifier;
*unquote_identifier = *Cpanel::PostgresUtils::Quote::unquote_identifier;
*unquote_e          = *Cpanel::PostgresUtils::Quote::unquote_e;
*getpostgresuser    = *Cpanel::PostgresUtils::PgPass::getpostgresuser;
*find_psql          = *Cpanel::DbUtils::find_psql;
*find_pg_restore    = *Cpanel::DbUtils::find_pg_restore;

# for testing
my ($locale);
our $IDENTIFIER_REGEXP = '(?:"(?:[^"\0]+|"")+"|[^\s\0"]+)';

sub find_pgsql_home {
    my (%args) = @_;

    $args{'user'} ||= getpostgresuser();

    return unless defined $args{'user'};

    my @PATHS = qw(
      /var/lib/pgsql
      /var/lib/pgsql9
      /var/lib/pgsql92
      /usr/local/lib/pgsql
      /opt/local/var/db/postgresql82
    );

    foreach my $path (@PATHS) {
        return $path if -d $path;
    }

    if ( my $home = ( Cpanel::PwCache::getpwnam( $args{'user'} ) )[7] ) {
        return $home if -d $home;
    }

    return;
}

#
# NOTE: We can get this information more reliably by simply
# querying the database: “SHOW data_directory”
#
sub find_pgsql_data {
    my (%args) = @_;

    $args{'home'} ||= find_pgsql_home();

    return unless defined $args{'home'};

    my @SUBDIRS = qw(
      data defaultdb
    );

    foreach my $subdir (@SUBDIRS) {
        my $path = "$args{'home'}/$subdir";

        return $path if -d $path;
    }

    return;
}

sub exec_psql {
    my (@sql) = @_;
    my $psql = Cpanel::DbUtils::find_psql();
    return if !$psql;
    my $pguser = getpostgresuser();
    return if !$pguser;

    my $sql = join( "\n", @sql );

    Cpanel::LoadModule::load_perl_module('Cpanel::SafeRun::Full');
    my $results = Cpanel::SafeRun::Full::run(
        program => $psql,
        args    => [ '-U', $pguser, '-t', 'postgres' ],
        stdin   => $sql,
    );

    return $results;
}

sub listusersindb {
    my ( $cpuser, $dbname ) = @_;
    return if !$cpuser;
    my $pguser = getpostgresuser();
    if ( !$pguser ) {
        return '';
    }

    # This function logs it's failures
    _load_session_temp_module() || return;

    return _get_map($cpuser)->get_dbusers_for_database($dbname);
}

sub listusers {
    my ($cpuser) = @_;
    return if !$cpuser;

    # This function logs its failures
    _load_session_temp_module() || return;

    return _get_map($cpuser)->get_dbusers();
}

sub listdbs {
    my ($cpuser) = @_;
    return if !$cpuser;
    return _get_map($cpuser)->get_databases();
}

sub user_exists {
    my ( $user, $dbh ) = @_;

    Cpanel::LoadModule::load_perl_module('Cpanel::Postgres::Connect');
    $dbh ||= Cpanel::Postgres::Connect::get_dbi_handle();
    my ($count) = $dbh->selectrow_array( 'SELECT COUNT(*) FROM pg_user WHERE usename = ?', undef, $user );
    return $count;
}

sub role_exists {
    my ( $user, $dbh ) = @_;

    Cpanel::LoadModule::load_perl_module('Cpanel::Postgres::Connect');
    $dbh ||= Cpanel::Postgres::Connect::get_dbi_handle();
    my ($count) = $dbh->selectrow_array( 'SELECT COUNT(*) FROM pg_roles WHERE rolname = ?', undef, $user );
    return $count;
}

sub db_exists {
    my ( $dbname, $dbh ) = @_;

    Cpanel::LoadModule::load_perl_module('Cpanel::Postgres::Connect');
    $dbh ||= Cpanel::Postgres::Connect::get_dbi_handle();
    my ($count) = $dbh->selectrow_array( 'SELECT COUNT(*) FROM pg_database WHERE datname = ?', undef, $dbname );
    return $count;
}

sub safesqlstring {
    die "safesqlstring is not backcompat";
}

sub _get_map {
    my ($cpuser) = @_;
    return Cpanel::DB::Map::Reader->new( 'cpuser' => $cpuser, engine => 'postgresql' );
}

sub reload {
    my $user         = shift || getpostgresuser();
    my $user_homedir = find_pgsql_home( 'user' => $user );
    my $datadir      = shift || find_pgsql_data( 'home' => $user_homedir );
    my $pg_ctl       = shift || Cpanel::DbUtils::find_pg_ctl();

    if ( !$user ) {
        Cpanel::Debug::log_warn("Failed to locate PostgreSQL user");
        return;
    }

    if ( !$datadir ) {
        Cpanel::Debug::log_warn("Failed to determine PostgreSQL data directory");
        return;
    }

    if ( !$pg_ctl ) {
        Cpanel::Debug::log_warn("Failed to determine PostgreSQL control application pg_ctl");
        return;
    }

    Cpanel::LoadModule::load_perl_module('Cpanel::SafeRun::Object');
    my $saferun = Cpanel::SafeRun::Object->new(
        'before_exec' => sub {
            require Cpanel::AccessIds::SetUids;
            Cpanel::AccessIds::SetUids::setuids($user);
            chdir($user_homedir);
        },
        'program' => $pg_ctl,
        'args'    => [ '-D', $datadir, 'reload' ],
    );

    if ( $saferun->CHILD_ERROR() ) {
        Cpanel::LoadModule::load_perl_module('Cpanel::Locale');
        $locale ||= Cpanel::Locale->get_handle();
        Cpanel::Debug::log_warn( $locale->maketext('Failed to reload PostgreSQL:') . q{ } . $saferun->autopsy() );
        return;
    }

    return 1;
}

sub get_version {
    my $psql = Cpanel::DbUtils::find_psql();
    if ( !$psql ) {
        my $message = 'Failed to locate postgresql CLI application';
        return wantarray ? ( 0, $message ) : 0;
    }

    Cpanel::LoadModule::load_perl_module('Cpanel::CachedCommand');
    my $psqlversion = Cpanel::CachedCommand::cachedcommand( $psql, '--version' );

    if ( $psqlversion && $psqlversion =~ m/\s(\d+)\.(\d+)/ma ) {
        my $psql_major_ver = $1;
        my $psql_minor_ver = $2;
        return wantarray
          ? ( $psql_major_ver, $psql_minor_ver )
          : $psql_major_ver . '.' . $psql_minor_ver;
    }
    else {
        return wantarray
          ? ( 0, 'Failed to determine postgresql version: ' . $psqlversion )
          : 0;
    }
}

my $QUERY_FOR_DEPENDENT_RESOURCES = q<
    SELECT
        1
    FROM
        pg_shdepend,
        pg_authid
    WHERE
        pg_authid.rolname = ?
        AND pg_shdepend.refobjid = pg_authid.oid
        AND deptype IN ('o','a') /*
            SHARED_DEPENDENCY_OWNER and SHARED_DEPENDENCY_ACL
            cf. http://www.postgresql.org/docs/8.1/static/catalog-pg-shdepend.html
        */
>;

###########################################################################
#
# Method:
#   dependent_items_count
#
# Description:
#   This function returns the number of database resources depending on the supplied role.
#
#     NOTE: This method does not indicate if a role is a member of another role. It only
#           searches for databases, tables, etc that are owned by, or otherwise depend, on
#           the supplied role.
#
# Parameters:
#   $dbh  - A database handle with an active PostgreSQL connection.
#   $role - The role that will be used to search for dependent database objects.
#
# Exceptions:
#   Cpanel::Exception::Database::Error - Thrown if the database query fails.
#
# Returns:
#   This method will return an integer that indicates the number of dependent database
#   resources on the supplied role.
#
sub dependent_items_count {
    my ( $dbh, $role ) = @_;

    my $items_ar = $dbh->selectcol_arrayref(
        $QUERY_FOR_DEPENDENT_RESOURCES,
        {},
        $role,
    );

    return scalar @$items_ar;
}

my %role_db_privileges = qw(
  c   CONNECT
  C   CREATE
  T   TEMPORARY
);

#Returns a data structure representing which roles have direct
#privileges on the given database:
#   [
#       { role => 'role1', privileges => [ ... ] },
#   ]
sub get_db_roles {
    my ( $dbh, $db ) = @_;

    #NOTE: This is not currently needed since we only grant all privs
    #to a user/db combination. But it could be useful later on.
    #table, WHERE clause
    #my @queries = (
    #    [ 'column_privileges' => q{table_schema != 'information_schema' AND table_schema != 'pg_catalog'} ],
    #    [ 'table_privileges' => q{table_schema != 'information_schema' AND table_schema != 'pg_catalog'} ],
    #    [ 'data_type_privileges' => q{object_schema != 'information_schema' AND object_schema != 'pg_catalog'} ],
    #    [ 'routine_privileges' => q{routine_schema != 'information_schema' AND routine_schema != 'pg_catalog'} ],
    #);

    my @roles;

    #It would seem ideal if this could come from information_schema
    #rather than pg_catalog.
    my $acl_ref = $dbh->selectcol_arrayref( 'SELECT datacl from pg_catalog.pg_database WHERE datname = ?', undef, $db );

    my $acls_ar = $acl_ref->[0];

    if ( !ref $acls_ar && $acls_ar =~ m/^{/ ) {

        #{=Tc/postgres,postgres=CTc/postgres,get_db_roles_sql=CTc/postgres}
        $acls_ar =~ s/^{//g;
        $acls_ar =~ s/^}//g;
        $acls_ar = [ split( m{,}, $acls_ar ) ];
    }

    for my $acl (@$acls_ar) {

        #NB: The last part of the ACL is the grantor, but that's
        #not important in this context. (...right?...??)
        my ( $grantee, $privs_str ) = ( $acl =~ m{\A(.*?)=(.*?)/} );

        my @privs = sort map { $role_db_privileges{$_} } split m{}, $privs_str;

        push @roles, { role => $grantee, privileges => \@privs };
    }

    return \@roles;
}

#Returns SQL statements for reproducing all of the roles that currently
#have access on the given database.
sub get_db_roles_sql {
    my ( $dbh, $db ) = @_;

    my $db_q = $dbh->quote_identifier($db);

    my @sql_stmts;

    for my $role_hr ( @{ get_db_roles( $dbh, $db ) } ) {
        my ( $grantee, $privs_ar ) = @{$role_hr}{qw(role privileges)};
        my $grant_privs = join( ', ', @$privs_ar );

        my $grantee_q = length($grantee) ? $dbh->quote_identifier($grantee) : 'PUBLIC';

        push @sql_stmts, "GRANT $grant_privs ON DATABASE $db_q TO $grantee_q";
    }

    return \@sql_stmts;
}

#A data structure that represents what the given role can do;
#i.e., the given role's "memberships in" other roles.
#
#Returns an arrayref of hashrefs: {
#   role_name => '..',
#   grantee => '..',    #always the passed-in role
#   admin_option => 1/0,
#}
sub get_role_memberships {
    my ( $dbh, $role ) = @_;

    return _get_role_relationship( $dbh, $role, 'grantee' );
}

#A data structure that represents which (other) roles can "be" the given role;
#i.e., to which roles the given role is "granted".
#
#Returns an arrayref of hashrefs: {
#   role_name => '..',  #always the passed-in role
#   grantee => '..',
#   admin_option => 1/0,
#}
sub get_role_grantees {
    my ( $dbh, $role ) = @_;

    return _get_role_relationship( $dbh, $role, 'role_name' );
}

#Returns SQL statements for reproducing the roles that the given role can do.
#For example, if $role "john" has grants on "tall" and "awesome", this
#represents that with:
#   [
#       'GRANT "tall" to "john"',
#       'GRANT "awesome" to "john"',
#   ]
sub get_role_memberships_sql {
    my ( $dbh, $role ) = @_;

    return [ map { _convert_role_relationship_to_sql( $dbh, $_ ) } @{ get_role_memberships( $dbh, $role ) } ];
}

#Returns SQL statements for reproducing which roles can "be" the given role.
#For example, if $role "awesome" is granted to "john" and to "dave",
#this represents that with: [
#   [
#       'GRANT "awesome" to "john"',
#       'GRANT "awesome" to "dave"',
#   ]
sub get_role_grantees_sql {
    my ( $dbh, $role ) = @_;

    return _get_role_relationship_sql( $dbh, $role, 'role_name' );
}

#Same as get_role_grantees_sql, but this function recurses in order to get
#every relationship that, either directly or indirectly, grants access to
#the given role.
#
#So, if:
#   role "felipe" has privs to role "coder", and
#   role "coder" has privs to "person"
#
#...then querying this function on "person" will return SQL statements for
#both of the above relationships.
sub get_role_grantees_sql_recursive {
    my ( $dbh, $role ) = @_;

    my %all_roles_lookup;
    _get_role_relationship_recursive( $dbh, $role, 'role_name', \%all_roles_lookup );

    return [ map { _convert_role_relationship_to_sql( $dbh, $_ ) } values %all_roles_lookup ];
}

sub _get_role_relationship_recursive {
    my ( $dbh, $role, $filter_column, $all_roles_hr ) = @_;

    my $new_grants_ar = _get_role_relationship( $dbh, $role, $filter_column );

    for my $new_grant (@$new_grants_ar) {

        #Use null byte as separator because that's the only forbidden character
        #in a PostgreSQL identifier.
        my $lookup_key = join "\x00", @{$new_grant}{ sort keys %$new_grant };

        if ( !exists $all_roles_hr->{$lookup_key} ) {
            $all_roles_hr->{$lookup_key} = $new_grant;
            _get_role_relationship_recursive( $dbh, $new_grant->{'grantee'}, $filter_column, $all_roles_hr );
        }
    }

    return;
}

#Returns an arrayref of hashrefs: {
#   role_name => '..',
#   grantee => '..',
#   admin_option => 1/0,
#}
sub _get_role_relationship {
    my ( $dbh, $role, $filter_column ) = @_;

    my $relations_ar = $dbh->selectall_arrayref( "SELECT role_name, grantee, (CASE WHEN (is_grantable = ?) THEN 1 ELSE 0 END) AS admin_option FROM information_schema.applicable_roles WHERE $filter_column = ?", { Slice => {} }, 'YES', $role );

    return $relations_ar;
}

#Same as _get_role_relationship, but returns actual SQL statements.
sub _get_role_relationship_sql {
    my ( $dbh, $role, $filter_column ) = @_;

    my $relations_ar = _get_role_relationship( $dbh, $role, $filter_column );

    return [ map { _convert_role_relationship_to_sql( $dbh, $_ ) } @$relations_ar ];
}

sub _convert_role_relationship_to_sql {
    my ( $dbh, $rel ) = @_;

    my ( $role_name, $grantee ) = map { $dbh->quote_identifier($_) } @{$rel}{qw(role_name  grantee)};

    my $sql = "GRANT $role_name TO $grantee";

    my $is_grantable = $rel->{'admin_option'};
    if ($is_grantable) {
        $sql .= ' WITH ADMIN OPTION';
    }

    return $sql;
}

=head1 ensure_secure_socket()

This updates postgresql.conf to use the path provided by
get_preferred_socket_path()  as the socket path
for PostGres rather than '/tmp' if necessary.

It returns 0 for failure and 1 for success.

NOTE:  It restarts the service if the socket path is updated.

=cut

sub ensure_secure_socket {
    require Cpanel::Logger;
    my $logger = Cpanel::Logger->new();

    my $pgsql_data = Cpanel::PostgresUtils::find_pgsql_data();
    unless ($pgsql_data) {
        $logger->info('Cpanel::PostgresUtils::ensure_secure_socket:  pgsql data directory not found');
        return 0;
    }

    # This helps to ensure that it is a supported PostGres install
    my $pgsql_user = Cpanel::PostgresUtils::PgPass::getpostgresuser();
    unless ($pgsql_user) {
        $logger->info('Cpanel::PostgresUtils::ensure_secure_socket:  could not determine postgres user');
        return 0;
    }

    _ensure_preferred_socket_path_exists($logger);

    my $trans_obj = eval { Cpanel::Transaction::File::Raw->new( path => "$pgsql_data/postgresql.conf", ownership => [$pgsql_user] ); };
    unless ($trans_obj) {
        $logger->info("Cpanel::PostgresUtils::ensure_secure_socket:  Unable to aquire transaction object:  $@");
        return 0;
    }

    # If the configuration is already set, then update it to point
    # to the new socket path.  At this time, we only support one path
    # so this is intentionally rigid.
    my $postgres_conf_txt_ref = $trans_obj->get_data();
    my @conf                  = split( /\n/, ${$postgres_conf_txt_ref} );
    my $preferred_socket_path = Cpanel::PostgresUtils::get_preferred_socket_path();
    my $pg_socket_option      = Cpanel::PostgresUtils::get_socket_directive();
    my $desired_socket_config = qq[$pg_socket_option = '$preferred_socket_path'];
    my $line_updated          = 0;
    foreach my $line (@conf) {
        if ( $line =~ /^\s*unix_socket_director(?:y|ies)\s*=/ ) {
            return 1 if $line eq $desired_socket_config;    # nothing to do here if it already matches

            $line         = $desired_socket_config;
            $line_updated = 1;
            last;
        }
    }

    # Append the desired socket path if there was not already a configured
    # socket path as that means the default of '/tmp' is in use
    unless ($line_updated) {
        push @conf, $desired_socket_config;
    }

    ${$postgres_conf_txt_ref} = join( "\n", @conf );

    my ( $save_ok, $save_status ) = $trans_obj->save_and_close();
    unless ($save_ok) {
        $logger->info("Cpanel::PostgresUtils::ensure_secure_socket:  Failed to modify postgres conf --  $save_status");
        return 0;
    }

    # Currently, only CL6 is supported
    _update_for_initd_start_system();

    Cpanel::Services::Restart::restartservice('postgresql');
    return 1;
}

=head1 get_socket_file()

This returns the file that Postgres should be using as its socket file.

NOTE:  It does not validate that the file exists or that it is a valid socket

=cut

sub get_socket_file {
    my $socket_directory = Cpanel::PostgresUtils::get_socket_directory();
    return "$socket_directory/$POSTGRESQL_SOCKET_FILE" if $socket_directory;
    return;
}

=head1 get_socket_directory()

This returns the directory that Postgres should be placing its socket file in.

=cut

sub get_socket_directory {
    require Cpanel::PostgresAdmin::Check;
    return unless Cpanel::PostgresAdmin::Check::is_enabled_and_configured();

    my $desired_socket_dir  = Cpanel::PostgresUtils::get_preferred_socket_path();
    my $desired_socket_file = "$desired_socket_dir/$POSTGRESQL_SOCKET_FILE";
    return $desired_socket_dir if -S $desired_socket_file;

    my $socket_directory = Cpanel::PostgresUtils::_get_socket_directory();

    # we only consider '/tmp' if there are no other options
    if ( !$socket_directory ) {
        my $file_owner;

        # Make sure the socket has the expected owner before accepting it since it is in /tmp
        if ( -e "/tmp/$POSTGRESQL_SOCKET_FILE" ) {
            my $uid = ( stat "/tmp/$POSTGRESQL_SOCKET_FILE" )[4];
            $file_owner = ( getpwuid $uid )[0];
        }

        $socket_directory = '/tmp' if ( -S "/tmp/$POSTGRESQL_SOCKET_FILE" && ( $file_owner eq 'postgres' || $file_owner eq 'root' ) );
    }

    return $socket_directory;
}

sub _get_socket_directory {
    return unless -s $POSTGRESQL_CONFIG_FILE_PATH;

    my @lines = Path::Tiny::path($POSTGRESQL_CONFIG_FILE_PATH)->lines();
    chomp(@lines);

    my $socket_directory_candidates;
    foreach my $line (@lines) {
        next unless $line =~ /^\s*unix_socket_director(?:y|ies)\s*=(.*)$/;
        $socket_directory_candidates = $1;
        last if $socket_directory_candidates;
    }

    my $socket_directory;
    my @candidates = split /\s*,\s*/, $socket_directory_candidates if $socket_directory_candidates;
    foreach my $candidate (@candidates) {
        $candidate =~ s/^\s*['"]?//;
        $candidate =~ s/['"]?\s*$//;
        $socket_directory = $candidate unless $candidate =~ m{^(?:/var)?/tmp};
        last if $socket_directory;
    }

    return $socket_directory;
}

=head1 get_preferred_socket_path()

This return the preferred path to use for Postgres' socket file

=cut

sub get_preferred_socket_path {
    return '/var/run/postgresql';
}

=head1 get_socket_directive()

This returns the socket directive to use when configuring the unix
socket directory

=cut

sub get_socket_directive {
    my $pg_version = Cpanel::PostgresUtils::get_version();

    return ( $pg_version >= 9 ) ? 'unix_socket_directories' : 'unix_socket_directory';
}

=head1 _update_for_initd_start_system()

Overwrite '/etc/sysconfig/postgres' with the new socket path

=cut

sub _update_for_initd_start_system {
    my $postgres_sysconfig_file = '/etc/sysconfig/postgres';

    return unless -d '/etc/init.d' && -f $postgres_sysconfig_file;

    my $preferred_socket_path = Cpanel::PostgresUtils::get_preferred_socket_path();
    Path::Tiny::path($postgres_sysconfig_file)->spew("SOCK_DIR=$preferred_socket_path");

    return;
}

=head1 _ensure_preferred_socket_path_exists

Make the directory and ensure it has the correct owner

=cut

sub _ensure_preferred_socket_path_exists {
    my $logger = @_;

    my $pgsql_user = Cpanel::PostgresUtils::PgPass::getpostgresuser();
    unless ($pgsql_user) {
        $logger->info('Cpanel::PostgresUtils::ensure_secure_socket:  could not determine postgres user');
        return 0;
    }

    my $preferred_socket_path = Cpanel::PostgresUtils::get_preferred_socket_path();

    my ( undef, undef, $uid, $gid ) = Cpanel::PwCache::getpwnam($pgsql_user);

    require Cpanel::Autodie;
    Cpanel::Autodie::mkdir_if_not_exists( $preferred_socket_path, 0755 );
    Cpanel::Autodie::chown( $uid, $gid, $preferred_socket_path );

    return 1;
}

1;
