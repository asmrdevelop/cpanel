package Cpanel::PostgresAdmin;

# cpanel - Cpanel/PostgresAdmin.pm                 Copyright 2022 cPanel, L.L.C.
#                                                           All rights reserved.
# copyright@cpanel.net                                         http://cpanel.net
# This code is subject to the cPanel license. Unauthorized copying is prohibited

use cPstrict;

use parent qw(
  Cpanel::PostgresAdmin::Basic
);

use Try::Tiny;

use Cpanel::AccessIds::ReducedPrivileges ();
use Cpanel::Autowarn                     ();
use Cpanel::Config::LoadCpConf           ();
use Cpanel::DB                           ();
use Cpanel::DbUtils                      ();
use Cpanel::DB::Utils                    ();
use Cpanel::Exception                    ();
use Cpanel::LocaleString                 ();
use Cpanel::PasswdStrength::Check        ();
use Cpanel::Postgres::Error              ();
use Cpanel::PostgresUtils                ();
use Cpanel::PostgresUtils::PgPass        ();
use Cpanel::PostgresUtils::Quote         ();
use Cpanel::PwCache                      ();
use Cpanel::Reseller::Override           ();
use Cpanel::ServerTasks                  ();
use Cpanel::Session::Temp::Active        ();
use Cpanel::Validate::DB::Name           ();
use Cpanel::Validate::DB::User           ();

our $VERSION = 1.1;

#START CONSTANTS
our $NO_UPDATE_PRIVS  = 1;
our $SKIP_OWNER_CHECK = 1;

our $HASHED_PASSWORD_PREFIX = 'md5';

#END CONSTANTS

my $REMOTE_PGSQL = 0;    # PAM NOW USED INSTEAD, HOWEVER IF WE SUPPORT REMOTE PGSQL IN THE FUTURE...

#Docs recommend using the "postgres" as a "default" login DB.
my $DEFAULT_LOGIN_DATABASE = 'postgres';

sub _diskusage {
    my $self = shift;

    # Callers that are tallying up disk usage
    # are expected to check for disk_usage_include_sqldbs
    # and not call for diskusage if they do not need it.
    my %DBS    = $self->listdbsbyid();
    my @IDLIST = keys %DBS;
    if ( !@IDLIST ) {
        return wantarray ? () : {};
    }

    my $disk_usage_ref = $self->get_disk_usage_for_dbids( \@IDLIST );
    my %DISKUSAGE;
    foreach my $dbid ( keys %DBS ) {
        my $dbname    = $DBS{$dbid};
        my $diskusage = $disk_usage_ref->{$dbid};
        $DISKUSAGE{$dbname} = $diskusage && int $diskusage;
    }

    return wantarray ? %DISKUSAGE : \%DISKUSAGE;
}

sub get_disk_usage_for_dbids {
    my $self       = shift;
    my $idlist_ref = shift;

    my ($datadir) = $self->{'dbh'}->selectrow_array('SHOW data_directory');
    require Cwd;
    my $basedir = Cwd::abs_path($datadir) . '/base';

    my %DISKUSAGE;
    foreach my $dbid (@$idlist_ref) {
        my $dir = "$basedir/$dbid";

        if ( opendir( DD, $dir ) ) {
            foreach my $file ( grep( !/^\.\.?$/, readdir(DD) ) ) {
                $DISKUSAGE{$dbid} += ( stat( $dir . '/' . $file ) )[12] * 512;
            }
            closedir(DD);
        }
        else {
            warn "Error opening directory “$dir”: $!";
        }
    }
    return \%DISKUSAGE;
}

sub getpostgresdiskusage {
    my $self             = shift;
    my $db_diskusage_ref = $self->_diskusage();
    my $total            = 0;

    # If $db_diskusage_ref isn't a ref then there were no databases
    return $total if !ref $db_diskusage_ref;
    foreach my $db ( keys %$db_diskusage_ref ) {
        $total += $db_diskusage_ref->{$db};
    }
    return $total;
}

sub _purge_connections_to_db {
    my ( $self, $dbname ) = @_;

    $self->disconnect_dbh($dbname);

    return $self->{'dbh'}->purge_connections_to_db($dbname);
}

#This will die() on failure.
sub drop_db {
    my ( $self, $dbname ) = @_;

    my $map = $self->_get_map();

    $self->_verify_db_in_map($dbname);

    my $safe_ident_dbname = $self->escape_pg_identifier($dbname);

    my $safe_dbname = $self->quote($dbname);

    my $results;

    $self->_purge_connections_to_db($dbname);

    # Save the thrown error if the database drop fails
    # Like, if the database had been removed manually
    # We still need to do the rest of the steps to clean up
    # the mapping information
    # And, some of these steps need to happen after dropping the database
    my $drop_query_error = undef;
    try {
        $self->{'dbh'}->do(qq/DROP DATABASE $safe_ident_dbname/);
    }
    catch {
        $drop_query_error = $_;
    };

    delete $self->{'_super_dbhs'}{$dbname};
    delete $self->{'_user_dbhs'}{$dbname};

    # CPANEL-28932: The user's cached value was being deleted for MySQL for
    # years, but not for PostgreSQL here, and that's suddenly causing
    # problems.
    $self->_unlink_user_postgres_db_count();

    unlink( $self->_get_userdatastore_dir() . "/postgres-db-count" );
    $map->{'owner'}->remove_db($dbname);
    $self->_save_map_hash($map);

    # need to remove members
    # remove the user / role associated with the table
    $self->deluser( $dbname, $SKIP_OWNER_CHECK );

    $self->queue_dbstoregrants( { 'deferred_seconds' => 10 } );

    # If we had an error dropping the database, then throw it.
    if ($drop_query_error) {
        die $drop_query_error;
    }

    return $results;
}

sub _get_userdatastore_dir ($self) {
    require Cpanel::UserDatastore;

    return Cpanel::UserDatastore::get_path( $self->{'cpuser'} );
}

# private method adapted from similar method in Cpanel::Mysql
sub _unlink_user_postgres_db_count {
    my ($self) = @_;

    my $privs      = Cpanel::AccessIds::ReducedPrivileges->new( $self->{'cpuser'} );
    my $count_path = Cpanel::PwCache::gethomedir($>) . '/.cpanel/datastore/postgres-db-count';

    Cpanel::Autowarn::unlink($count_path);

    return;
}

#This will actually create a DB role for the "user",
#not just "update privileges".
#
#%opts can be:
#   force_update - skips reseller-override verification
#   user         - the dbuser who will own the DBs
#   db           - optional; if not given, includes all DBs in the map.
sub updateprivs {
    my ( $self, %opts ) = @_;

    my $force_update = $opts{'force_update'};

    my $envpass            = ( ( ( !Cpanel::Reseller::Override::is_overriding() && !$ENV{'WHM50'} ) || $force_update ) && $ENV{'REMOTE_PASSWORD'} ) ? $ENV{'REMOTE_PASSWORD'} : '';    #TEMP_SESSION_SAFE
    my $update_cpanel_user = $envpass                                                                                                               ? 1                       : 0;

    my $map    = $self->_get_map();
    my $dbuser = Cpanel::DB::Utils::username_to_dbowner( $opts{'user'} || $map->{'owner'}->name() );

    if ( $self->{'cpuser'} ne $dbuser ) {
        if ( $self->{'cpuser'} ne 'root' && !$map->{'map'}->user_owns_dbuser( $self->{'cpuser'}, $dbuser ) ) {
            return $self->_log_error_and_output( "You, “[_1]”, are not authorized to update privileges for “[_2]”.", $self->{'cpuser'}, $dbuser );
        }
    }

    if ($update_cpanel_user) {
        $self->passwduser( $dbuser, $envpass, 1 );
    }

    # opts{'db'} is only ever passed from create_db
    # and at this point its already checked.  We can't
    # check it see if its in the map because addusertodb is going
    # to put it in there.
    my @DBS = $opts{db} ? ( $opts{db} ) : $self->listdbs();

    $self->setupdbrole( \@DBS );

    if ( $update_cpanel_user && $dbuser eq $self->{'cpuser'} ) {
        my $safe_ident_dbuser = $self->escape_pg_identifier($dbuser);
        $self->exec_psql( qq/ALTER USER $safe_ident_dbuser WITH PASSWORD ?;/, {}, $envpass );
    }

    my %addusers = ( $dbuser => 0 );

    if ($REMOTE_PGSQL) {
        my $temp_users = Cpanel::Session::Temp::Active::get_all_active_user_temp_sessions( $self->{'cpuser'} );
        if ( $temp_users && @{$temp_users} ) {
            foreach my $temp_user ( @{$temp_users} ) {
                $addusers{ $temp_user->[0] } = 1 if $temp_user->[0];
            }
        }
    }

    $self->addusertodb( \@DBS, \%addusers );

    return;
}

*remove_dbowner_from_all = \&deluser;

sub remove_dbowner_from_all_without_ownership_checks {
    my ( $self, $dbuser ) = @_;
    return $self->deluser( $dbuser, $SKIP_OWNER_CHECK );
}

sub add_dbowner_to_all {
    my ( $self, $user, $pass ) = @_;

    my $map = $self->_get_map();
    if ( $self->user_exists($user) && !$map->{'map'}->user_owns_dbuser( $self->{'cpuser'}, $user ) ) {
        return $self->_log_error_and_output( Cpanel::LocaleString->new( "You, “[_1],” are not authorized to access user “[_2]”", $self->{'cpuser'}, $user ) );
    }

    my @DBS = $self->listdbs();

    if ($pass) {
        my ( $ok, $err ) = $self->_passwduser_without_name_validity_check( $user, $pass, 1 );
        if ( !$ok ) {
            return $self->_log_error_and_output( Cpanel::LocaleString->new( 'The system failed to create a temporary PostgreSQL user “[_1]” because of an error: [_2]', $user, $err ) );
        }

        $self->setupdbrole( \@DBS );
    }

    $self->addusertodb( \@DBS, { $user => 1 } );

    return;
}

#
#  Create a group/role for the database and make sure
#  the group has all privs on the db
#
#  TODO: Teach this function to indicate success or failure.
#
sub setupdbrole {
    my ( $self, $dbs ) = @_;

    $dbs = [$dbs] if !ref $dbs;

    return if !@{$dbs};

    my $map     = $self->_get_map();
    my $dbowner = $map->{'owner'}->name();

    my ( $fetch_roles_status, $roles_ref ) = $self->fetch_roles($dbs);

    my %uniq_users     = map { $_ => undef } ( $map->{'owner'}->name(), $self->listusers() );
    my $safe_user_list = join( ',', map { $self->quote($_) } keys %uniq_users );

  DBNAME:
    foreach my $dbname ( @{$dbs} ) {
        my $dbname_quoted = $self->escape_pg_identifier($dbname);

        my @cmds;
        if ( !$fetch_roles_status || !$roles_ref->{$dbname} ) {

            # 1/ create a role if needed -- This is a GROUP since it is NOLOGIN
            push @cmds, qq{CREATE ROLE $dbname_quoted NOLOGIN};
        }

        # 2/ this role (group) has full control on db
        push @cmds, qq{GRANT ALL PRIVILEGES on DATABASE $dbname_quoted TO $dbname_quoted;};

        for my $cmd (@cmds) {
            $self->exec_psql($cmd) or next DBNAME;
        }

        my $ret = $self->exec_psql_on_database(
            $dbname,
            qq{SELECT schemaname, tablename
          FROM pg_tables
          WHERE tableowner IN ($safe_user_list) OR schemaname='public';}
        );

        if ( ref $ret ) {
            my @dbq;
            my $results = $ret->[0];    # results in query zero
            if ( ref $results ) {
                foreach my $new_query ( @{$results} ) {
                    next if !ref $new_query;
                    my ( $schema_q, $table_q ) = map { $self->escape_pg_identifier($_) } @$new_query;
                    push @dbq, "GRANT ALL PRIVILEGES ON $schema_q.$table_q TO $dbname_quoted";
                }
            }

            if (@dbq) {
                $self->super_exec_psql_on_database( $dbname, @dbq );
            }
        }
    }

    return;
}

#This is narrower in scope than addusertodb() in these ways:
#   - It *only* handles login-capable users, not other roles.
#   - It only does one dbuser to one db at a time.
#
#It also throws exceptions on failure.
#
sub grant_db_to_dbuser {
    my ( $self, $dbname, $dbuser ) = @_;

    #NOTE: No need to validate these because the DB server
    #will error if either doesn’t exist.

    $self->_toggle_db_dbuser(
        $dbname,
        $dbuser,
        'GRANT %s TO %s',
        'add_db_for_dbuser',
    );

    return;
}

#Same difference as the above with deluserfromdb().
sub revoke_db_from_dbuser {
    my ( $self, $dbname, $dbuser ) = @_;

    $self->_toggle_db_dbuser(
        $dbname,
        $dbuser,
        'REVOKE %s FROM %s',
        'remove_db_for_dbuser',
    );

    return;
}

sub _toggle_db_dbuser {
    my ( $self, $dbname, $dbuser, $sql_template, $map_method ) = @_;

    $self->_verify_db_in_map($dbname);
    $self->_verify_dbuser_in_map($dbuser);

    my $dbh = $self->{'dbh'} or die "Need dbh!";

    {

        #Turn off AutoCommit so that we automatically roll back
        #if the update of the DB map fails below.
        local $dbh->{'AutoCommit'} = 0;

        my $sql = sprintf(
            $sql_template,
            ( map { $dbh->quote_identifier($_) } $dbname, $dbuser ),
        );

        $self->{'dbh'}->do($sql);

        my $map = $self->_get_map();
        $map->{'owner'}->$map_method( $dbname, $dbuser );
        $self->_save_map_hash($map);

        $dbh->commit();
    }

    $self->queue_dbstoregrants();

    return;
}

#$arg_db is either a DB name or an arrayref of DB names
#
#$arg_dbuser is a DB username or a hashref of:
#   dbuser_name => $nodbmap_value (see below)
#
#$arg_nodbmap is a boolean that specifies whether to suppress adding this
#ownership relation to the DB map.
#
#NOTE: This function doesn’t error-check very consistently.
#Consider grant_db_to_dbuser, or creating a similar function to serve
#your needs?
#
sub addusertodb {
    my ( $self, $arg_db, $arg_dbuser, $arg_nodbmap ) = @_;

    my $dbs     = ref $arg_db     ? $arg_db     : [$arg_db];
    my $dbusers = ref $arg_dbuser ? $arg_dbuser : { $arg_dbuser => ( $arg_nodbmap || 0 ) };

    my @cmds;

    my ( $fetch_roles_status,      $roles_ref )      = $self->fetch_roles( [ keys %{$dbusers} ] );
    my ( $fetch_user_roles_status, $user_roles_ref ) = $self->fetch_user_roles( [ keys %{$dbusers} ] );

    my ($map);

    foreach my $dbuser ( keys %{$dbusers} ) {
        my $nodbmap           = $dbusers->{$dbuser};
        my $safe_ident_dbuser = $self->escape_pg_identifier($dbuser);

        if (   !$fetch_roles_status
            || !$roles_ref->{$dbuser}
            || ( $roles_ref->{$dbuser}{'rolcanlogin'} ne '1' && $roles_ref->{$dbuser}{'rolcanlogin'} ne 't' ) ) {

            # be sure that user can login
            push @cmds, qq{ALTER ROLE $safe_ident_dbuser WITH LOGIN;};
        }

        foreach my $dbname ( @{$dbs} ) {
            my $role_for_db            = $dbname;
            my $safe_ident_role_for_db = $self->escape_pg_identifier($role_for_db);
            my $safe_ident_dbname      = $self->escape_pg_identifier($dbname);

            if (
                $role_for_db ne $dbuser
                && (   !$fetch_user_roles_status
                    || !( grep { $_->{'grantee'} eq $dbuser && $_->{'role_name'} eq $role_for_db } @{$user_roles_ref} ) )
            ) {

                # 3/ role can access the db
                push @cmds, qq{GRANT $safe_ident_role_for_db TO $safe_ident_dbuser;};
            }

            unless ($nodbmap) {
                $map ||= $self->_get_map();
                $map->{'owner'}->add_db_for_dbuser( $dbname, $dbuser );
            }
        }
    }

    foreach my $cmd (@cmds) {
        $self->exec_psql($cmd);
    }

    if ($map) {
        $self->_save_map_hash($map);
    }

    if (@cmds) {
        $self->queue_dbstoregrants();
    }

    return;
}

sub rename_role {
    my ( $self, $oldname, $newname ) = @_;

    return $self->_rename_role_in_pgsql( $oldname, $newname );
}

#NOTE: After rename_cpuser, the cpuser's PostgreSQL user will be unable to login
#until the password is set again.
sub _rename_dbowner {
    my ( $self, $old_dbowner, $new_dbowner ) = @_;

    $self->_rename_role_in_pgsql( $old_dbowner, $new_dbowner );

    return 1;
}

sub _rename_role_in_pgsql {
    my ( $self, $oldname, $newname ) = @_;

    Cpanel::Validate::DB::User::verify_pgsql_dbuser_name($newname);

    my ( $oldname_q, $newname_q ) = map { $self->escape_pg_identifier($_) } ( $oldname, $newname );

    try {
        local $self->{'dbh'}->{'RaiseError'} = 1;

        #The rename will generate a warning about clearning the MD5 password.
        #Don't report this.
        local $self->{'dbh'}->{'PrintWarn'} = 0;

        $self->{'dbh'}->do("ALTER ROLE $oldname_q RENAME TO $newname_q");
    }
    catch {
        if ( UNIVERSAL::isa( $_, 'Cpanel::Exception::Database::Error' ) ) {

            if ( $_->get('state') eq Cpanel::Postgres::Error::undefined_object() ) {
                die Cpanel::Exception::create( 'Database::UserMissing', [ engine => 'postgresql', name => $oldname ] );
            }
        }

        die $_;
    };

    return 1;
}

#NOTE: This does NOT add a DB prefix.
#NOTE: After doing this, the PostgreSQL user will be unable to login
#until the password is set again.
#
#TODO: Have rename_dbuser accept a password and do the rename/set-password
#in a transaction.
#
*_rename_dbuser_in_server = \&_rename_role_in_pgsql;

sub _rename_database_in_server {
    my ( $self, $oldname, $newname ) = @_;

    Cpanel::Validate::DB::Name::verify_pgsql_database_name($newname);

    my ( $oldname_q, $newname_q ) = map { $self->escape_pg_identifier($_) } ( $oldname, $newname );

    #Drop any cached DBI handles that refer to the DB.
    delete $self->{'_user_dbhs'}{$oldname};
    delete $self->{'_super_dbhs'}{$oldname};

    try {
        local $self->{'dbh'}->{'RaiseError'} = 1;
        local $self->{'dbh'}->{'AutoCommit'} = 0;

        $self->{'dbh'}->do("ALTER DATABASE $oldname_q RENAME TO $newname_q");

        $self->{'dbh'}->do("ALTER ROLE $oldname_q RENAME TO $newname_q");

        $self->{'dbh'}->commit();
    }
    catch {
        if ( UNIVERSAL::isa( $_, 'Cpanel::Exception::Database::Error' ) ) {

            if ( $_->get('state') eq Cpanel::Postgres::Error::invalid_catalog_name() ) {
                die Cpanel::Exception::create( 'Database::DatabaseMissing', [ engine => 'postgresql', name => $oldname ] );
            }
        }

        die $_;
    };

    return 1;
}

#NOTE: used in testing
sub _clear_dbhs {
    my ($self) = @_;

    %{ $self->{$_} } = () for qw( _user_dbhs _super_dbhs );

    return;
}

sub deluserfromdb {
    my ( $self, $dbname, $dbuser ) = @_;

    my $map = $self->_get_map();

    if ( !$map->{'map'}->user_owns_db( $self->{'cpuser'}, $dbname ) && !$map->{'map'}->user_owns_dbuser( $self->{'cpuser'}, $dbname ) ) {
        return $self->_log_error_and_output( Cpanel::LocaleString->new( "You, “[_1]”, are not authorized to remove “[_2]” from the database “[_3]”.", $self->{'cpuser'}, $dbuser, $dbname ) );
    }

    $map->{'owner'}->remove_db_for_dbuser( $dbname, $dbuser );
    $self->_save_map_hash($map);

    $self->queue_dbstoregrants( { 'deferred_seconds' => 10 } );

    return unless $self->user_is_member_of( $dbuser, $dbname );

    my $safe_ident_dbuser = $self->escape_pg_identifier($dbuser);
    my $safe_ident_dbname = $self->escape_pg_identifier($dbname);

    return $self->exec_psql(qq/REVOKE $safe_ident_dbname FROM $safe_ident_dbuser;/);
}

sub set_password {
    my ( $self, $dbuser, $dbpass ) = @_;

    $self->_verify_dbuser_in_map($dbuser);

    Cpanel::PasswdStrength::Check::verify_or_die( app => 'postgres', pw => $dbpass );

    my $ok;
    try {
        $ok = $self->{'dbh'}->set_password( $dbuser, $dbpass );
    }
    catch {
        if ( UNIVERSAL::isa( $_, 'Cpanel::Exception::Database::Error' ) ) {

            if ( $_->get('state') eq Cpanel::Postgres::Error::undefined_object() ) {
                die Cpanel::Exception::create( 'Database::UserMissing', [ engine => 'postgresql', name => $dbuser ] );
            }
        }

        die $_;
    };

    $self->queue_dbstoregrants();

    return $ok;
}

sub _passwduser_without_name_validity_check {
    my ( $self, $dbuser, $dbpass, $noupdate ) = @_;

    my $map = $self->_get_map();

    if ( $self->user_exists($dbuser) && !$map->{'map'}->user_owns_dbuser( $self->{'cpuser'}, $dbuser ) ) {
        return ( 0, $self->_log_error_and_output_return( Cpanel::LocaleString->new( "The user “[_1]” already exists, and you, “[_2]”, are not allowed to re-create it.", $dbuser, $self->{'cpuser'} ) ) );
    }
    elsif ( $self->raw_db_exists($dbuser) ) {    # If a database already exists this new role would gain access to it implicitly
        return ( 0, $self->_log_error_and_output_return( Cpanel::LocaleString->new( "The database “[_1]” already exists, and you, “[_2]”, are not allowed to create a user with the same name.", $dbuser, $self->{'cpuser'} ) ) );
    }

    my $safe_ident_dbuser = $self->escape_pg_identifier($dbuser);

    my @cmds;

    if ( !$self->role_exists($dbuser) ) {
        push @cmds, [ qq/CREATE USER $safe_ident_dbuser WITH PASSWORD ?;/, {}, $dbpass ];
        push @cmds, [ qq/ALTER USER $safe_ident_dbuser WITH PASSWORD ?;/,  {}, $dbpass ];
    }
    push @cmds, [ qq/ALTER ROLE $safe_ident_dbuser WITH LOGIN PASSWORD ?;/, {}, $dbpass ];

    foreach my $cmd (@cmds) {
        $self->exec_psql( @{$cmd} );
    }

    my $dbowner = $map->{'owner'}->name();

    if ( $dbowner ne $dbuser ) {
        $map->{'owner'}->add_dbuser( { 'dbuser' => $dbuser, 'server' => Cpanel::PostgresUtils::PgPass::get_server() } );
        $self->_save_map_hash($map);
    }

    if ($noupdate) {
        $self->queue_dbstoregrants();
    }
    else {
        $self->updateprivs();
    }

    return ( 1, $dbuser );
}

#NOTE: Unlike its MySQL counterpart, this DOES apply a database prefix.
sub passwduser {
    my ( $self, $dbuser, $dbpass, $noupdate ) = @_;
    return 0 if ( !$dbuser || !$dbpass );

    if ( !$noupdate ) {
        $dbuser = $self->add_prefix($dbuser);
    }

    return $self->raw_passwduser( $dbuser, $dbpass, $noupdate );
}

#NOTE: This does NOT apply a DB prefix.
sub raw_passwduser {
    my ( $self, $dbuser, $dbpass, $noupdate ) = @_;
    return 0 if ( !$dbuser || !$dbpass );

    local $@;
    if ( !eval { Cpanel::Validate::DB::User::verify_pgsql_dbuser_name($dbuser) } ) {
        my $err = $@;
        return ( 0, $err->to_string() );
    }

    return $self->_passwduser_without_name_validity_check( $dbuser, $dbpass, $noupdate );
}

#NOTE: This does NOT add a DB prefix.
sub deluser {
    my ( $self, $dbuser, $skip_owner_check ) = @_;

    die "Need dbuser!" if !length $dbuser;

    if ( lc($dbuser) eq 'postgres' ) {
        die Cpanel::Exception::create( 'Database::UserNotFound', [ engine => 'postgresql', name => $dbuser ] );
    }

    my $map = $self->_get_map();

    $skip_owner_check ||= 0;

    if ( $skip_owner_check != $SKIP_OWNER_CHECK ) {
        $self->_verify_dbuser_in_map($dbuser);
    }

    my @DBS = $self->listdbs();

    # Case 84193: This will ensure that deleted users do no own any objects
    # prior to removal of the role to which can cause it to fail.

    foreach my $db (@DBS) {
        try {
            $self->chownobjectsindb($db);
        }
        catch {
            warn "A non-fatal error occurred while attempting to fix ownership of the database “$db”: $_";
        };
    }

    my $status;
    my $safe_ident_dbuser = $self->escape_pg_identifier($dbuser);
    if ( $self->raw_db_exists($dbuser) ) {

        # deluserfrom its own db if it exists as well (first)

        foreach my $db ( $dbuser, sort @DBS ) {
            $self->deluserfromdb( $db, $dbuser );
        }

        # Change to a group
        $status = $self->exec_psql(qq{ALTER ROLE $safe_ident_dbuser WITH NOLOGIN;});
    }
    else {
        $status = $self->exec_psql(qq/DROP ROLE $safe_ident_dbuser;/);
    }

    if ($status) {
        $map->{'owner'}->remove_dbuser($dbuser);
        $self->_save_map_hash($map);

        $self->queue_dbstoregrants( { 'deferred_seconds' => 10 } );
    }

    return $status;
}

sub getalldbids {
    my $self = shift;

    my %DBS;
    my $q = $self->{'dbh'}->prepare("SELECT datname,datid FROM pg_stat_database;");
    $q->execute();
    while ( my $data = $q->fetchrow_hashref() ) {
        next if $data->{'datid'} == 0;
        $DBS{ $data->{'datid'} } = $data->{'datname'};
    }
    $q->finish();

    return \%DBS;
}

sub listdbsbyid {
    my $self = shift;
    my (%DBS);

    my @db_list   = map { $self->quote($_) } $self->listdbs();
    my $db_string = join ',', @db_list;
    if ( !$db_string ) {
        $db_string = "''";
    }

    my $q = $self->{'dbh'}->prepare("SELECT datname,datid FROM pg_stat_database where datname in ($db_string);");
    $q->execute();
    while ( my $data = $q->fetchrow_hashref() ) {
        next if $data->{'datid'} == 0;
        $DBS{ $data->{'datid'} } = $data->{'datname'};
    }
    $q->finish();

    return %DBS;
}

sub countdbs {
    my ($self) = @_;
    my @DBS = $self->listdbs();
    if (@DBS) {
        return scalar @DBS;
    }
    return 0;
}

sub dumpsql {
    my ($self) = @_;

    $self->dumpsql_users();
    $self->dumpsql_grants();

    return;
}

sub pgdump {
    my ( $self, $db, $db_backup_type ) = @_;

    return if !length $db;    #XXX: This should die() instead.
    $db_backup_type ||= 'all';

    my $pguser  = Cpanel::PostgresUtils::PgPass::getpostgresuser();
    my $pg_dump = Cpanel::DbUtils::find_pg_dump();
    my $version = Cpanel::PostgresUtils::get_version();

    # i.e., is this CentOS 6 or newer?
    my $scs = $version >= 8.4 ? '-c standard_conforming_strings=on ' : '';

    local $ENV{'TMPDIR'} = '/tmp';    # pg_dump needs to create temporary files Case 4116.

    #This will suppress warnings when the database contains backslashes.
    local $ENV{'PGOPTIONS'} = "$scs-c escape_string_warning=off";

    return system( $pg_dump,
        '--username' => $pguser,
        '--blobs',
        '--format' => 'tar',
        ( $db_backup_type eq 'schema' ? ('--schema-only') : () ),
        Cpanel::PostgresUtils::Quote::pg_dump_dbname_arg($db),
    );
}

#returns a hashref:
#   { name1 => { type => '..', owner => '..' }, name2 => .. }
#
sub getobjectsindb {
    my ( $self, $db ) = @_;
    my $map = $self->_get_map();
    my ($safeuser) = $map->{'owner'}->name();
    my (%OBJECTS);

    my $ret = $self->exec_psql_on_database(
        $db, q{SELECT n.nspname as "Schema",
  c.relname as "Name",
  CASE c.relkind WHEN 'r' THEN 'table' WHEN 'v' THEN 'view' WHEN 'i' THEN 'index' WHEN 'S' THEN 'sequence' WHEN 's' THEN 'special' END as "Type",
  r.rolname as "Owner"
FROM pg_catalog.pg_class c
     JOIN pg_catalog.pg_roles r ON r.oid = c.relowner
     LEFT JOIN pg_catalog.pg_namespace n ON n.oid = c.relnamespace
WHERE c.relkind IN ('r','v','S','')
      AND n.nspname NOT IN ('pg_catalog', 'pg_toast')
      AND pg_catalog.pg_table_is_visible(c.oid)
ORDER BY 1,2;}
    );

    if ($ret) {
        foreach my $query_result ( @{$ret} ) {
            foreach my $result ( @{$query_result} ) {
                my ( $schema, $name, $type, $owner ) = @{$result};
                $OBJECTS{$name} = { 'type' => $type, 'owner' => $owner };
            }
        }
    }
    return \%OBJECTS;
}

#As of 11.44, this sets ownership to the database role.
#(Previously, ownership was set to the user role.)
sub chownobjectsindb {
    my ( $self, $db ) = @_;

    my $object_ref = $self->getobjectsindb($db);

    my $quoted_db = Cpanel::PostgresUtils::Quote::quote_identifier($db);

    my @table_statements;
    my @sequence_statements;
    while ( my ( $obj, $obj_data ) = each %{$object_ref} ) {
        my $quoted_obj = Cpanel::PostgresUtils::Quote::quote_identifier($obj);
        my $statement  = qq{ALTER TABLE $quoted_obj OWNER TO $quoted_db};

        #TODO: Even if ALTER TABLE works on sequences,
        #wouldn't ALTER SEQUENCE make more sense?
        if ( $obj_data->{'type'} eq 'table' ) {
            push @table_statements, $statement;
        }
        else {
            push @sequence_statements, $statement;
        }
    }

    # tables need to be altered first
    return $self->super_exec_psql_on_database( $db, @table_statements, @sequence_statements );
}

sub dbcache {
    my ($self)      = @_;
    my @DBS         = $self->listdbs();
    my %DBUSERS     = $self->listusersindb(@DBS);
    my %DBDISKUSAGE = $self->_diskusage();

    my $pong = $self->exec_psql("SELECT 'PING';");

    print "ISRUNNING\t" . ( $pong =~ /ping/i ? 1 : 0 ) . "\n";
    foreach my $db (@DBS) {
        print "DB\t${db}\n";
        foreach my $user ( @{ $DBUSERS{$db} } ) {
            print "DBUSER\t${db}\t${user}\n";
        }
        print "DBDISKUSED\t$db\t" . ( $DBDISKUSAGE{$db} || 0 ) . "\n";
    }
    my (@USERS) = $self->listusers();
    foreach my $user (@USERS) {
        print "USER\t${user}\n";
    }

    $self->updateprivs();

    return;
}

#NOTE: Unlike its MySQL counterpart, this DOES add a database prefix.
sub create_db {
    my ( $self, $dbname, $noupdateprivs ) = @_;

    $dbname = $self->add_prefix($dbname);

    return $self->raw_create_db( $dbname, $noupdateprivs );
}

#NOTE: This does NOT add a DB prefix.
sub raw_create_db {
    my ( $self, $dbname, $noupdateprivs ) = @_;

    my $map   = $self->_get_map();
    my $owner = $map->{'owner'}->name() || $self->{'cpuser'};

    local $@;
    if ( !eval { Cpanel::Validate::DB::Name::verify_pgsql_database_name($dbname) } ) {
        my $err = $@;
        $self->_log_error_and_output( '[_1]', $err->to_string() );
        return ( 0, $err->to_string() );
    }

    my $err_phrase;

    # If they own the db thats ok
    if ( $self->raw_db_exists($dbname) && !$map->{'map'}->user_owns_db( $self->{'cpuser'}, $dbname ) ) {
        $err_phrase = Cpanel::LocaleString->new( "The database “[_1]” already exists.", $dbname );
    }

    # If a role already exists it would gain access to this database implicitly
    elsif ( $self->role_exists($dbname) ) {
        $err_phrase = Cpanel::LocaleString->new( "The database “[_1]” cannot be added because a user with the same name already exists.", $dbname );
    }

    if ($err_phrase) {
        $self->_log_error_and_output($err_phrase);
        return ( 0, $err_phrase->to_string() );
    }

    my $safeuser = $owner;

    my $safe_ident_dbname = $self->escape_pg_identifier($dbname);
    my $safe_ident_owner  = $self->escape_pg_identifier($owner);

    my @cmds = (
        qq{CREATE ROLE $safe_ident_dbname},
        qq{CREATE DATABASE $safe_ident_dbname with OWNER=$safe_ident_dbname},
    );

    foreach my $cmd (@cmds) {
        my $err;
        try {
            $self->{'dbh'}->do($cmd);
        }
        catch {
            my $phrase = Cpanel::LocaleString->new( "The PostgreSQL command ([_1]) to create the database “[_2]” for the user “[_3]” failed because of an error: [_4]", $cmd, $dbname, $owner, Cpanel::Exception::get_string($_) );
            $err = $phrase->to_string();
            $self->_log_error_and_output($phrase);
        };

        return ( 0, $err ) if $err;
    }

    # CPANEL-28932: The user's cached value was being deleted for MySQL for
    # years, but not for PostgreSQL here, and that's suddenly causing
    # problems.
    $self->_unlink_user_postgres_db_count();

    unlink( $self->_get_userdatastore_dir() . '/postgres-db-count' );

    $map->{'owner'}->add_db($dbname);
    $self->_save_map_hash($map);

    # update privileges only for this database
    if ($noupdateprivs) {
        $self->queue_dbstoregrants();
    }
    else {
        $self->updateprivs( 'db' => $dbname );
    }

    # CPANEL-28932: Remember to rebuild the dbindex; otherwise, update_db_cache
    # can't do system caching of database info.
    Cpanel::ServerTasks::schedule_task( ['MysqlTasks'], 3, 'dbindex' );

    return ( 1, $dbname );
}

sub exec_psql {
    my ( $self, $sql, $attr, @bind ) = @_;

    my $results;

    $self->{'cpconf'} ||= Cpanel::Config::LoadCpConf::loadcpconf_not_copy();

    if ( $sql =~ m/^[ \t]*select/i ) {
        my $res   = $self->{'dbh'}->selectall_arrayref( $sql, $attr, @bind );
        my $state = $self->{'dbh'}->state();
        if ( $state && $state ne Cpanel::Postgres::Error::duplicate_object() ) {
            print STDERR "PostgreSQL Server is down or unreachable with state: " . $state . ": " . $self->{'dbh'}->errstr() . "\n";
            return;
        }
        foreach my $row ( @{$res} ) {
            $results .= join( ' ', @{$row} );
        }
    }
    else {
        my ( $err, $res );
        try {
            $res = $self->{'dbh'}->do( $sql, $attr, @bind );
        }
        catch {
            $err = $_;
        };
        if ($err) {
            return $self->_log_error_and_output( Cpanel::LocaleString->new( "PostgreSQL query failed: [_1]: [_2]", $sql, Cpanel::Exception::get_string($err) ) );
        }

        my $state = $self->{'dbh'}->state();
        if ( $state && $state ne Cpanel::Postgres::Error::duplicate_object() ) {
            print STDERR "PostgreSQL Server is down or unreachable with state: " . $state . ": " . $self->{'dbh'}->errstr() . "\n";
            return;
        }
        $results .= $res;
    }

    return $results;
}

sub disconnect_dbh {
    my ( $self, $database ) = @_;

    if ( $self->{'_user_dbhs'}{$database} ) {
        try { $self->{'_user_dbhs'}{$database}->disconnect(); };
    }

    if ( $self->{'_super_dbhs'}{$database} ) {
        try { $self->{'_super_dbhs'}{$database}->disconnect(); };
    }

    return;
}

sub exec_psql_on_database {
    my ( $self, $database, @sql ) = @_;

    $self->{'_user_dbhs'}{$database} ||= $self->_get_dbh( $database, $self->{'user'}, $self->{'dbpass'} );

    my $dbh = $self->{'_user_dbhs'}{$database};

    return if !$dbh;

    return $self->_exec_psql_on_database_with_dbh( $database, $dbh, @sql );
}

sub _cache_super_dbh_after_instantiation {
    my ( $self, $database ) = @_;

    return if !$self->{'dbh'};

    return $self->{'_super_dbhs'}{$database} ||= $self->{'dbh'}->clone( { database => $database } );
}

sub super_exec_psql_on_database {
    my ( $self, $database, @sql ) = @_;

    #XXX: If the @sql statements contain a SET SESSION AUTHORIZATION command,
    #that command will "taint" these cached DB handles. If that becomes a problem,
    #this caching will need to be removed.
    my $dbh = $self->_cache_super_dbh_after_instantiation($database) or die 'No dbh!';

    return $self->_exec_psql_on_database_with_dbh( $database, $dbh, @sql );
}

sub _exec_psql_on_database_with_dbh {
    my ( $self, $database, $dbh, @sql ) = @_;

    $self->{'cpconf'} ||= Cpanel::Config::LoadCpConf::loadcpconf();

    my @results;
    foreach my $statement (@sql) {
        my $clean_statement = $statement;
        $clean_statement =~ s/\n/ /g;

        if ( $statement =~ /\Aselect\s/i ) {
            push @results, $dbh->selectall_arrayref($statement);
        }
        else {
            my ( $res, $err );
            try {
                $res = $dbh->do($statement);
            }
            catch {
                $err = $_;
            };
            if ($err) {
                $self->{'logger'}->warn( "PostgreSQL statement ($statement) execution failed: " . Cpanel::Exception::get_string($err) );
            }
            elsif ( $dbh->err() ) {
                $self->{'logger'}->warn( "PostgreSQL statement ($statement) execution failed: " . $dbh->errstr() );
            }
            push @results, $res;
        }
    }

    return \@results;
}

# TODO user_exists, db_exists, ... looks to be a duplicate
#    of what we have in PostgresUtils
#    we should factorize all that in one single place

sub user_exists {
    my ( $self, $user ) = @_;

    return $self->_easy_check( qq{SELECT 1 FROM pg_user WHERE usename=?;}, {}, $user );
}

#This prefixes the DB name if the server does DB prefixing and the name
#isn't already prefixed, then returns whether the DB exists (boolean).
sub db_exists {
    my ( $self, $dbname ) = @_;

    return $self->raw_db_exists( $self->add_prefix($dbname) );
}

#Same as db_exists(), but this checks a raw DB name without prefixing it first.
sub raw_db_exists {
    my ( $self, $dbname ) = @_;

    # Since we have a role for each dbname we cannot allow them to create a user with the same
    return $self->_easy_check( qq{SELECT 1 FROM pg_database WHERE datname=?;}, {}, $dbname );
}

sub role_can_login {
    my ( $self, $role ) = @_;

    return $self->_easy_check( qq{SELECT 1 FROM pg_roles WHERE rolname=? and rolcanlogin='t';}, {}, $role );
}

sub role_cannot_login {
    my ( $self, $role ) = @_;

    return $self->_easy_check( qq{SELECT 1 FROM pg_roles WHERE rolname=? and rolcanlogin='f';}, {}, $role );
}

sub role_exists {
    my ( $self, $role ) = @_;

    return $self->_easy_check( qq{SELECT 1 FROM pg_roles WHERE rolname=?;}, {}, $role );
}

sub user_is_member_of {
    my ( $self, $user, $role ) = @_;

    return $self->_easy_check( qq{SELECT 1 FROM information_schema.applicable_roles where grantee=? and role_name=?;}, {}, $user, $role );
}

sub fetch_user_roles {
    my ( $self, $users ) = @_;

    my $dbh = $self->{'dbh'};

    my $user_list = join( ',', map { $self->quote($_) } @{$users} );

    my $sql = "SELECT grantee,role_name from information_schema.applicable_roles where grantee IN ($user_list);";
    $self->{'cpconf'} ||= Cpanel::Config::LoadCpConf::loadcpconf();
    my $data = $dbh->selectall_arrayref( $sql, { Slice => {} } );

    my $err = $dbh->errstr();

    return ( 0, $err ) if $err;

    return ( 1, $data );

}

sub fetch_roles {
    my ( $self, $roles ) = @_;

    my $dbh = $self->{'dbh'};

    my $role_list = join( ',', map { $self->quote($_) } @{$roles} );

    my $sql = "SELECT rolname,rolcanlogin from pg_roles where rolname IN ($role_list);";

    $self->{'cpconf'} ||= Cpanel::Config::LoadCpConf::loadcpconf();

    my $data = $dbh->selectall_hashref( $sql, 'rolname' );

    my $err = $dbh->errstr();

    return ( 0, $err ) if $err;

    return ( 1, $data );
}

sub fetch_temp_users {
    my ($self) = @_;

    my $dbh = $self->{'dbh'};

    my $sql = "SELECT usename as user FROM pg_user WHERE usename LIKE ?";
    $self->{'cpconf'} ||= Cpanel::Config::LoadCpConf::loadcpconf();
    my $data = $dbh->selectall_hashref( $sql, 'user', undef, 'cpses\\_%' );

    my $err = $dbh->errstr();

    return ( 0, $err ) if $err;

    return ( 1, $data );
}

sub _easy_check {
    my ( $self, $cmd, $attrs, @bind ) = @_;
    my $return = $self->exec_psql( $cmd, $attrs, @bind );
    chomp($return) if $return;
    return $return && $return == 1 ? 1 : 0;
}

sub add_prefix {
    my ( $self, $name ) = @_;

    return Cpanel::DB::add_prefix_if_name_and_server_need($name);
}

1;
