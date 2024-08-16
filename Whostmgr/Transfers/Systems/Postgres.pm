package Whostmgr::Transfers::Systems::Postgres;

# cpanel - Whostmgr/Transfers/Systems/Postgres.pm  Copyright 2022 cPanel, L.L.C.
#                                                           All rights reserved.
# copyright@cpanel.net                                         http://cpanel.net
# This code is subject to the cPanel license. Unauthorized copying is prohibited

use strict;
## no critic qw(TestingAndDebugging::RequireUseWarnings)

# RR Audit: JNK

use base qw(
  Whostmgr::Transfers::SystemsBase::DBBase
);

use Try::Tiny;
use Cpanel::PostgresAdmin::Check ();

use Cpanel::DbUtils                      ();
use Cpanel::PostgresUtils::PgPass        ();
use Cpanel::Exception                    ();
use Cpanel::DB::Map::Collection::Index   ();
use Cpanel::DB::Utils                    ();
use Cpanel::FileUtils::Dir               ();
use Cpanel::LoadFile                     ();
use Cpanel::Locale                       ();
use Cpanel::LocaleString                 ();
use Cpanel::Postgres::Error              ();
use Cpanel::PostgresAdmin                ();
use Cpanel::PostgresAdmin::Restore       ();
use Cpanel::PostgresUtils                ();
use Cpanel::PostgresUtils::Quote         ();
use Cpanel::Rand::Get                    ();
use Cpanel::Version::Compare             ();
use Cpanel::Validate::LineTerminatorFree ();
use Cpanel::Validate::DB::Name           ();
use Cpanel::Validate::DB::User           ();

sub get_relative_time {
    return 3;
}

sub map_engine { return 'PGSQL'; }

our $MIN_VERSION_FOR_SAFE_RESTORE;
our $MIN_VERSION_FOR_SETTING_SCHEMA;
our $MAX_IDENTIFIER_LENGTH;

BEGIN {
    $MIN_VERSION_FOR_SAFE_RESTORE   = '8.4';
    $MIN_VERSION_FOR_SETTING_SCHEMA = '9.0';
    $MAX_IDENTIFIER_LENGTH          = 63;
}

sub get_summary {
    my ($self) = @_;
    return [ $self->_locale()->maketext('This restores [asis,PostgreSQL] databases, users, and grants.') ];
}

sub get_restricted_available {
    my ($self) = @_;

    my $postgres_version = Cpanel::PostgresUtils::get_version();
    if ( Cpanel::Version::Compare::compare( $postgres_version, '>=', $MIN_VERSION_FOR_SAFE_RESTORE ) ) {
        return 1;
    }
    return 0;
}

sub get_restricted_summary {
    my ($self) = @_;
    return [ $self->_locale()->maketext( '[asis,PostgreSQL] version “[_1]” or later is required to restore databases in restricted mode.', $MIN_VERSION_FOR_SAFE_RESTORE ) ];
}

#This takes three "flags":
#
sub restricted_restore {
    my ($self) = @_;

    #Unneeded, and it makes dumps of $self obnoxiously big.
    delete $self->{'locale'};

    $self->start_action("Preparing PostgreSQL restore …");

    my $flags_hr = $self->{'_utils'}{'flags'};

    my ( $init_ok, $err ) = $self->_init();
    return ( 0, $err ) if !$init_ok;

    my ( $files_ok, $has_db_files ) = $self->_find_psql_db_files_in_restore();
    return ( 0, $has_db_files ) if !$files_ok;

    my $pguser        = Cpanel::PostgresUtils::PgPass::getpostgresuser();
    my $pgrestore_bin = $pguser && Cpanel::DbUtils::find_pg_restore();

    if ( !$pgrestore_bin ) {
        if ($has_db_files) {
            my $err = $self->_locale()->maketext('This system does not have PostgreSQL, so the system will not restore any [asis,PostgreSQL] resources.');
            $self->save_databases_in_homedir('psql');
            $self->warn($err);
        }
        else {
            my $err = $self->_locale()->maketext('This system does not have PostgreSQL.');
            $self->out($err);
        }
        return 1;
    }

    if ( !Cpanel::PostgresAdmin::Check::is_enabled_and_configured() ) {
        $self->{'_utils'}->add_skipped_item( $self->_locale()->maketext('[asis,PostgreSQL] is disabled on this server, so the system will not restore any [asis,PostgreSQL] resources.') );
        $self->save_databases_in_homedir('psql') if $has_db_files;
        return 1;
    }

    $self->{'_pgrestore_bin'} = $pgrestore_bin;

    #$self->{'_pgrestore_bin'} = "/usr/local/pgsql/bin/pg_restore";

    my $newuser = $self->newuser();

    my ( $pgadmin, $connect_err );
    try {
        $pgadmin = Cpanel::PostgresAdmin->new(
            {
                cpuser => $newuser,

                #Allow creation of the DB map since we’re in the middle
                #of creating/restoring an account.
                allow_create_dbmap => 1,
            }
        );
    }
    catch {
        $connect_err = $_;
    };

    if ($connect_err) {
        $self->save_databases_in_homedir('psql') if $has_db_files;
        return ( 0, Cpanel::Exception::get_string($connect_err) );
    }

    local $pgadmin->{'disable_queue_dbstoregrants'} = 1;

    if ( !$pgadmin || !$pgadmin->{'dbh'} ) {
        return ( 0, $self->_locale()->maketext("Failed to connect to PostgreSQL server.") );
    }

    $self->{'pgadmin'} = $pgadmin;
    $self->_ensure_primary_user_exists();

    if ( !$has_db_files ) {
        $self->out( $self->_locale()->maketext("This archive contains no PostgreSQL data.") );

        #No psql to restore
        delete $self->{'pgadmin'};    #force destory
        return 1;
    }

    my ( $users_ok, $users_ar ) = $self->_load_users();
    return ( 0, $users_ar ) if !$users_ok;

    #NOTE: Do we need to filter out any @users here or below?
    #We currently do restore users that have no grants.
    my ( $grants_ok, $grants_ar ) = $self->_load_grants();
    return ( 0, $grants_ar ) if !$grants_ok;

    $self->_get_unique_dbs_and_users( $users_ar, $grants_ar );

    $self->_determine_dbuser_updates_for_restore_and_overwrite();
    $self->_restore_users($users_ar) if $users_ar;

    if ( $self->_should_restore_databases() ) {
        $self->_determine_dbname_updates_for_restore_and_overwrite();
        $self->_restore_databases_with_mappings();
    }
    else {
        my @current_dbs = $pgadmin->listdbs();
        my %updates;
        @updates{@current_dbs} = @current_dbs;
        $self->{'_dbname_updates'} = \%updates;
    }

    $self->_restore_grants($grants_ar) if $grants_ar;

    local $pgadmin->{'disable_queue_dbstoregrants'} = 0;

    $pgadmin->queue_dbstoregrants();

    delete $self->{'pgadmin'};

    return 1;
}

sub _ensure_primary_user_exists {
    my ($self) = @_;

    #A temporary password that will be overwritten if the archive contains
    #a password for the dbowner.
    local $ENV{'REMOTE_PASSWORD'} = Cpanel::Rand::Get::getranddata(8);
    $self->{'pgadmin'}->updateprivs();

    return 1;
}

#payload value here indicates whether there are DBs to restore.
sub _find_psql_db_files_in_restore {
    my ($self) = @_;
    my $extractdir = $self->extractdir();
    my @DB_TARS;
    if ( -d "$extractdir/psql" ) {

        my ( $err, $psql_dir_nodes );
        try {
            $psql_dir_nodes = Cpanel::FileUtils::Dir::get_directory_nodes("$extractdir/psql");
        }
        catch {
            $err = $_;
        };
        return ( 0, $err->to_string() ) if $err;

        @DB_TARS = grep m{\.tar\z}, @$psql_dir_nodes;
    }

    return ( 1, 0 ) if !@DB_TARS;    #Nothing to do

    my %DB_FILE = map { ( m{\A(.*)\.} ? $1 : $_ ) => $_ } @DB_TARS;

    # Should never happen
    Cpanel::Validate::LineTerminatorFree::validate_or_die($_) for keys %DB_FILE;

    $self->{'_db_files'} = \%DB_FILE;

    return ( 1, 1 );
}

sub _restore_grants {
    my ( $self, $grants_ar ) = @_;
    $self->start_action("Restoring PostgreSQL grants …");

    #TODO: Error checking … except this function doesn't report status.

    $self->{'_grants_ar'} = $grants_ar;

    for my $grant (@$grants_ar) {

        next if $grant->{'grantee'} eq Cpanel::DB::Utils::username_to_dbowner( $self->olduser() );

        next if !$self->_check_if_db_is_restored_and_warn_about_non_grant_restoration( $grant->{'granted'} );

        my $dbname = $self->new_dbname_name( $grant->{'granted'} );
        my $dbuser = $self->new_dbuser_name( $grant->{'grantee'} );

        next if $self->{'_failed_db_restore'}{$dbname};

        # $pgadmin will validate they are allowed to do this
        $self->{'pgadmin'}->addusertodb( $dbname, $dbuser );

        push @{ $self->{'_restored_grants'} },
          {
            granted => $dbname,
            grantee => $dbuser,
          };
    }

    return 1;
}

sub _restore_users {
    my ( $self, $dbusers_ar ) = @_;

    $self->start_action("Restoring PostgreSQL users …");

    my $olduser     = $self->olduser();
    my $old_dbowner = Cpanel::DB::Utils::username_to_dbowner($olduser);

    my $newuser = $self->newuser();
    my $dbowner = Cpanel::DB::Utils::username_to_dbowner($newuser);

    for my $dbuser_hr (@$dbusers_ar) {
        my $dbusername = $dbuser_hr->{'username'};

        if ( $dbusername eq $old_dbowner ) {
            my $dbowner_q = $self->{'pgadmin'}->{'dbh'}->quote_identifier($dbowner);
            $self->{'pgadmin'}->exec_psql( "ALTER ROLE $dbowner_q WITH LOGIN PASSWORD ?", undef, $dbuser_hr->{'password'} );
        }
        else {
            my $new_dbusername = $self->new_dbuser_name($dbusername);

            if ( $self->system_already_has_dbuser_with_name($new_dbusername) ) {
                my $former_owner = $self->get_preexisting_system_dbuser_owner($new_dbusername);
                if ( defined $former_owner ) {
                    if ( $former_owner ne $newuser ) {
                        $self->out( $self->_locale()->maketext( 'The system will overwrite [_1]’s database user “[_2]”.', $former_owner, $new_dbusername ) );
                        my $old_dbadmin = Cpanel::PostgresAdmin->new( { cpuser => $former_owner } );
                        $old_dbadmin->deluser($new_dbusername);
                    }
                }
                else {
                    $self->_rename_role_out_of_the_way($new_dbusername);
                }
            }

            # $pgadmin will validate they are allowed to modify $new_dbusername
            my ( $ok, $passwd_result ) = $self->{'pgadmin'}->raw_passwduser( $new_dbusername, $dbuser_hr->{'password'}, $Cpanel::PostgresAdmin::NO_UPDATE_PRIVS );
            if ($ok) {
                $self->{'_restored_dbusers'}{$dbusername} = $new_dbusername;

                if ( $dbusername ne $new_dbusername ) {
                    $self->{'_utils'}->add_altered_item(
                        $self->_locale()->maketext( "The system has restored the PostgreSQL user “[_1]” as “[_2]”.", $dbusername, $new_dbusername ),
                        [
                            $self->_locale()->maketext("Rename"),
                            '/scripts5/manage_database_users',
                            { engine => 'postgresql', name => $new_dbusername },
                        ],
                    );
                }
            }
            else {
                $self->warn("Failed to create new PostgreSQL user “$new_dbusername”: $passwd_result");
            }
        }
    }
    return 1;
}

#%opts are described inline below:
sub __rename_out_of_the_way {
    my ( $self, %opts ) = @_;

    for (
        'obj_name',
        'statement',    #passed to _find_unique_name_variant as a DBI $sth
        'exclude',      #passed to _find_unique_name_variant()
        'does_not_exist_sqlstate',
        'will_rename_phrase',
        'sql_whatsit',
        'failed_rename_phrase',
    ) {
        die "Missing “$_”!" if !exists $opts{$_};
    }

    my $obj_name = $opts{'obj_name'};

    my $dbh = $self->{'pgadmin'}{'dbh'};

    my $name_to_rename_as = $self->_find_unique_name_variant(
        name       => $obj_name,
        max_length => $MAX_IDENTIFIER_LENGTH,
        statement  => $dbh->prepare( $opts{'statement'} ),
        exclude    => $opts{'exclude'},
    );

    $self->out( $opts{'will_rename_phrase'}->clone_with_args( $obj_name, $name_to_rename_as )->to_string() );

    my $name_to_rename_as_q = $dbh->quote_identifier($name_to_rename_as);

    try {
        $dbh->do(
            qq<
            ALTER
            $opts{'sql_whatsit'}
            $obj_name
            RENAME TO
            $name_to_rename_as_q
        >
        );
    }
    catch {
        die $_ if $_->get('state') ne $opts{'does_not_exist_sqlstate'};
    };

    return $name_to_rename_as;
}

sub _rename_db_out_of_the_way {
    my ( $self, $db_name ) = @_;

    return $self->__rename_out_of_the_way(
        obj_name                => $db_name,
        statement               => 'SELECT 1 FROM pg_database WHERE datname = ?',
        exclude                 => [ grep { defined } $self->_get_new_db_names() ],
        does_not_exist_sqlstate => Cpanel::Postgres::Error::invalid_catalog_name(),
        sql_whatsit             => 'DATABASE',
        will_rename_phrase      => Cpanel::LocaleString->new('The system will rename the unmanaged database “[_1]” to “[_2]”.'),
        failed_rename_phrase    => Cpanel::LocaleString->new('The system failed to rename the database “[_1]” because of an error: [_2]'),
    );
}

sub _rename_role_out_of_the_way {
    my ( $self, $rolename ) = @_;

    return $self->__rename_out_of_the_way(
        obj_name                => $rolename,
        statement               => 'SELECT 1 FROM pg_roles WHERE rolname = ?',
        exclude                 => [ grep { defined } $self->_get_new_dbuser_names() ],
        does_not_exist_sqlstate => Cpanel::Postgres::Error::undefined_object(),
        sql_whatsit             => 'ROLE',
        will_rename_phrase      => Cpanel::LocaleString->new('The system will rename the unmanaged role “[_1]” to “[_2]”.'),
        failed_rename_phrase    => Cpanel::LocaleString->new('The system failed to rename “[_1]” because of an error: [_2]'),
    );
}

sub _restore_databases_with_mappings {
    my ($self) = @_;

    my $db_file = $self->{'_db_files'} || die "_find_psql_db_files_in_restore must be called before _restore_databases_with_mappings";
    $self->start_action("Creating PostgreSQL databases …");

    my $postgres_version = Cpanel::PostgresUtils::get_version();
    if ( Cpanel::Version::Compare::compare( $postgres_version, '<', $MIN_VERSION_FOR_SAFE_RESTORE ) && !$self->{'_utils'}->is_unrestricted_restore() ) {
        while ( my ( $db, $dbtar ) = each %{$db_file} ) {
            my $full_dbname = $self->new_dbname_name($db);
            $self->{'_utils'}->add_skipped_item( $self->_locale()->maketext( 'The system cannot restore the database “[_1]” because PostgreSQL version “[_2]” is required to restore a database in restricted mode and the installed version is “[_3]”.', $full_dbname, $MIN_VERSION_FOR_SAFE_RESTORE, $postgres_version ) );
            $self->{'_failed_db_restore'}{$full_dbname} = 1;
        }
        return;
    }

    while ( my ( $db, $dbtar ) = each %{$db_file} ) {
        next if $self->should_skip_db($db);

        # create_db will get the new name
        $self->_create_db($db);    # Will create the database and setting the mappings
    }

    $self->start_action("Updating PostgreSQL privileges …");

    #TODO: Error checking .. except this function doesn't return status.
    my $newuser = $self->newuser();
    $self->{'pgadmin'}->updateprivs( user => $newuser );    # auto converts to dbowner

    my $extractdir = $self->extractdir();
    $self->start_action("Restoring PostgreSQL databases …");
    while ( my ( $db, $dbtar ) = each %{$db_file} ) {

        # Must get the full name after the _create_db
        my $full_dbname = $self->new_dbname_name($db);
        next if $self->should_skip_db($db);    # Creation may have failed

        my $path = "$extractdir/psql/$dbtar";
        if ( !-s $path ) {
            $self->warn( $self->_locale()->maketext( "The PostgreSQL backup for the database “[_1]” is empty.", $db ) );
            next;
        }
        $self->_restore_db( $db, $full_dbname, $path );
    }

    return 1;
}

sub _restore_db {
    my ( $self, $old_name, $new_name, $path ) = @_;
    my $super_dbh = $self->{'pgadmin'}{'dbh'};

    my $newuser = $self->newuser();

    if ( $old_name eq $new_name ) {
        $self->out( $self->_locale()->maketext( "Restoring the database “[_1]” …", $old_name ) );
    }
    else {
        $self->out( $self->_locale()->maketext( "Restoring the database “[_1]” as “[_2]” …", $old_name, $new_name ) );
    }

    open my $rfh, '<', $path or do {
        $self->warn("Failed to open $path for reading: $!");
        $self->{'_utils'}->add_skipped_item( $self->_locale()->maketext( 'The system failed to restore the database “[_1]” because the system failed to open the file “[_2]” because of an error: [_3]', $old_name, $path, $! ) );
        $self->{'_failed_db_restore'}{$new_name} = 1;
        return;
    };

    my @args = (
        '--no-privileges',
        '--no-owner',
        Cpanel::PostgresUtils::Quote::dbname_command_args($new_name),
    );

    my $postgres_version = Cpanel::PostgresUtils::get_version();

    if ( Cpanel::Version::Compare::compare( $postgres_version, '>=', $MIN_VERSION_FOR_SAFE_RESTORE ) ) {
        push @args, '--single-transaction', '--role' => $new_name;
    }
    if ( Cpanel::Version::Compare::compare( $postgres_version, '>=', $MIN_VERSION_FOR_SETTING_SCHEMA ) ) {
        push @args, '--schema' => 'public';
    }

    # executes as postgres user
    my $restore = $super_dbh->exec_with_credentials_no_db(
        program => $self->{'_pgrestore_bin'},
        args    => \@args,
        stdin   => $rfh,
    );

    if ( $restore->CHILD_ERROR() ) {
        $self->warn( "Import of DB “$old_name” failed: " . $restore->stderr() );

        $self->{'_utils'}->add_skipped_item( $self->_locale()->maketext( 'The system failed to restore the database “[_1]” because of an error: [_2]', $old_name, $restore->stderr() ) );
        $self->save_databases_in_homedir('psql');
        $self->{'_failed_db_restore'}{$new_name} = 1;

        return;
    }

    if ( length $restore->stderr() ) {
        $self->out( $self->_locale()->maketext( '[asis,PostgreSQL] sent the following warning text upon the restoration of the “[_1]” database: [_2]', $old_name, $restore->stderr() ) );
    }

    #Once we stop supporting PgSQL 8.1, we can use --role with
    #pg_restore, and this can be dropped.
    my $quoted_new_name = $super_dbh->quote_identifier($new_name);
    $super_dbh->do("ALTER DATABASE $quoted_new_name OWNER TO $quoted_new_name");

    $self->{'pgadmin'}->chownobjectsindb($new_name);

    # For testing
    $self->{'_restored_databases'}{$old_name} = $new_name;

    if ( $old_name ne $new_name ) {
        $self->{'_utils'}->add_altered_item(
            $self->_locale()->maketext( "The system has restored the PostgreSQL database “[_1]” as “[_2]”.", $old_name, $new_name ),
            [
                $self->_locale()->maketext("Rename"),
                '/scripts5/manage_databases',
                { engine => 'postgresql', name => $new_name },
            ],
        );
    }
    return 1;
}

sub _create_db {
    my ( $self, $dbname ) = @_;

    my $new_dbname = $self->new_dbname_name($dbname);

    my ($tryerr);
    try {
        Cpanel::Validate::DB::Name::verify_pgsql_database_name($new_dbname);
    }
    catch {
        $tryerr = $_;
    };
    if ($tryerr) {
        $self->set_skip_db($dbname);    # skip restoring the failed db
        $self->warn( $self->_locale()->maketext( "The system is unable to restore the database “[_1]” because of an error: [_2]", $new_dbname, Cpanel::Exception::get_string($tryerr) ) );
        return;
    }

    my $super_dbh = $self->{'pgadmin'}{'dbh'};

    $self->{'_quiet_dbh'} ||= $super_dbh->clone( { db => 'postgres', PrintWarn => 0, PrintError => 0 } );
    my $quiet_dbh = $self->{'_quiet_dbh'};

    if ( $super_dbh->db_exists($new_dbname) ) {
        my $dbindex          = Cpanel::DB::Map::Collection::Index->new( { 'db' => 'PGSQL' } );
        my $old_cpuser_owner = $dbindex->get_dbuser_by_db($new_dbname);

        #If the DB is a cPanel-owned DB, we can be sure that there is a role
        #with the same name as the DB that we should delete.
        #
        if ( defined $old_cpuser_owner ) {
            $self->out( $self->_locale()->maketext( "The system will overwrite [_1]’s existing database “[_2]” and its associated role.", $old_cpuser_owner, $new_dbname ) );
            my $old_dbadmin = ( $old_cpuser_owner eq $self->newuser() ) ? $self->{'pgadmin'} : Cpanel::PostgresAdmin->new( { cpuser => $old_cpuser_owner } );
            $old_dbadmin->drop_db($new_dbname);
        }

        #If the DB is not cPanel-owned, then we want separate messages for DB
        #and role.
        else {
            $self->_rename_db_out_of_the_way($new_dbname);

            if ( $super_dbh->role_exists($new_dbname) ) {
                $self->_rename_role_out_of_the_way($new_dbname);
            }
        }
    }

    my ( $create_ok, $full_dbname ) = $self->{'pgadmin'}->raw_create_db( $new_dbname, 1 );

    if ($create_ok) {
        $self->{'_dbname_updates'}->{$dbname} = $full_dbname;
    }
    else {
        if ( $dbname eq $new_dbname ) {
            $self->out( $self->_locale()->maketext( "Overwriting existing database “[_1]” …", $dbname ) );
        }
        else {
            $self->set_skip_db($dbname);    # skip restoring the failed db
            $self->warn("Failed to create new PostgreSQL DB “$dbname”: $full_dbname");
        }
    }

    return;
}

sub _load_users {
    my ($self) = @_;

    my $extractdir = $self->extractdir();

    my @users;

    my $users_sql_path = "$extractdir/psql_users.sql";
    if ( -s $users_sql_path ) {
        my $users_sql_sr = Cpanel::LoadFile::loadfile_r($users_sql_path) or do {
            return ( 0, $self->_locale()->maketext( 'The system failed to load the file “[_1]” because of an error: [_2]', $users_sql_path, $! ) );
        };

        foreach my $user_ref ( @{ Cpanel::PostgresAdmin::Restore::parse_users_file_sr_from_postgresadmin($users_sql_sr) } ) {
            my ( $username, $password ) = @{$user_ref};
            my ($err);
            try {
                Cpanel::Validate::DB::User::verify_pgsql_dbuser_name($username);
            }
            catch {
                $err = $_;
            };
            if ($err) {
                $self->warn( $self->_locale()->maketext( "The system is unable to restore the PostgreSQL username “[_1]” because of an error: [_2]", $username, Cpanel::Exception::get_string($err) ) );
                next;
            }
            push @users, { 'username' => $username, 'password' => $password };
        }
    }

    return ( 1, \@users );
}

sub _load_grants {
    my ($self) = @_;

    my $db_file    = $self->{'_db_files'} || die "_find_psql_db_files_in_restore must be called before _load_grants";
    my $extractdir = $self->extractdir();

    my @grants;

    my $grants_sql_path = "$extractdir/psql_grants.sql";
    if ( -s $grants_sql_path ) {
        local $@;

        my $grants_sql_sr = eval { Cpanel::LoadFile::load_r($grants_sql_path) } or do {
            return ( 0, $@->to_string() );
        };

        foreach my $grant_ref ( @{ Cpanel::PostgresAdmin::Restore::parse_grants_file_sr_from_postgresadmin($grants_sql_sr) } ) {
            my ( $granted, $grantee ) = @{$grant_ref};
            my ($err);
            try {
                Cpanel::Validate::DB::User::verify_pgsql_dbuser_name($grantee);
            }
            catch {
                $err = $_;
            };
            if ($err) {
                $self->warn( $self->_locale()->maketext( "The system is unable to grant privileges for the PostgreSQL username “[_1]” because of an error: [_2]", $grantee, Cpanel::Exception::get_string($err) ) );
                next;
            }
            try {
                Cpanel::Validate::DB::Name::verify_pgsql_database_name($granted);
            }
            catch {
                $err = $_;
            };
            if ($err) {
                $self->warn( $self->_locale()->maketext( "The system is unable to grant privileges for the PostgreSQL database “[_1]” because of an error: [_2]", $granted, Cpanel::Exception::get_string($err) ) );
                next;
            }

            push @grants, { 'granted' => $granted, 'grantee' => $grantee };
        }

        #Only restore grants that pertain to DBs that we're restoring here.
        for my $g ( reverse( 0 .. $#grants ) ) {
            my $grant_hr = $grants[$g];

            if ( !$db_file->{ $grant_hr->{'granted'} } ) {
                splice( @grants, $g, 1 );
                $self->{'_utils'}->add_dangerous_item("PostgreSQL: grant “$grant_hr->{'granted'}” to “$grant_hr->{'grantee'}”");
            }
        }
    }

    return ( 1, \@grants );
}

#For each DB and dbuser, this will avoid naming conflicts with either the
#DB cluster or the account tarball.
#
#For example, if the cluster has:
#   bob
#   bob2
#   bob3
#
#…and the archive to be restored has:
#   bob
#   bob2
#
#…this will create the new items as names that aren't on either list.
#
#In other words, each restored DB has either its old name or a name that doesn't
#exist in either the archive or the DB cluster.
#
#NOTE: NOTHING ELSE ABOUT THE NEW NAMES IS GUARANTEED.
#
sub _get_unique_dbs_and_users {
    my ( $self, $users_ar, $grants_ar ) = @_;

    my $db_file = $self->{'_db_files'} || die "_find_psql_db_files_in_restore must be called before _get_unique_dbs_and_users";

    my $flags_hr = $self->{'_utils'}{'flags'};

    my $dbname_updates_hr = $self->{'_dbname_updates'};
    my $dbuser_updates_hr = $self->{'_dbuser_updates'};

    my $super_dbh = $self->{'pgadmin'}{'dbh'};

    my $stmt = $super_dbh->prepare('SELECT datname FROM pg_database WHERE datname = ?');

    for my $db ( keys %$db_file ) {
        next if exists $dbname_updates_hr->{$db};

        my @taken_names = (

            #Can't name the DB any of the names that are in the archive.
            ( grep { $_ ne $db } keys %$db_file ),

            #Can't name the DB any name that's already been assigned.
            ( values %$dbname_updates_hr ),
        );

        try {
            my $new_db_name = $self->_find_unique_name_variant(
                name       => $db,
                exclude    => \@taken_names,
                statement  => $stmt,
                max_length => $MAX_IDENTIFIER_LENGTH,
            );

            $dbname_updates_hr->{$db} = $new_db_name;
        }
        catch {
            my $err = $_;
            $self->{'_utils'}->add_skipped_item( $self->_locale()->maketext( 'The system failed to find a suitable name for the archive’s PostgreSQL database “[_1]” on this system because of an error: [_2]', $db, Cpanel::Exception::get_string($err) ) );
        };
    }

    #This will prevent dbuser/db naming conflicts because every DB has a dbrole
    #with the same name.
    $stmt = $super_dbh->prepare('SELECT rolname FROM pg_authid WHERE rolname = ?');

    my %users_to_restore_lookup;
    @users_to_restore_lookup{ map { $_->{'username'} } @$users_ar } = ();

    my $olduser     = $self->olduser();
    my $old_dbowner = Cpanel::DB::Utils::username_to_dbowner($olduser);

    #This part looks for users that receive grants but that aren't in the
    #archive's list of users. When it finds a grantee that isn't in the list
    #of users, it adds the grantee to the user list and gives it a password.
    #
    for my $grant_obj (@$grants_ar) {
        if ( !exists $users_to_restore_lookup{ $grant_obj->{'grantee'} } ) {
            my $newuser = $self->newuser();

            my $new_dbowner = Cpanel::DB::Utils::username_to_dbowner($newuser);

            if ( $grant_obj->{'grantee'} eq $old_dbowner && $old_dbowner ne $new_dbowner ) {
                $self->warn(
                    $self->_locale()->maketext( 'Because you assigned this [asis,cPanel] user a different system username ([_1]) than what its archive contains ([_2]), the [asis,PostgreSQL] user “[_3]” will be unable to log in until “[_1]” logs into cPanel or until someone sets [_3]’s [asis,PostgreSQL] password manually.', $newuser, $olduser, Cpanel::DB::Utils::username_to_dbowner($newuser) ) );
            }
            else {
                $self->warn( $self->_locale()
                      ->maketext( "This archive contains an instruction to grant access on the database “[_1]” to a database user named “[_2]”, but the archive’s main list of database users does not contain that username. The system will create the user and restore this grant, but the user will be unable to log in until its password is set.", $grant_obj->{'granted'}, $grant_obj->{'grantee'} ) );
            }

            push @$users_ar, { username => $grant_obj->{'grantee'}, password => Cpanel::Rand::Get::getranddata(32) };
            $users_to_restore_lookup{ $grant_obj->{'grantee'} } = undef;
        }
    }

    #Now that we have a complete list of users to restore, resolve any
    #dbuser name conflicts. $self->{'_dbuser_updates'} will be a fully
    #populated once this is done.
    #
    for my $user_obj (@$users_ar) {

        #We don't store the cpuser's dbuser in this hash.
        next if $user_obj->{'username'} eq $old_dbowner;

        my $username = $user_obj->{'username'};
        next if exists $dbuser_updates_hr->{$username};

        my @taken_names = (

            #Can't have a dbuser with the same name as a db.
            ( values %$dbname_updates_hr ),

            #Reject the other intended dbuser names.
            ( grep { $_ ne $username } map { $_->{'username'} } @$users_ar ),

            #Reject any dbuser name that we've already gotten from this loop.
            ( grep { $_ ne $username } values %$dbuser_updates_hr ),
        );

        try {
            my $new_username = $self->_find_unique_name_variant(
                name       => $username,
                exclude    => \@taken_names,
                statement  => $stmt,
                max_length => $MAX_IDENTIFIER_LENGTH,
            );

            $dbuser_updates_hr->{$username} = $new_username;
        }
        catch {
            my $err = $_;
            $self->{'_utils'}->add_skipped_item( $self->_locale()->maketext( 'The system failed to find a suitable name for the archive’s PostgreSQL database user “[_1]” on this system because of an error: [_2]', $username, Cpanel::Exception::get_string($err) ) );
        };

    }

    return;
}

sub _should_restore_databases {
    my ($self) = @_;

    return $self->{'_should_restore_databases'} if defined $self->{'_should_restore_databases'};

    my $restore_databases = $self->disabled()->{'Postgres'}{'databases'} ? 0 : 1;
    if ( !$restore_databases ) {
        $self->{'_utils'}->add_skipped_item("The restoring of PostgreSQL databases has been disabled (by request)");
    }

    $self->{'_should_restore_databases'} = $restore_databases;

    return $self->{'_should_restore_databases'};
}

*unrestricted_restore = \&restricted_restore;

1;
