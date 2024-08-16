package Cpanel::Mysql;

# cpanel - Cpanel/Mysql.pm                         Copyright 2022 cPanel, L.L.C.
#                                                           All rights reserved.
# copyright@cpanel.net                                         http://cpanel.net
# This code is subject to the cPanel license. Unauthorized copying is prohibited

=encoding utf8

=head1 NAME

C<Cpanel::Mysql>

=head1 DESCRIPTION

This module contains methods and abstractions for connecting to and working with Mysql in cPanel.

=head1 FUNCTIONS

=cut

use cPstrict;

##
##
## Please try to avoid loading Cpanel::MysqlUtils in this module as it
## will increase the memory footprint and startup time of xml-api.
##
##

use parent qw(
  Cpanel::Mysql::Create
);

use Try::Tiny;

use Cpanel::AccessIds::ReducedPrivileges ();
use Cpanel::Autodie                      ();
use Cpanel::Autowarn                     ();
use Cpanel::Context                      ();

# Note: Cpanel::MysqlUtils was avoided
# due to memory concerns
use Cpanel::MysqlUtils::DirName          ();
use Cpanel::MysqlUtils::Grants           ();
use Cpanel::MysqlUtils::Grants::Users    ();
use Cpanel::MysqlUtils::MyCnf::Basic     ();
use Cpanel::MysqlUtils::Compat           ();
use Cpanel::MysqlUtils::Compat::Password ();
use Cpanel::MysqlUtils::Quote            ();
use Cpanel::Mysql::Error                 ();
use Cpanel::Mysql::Privs                 ();
use Cpanel::Mysql::Flush                 ();
use Cpanel::Mysql::Hosts                 ();
use Cpanel::LocaleString                 ();
use Cpanel::Hostname                     ();
use Cpanel::DIp::MainIP                  ();
use Cpanel::DB::Utils                    ();
use Cpanel::Exception                    ();
use Cpanel::PasswdStrength::Check        ();
use Cpanel::PwCache                      ();
use Cpanel::ServerTasks                  ();
use Cpanel::Session::Constants           ();
use Cpanel::Session::Temp::Active        ();
use Cpanel::Validate::DB::Name           ();
use Cpanel::Validate::DB::User           ();

*PASSWORD_PLAINTEXT = \$Cpanel::Mysql::Create::PASSWORD_PLAINTEXT;
*PASSWORD_HASHED    = \$Cpanel::Mysql::Create::PASSWORD_HASHED;

sub running {
    my ($self) = @_;
    return 1 if $self->{'dbh'};
    require Cpanel::MysqlRun;
    goto \&Cpanel::MysqlRun::running;
}

sub getmysqldiskusage {
    my $self = shift;
    return 'NA' if !$self->running();
    my $db_diskusage_hr = $self->diskusage();
    if ( scalar keys %$db_diskusage_hr ) {
        my $total = 0;
        for my $space_used ( values %$db_diskusage_hr ) {
            next unless defined $space_used;
            $total += $space_used;
        }
        return $total;
    }
    elsif ( $self->running() ) {
        return '0';
    }
    else {
        return 'NA';
    }
}

sub diskusage {
    my ($self) = @_;

    my $disk_usage_ref;
    my @dbs = $self->listdbs();
    require Cpanel::Mysql::DiskUsage;

    try {
        $disk_usage_ref = Cpanel::Mysql::DiskUsage->load( $self->{'cpuser'} );

        # If a db is missing from the cache we must rebuild it
        undef $disk_usage_ref if grep { !defined } @{$disk_usage_ref}{@dbs};
    }
    catch {
        if ( !try { $_->isa('Cpanel::CacheFile::NEED_FRESH') } ) {
            local $@ = $_;
            die;
        }
    };

    $disk_usage_ref ||= do {
        my %DISKUSAGE = $self->_diskusage();

        try { Cpanel::Mysql::DiskUsage->save( \%DISKUSAGE, $self->{'cpuser'} ) } catch { local $@ = $_; warn };

        \%DISKUSAGE;
    };

    return $disk_usage_ref;
}

=head2 _diskusage()

Retrieve a hash of database => size_bytes for all databases.
Uses various techniques to retrive this information such as
INFORMATION_SCHEMA or filesystem stat.

=head3 ARGUMENTS

None

=head3 RETURNS

hash - they keys are the database name and the values are the size in bytes

=head3 EXCEPTIONS

=over

=item dies on filesystem read errors

=item possibly rethrows from other methods

=back

=cut

sub _diskusage {
    my $self = shift;

    my @db_list = $self->listdbs();

    return if scalar @db_list == 0;

    # We used to return no disk usage when disk_usage_include_sqldbs was set
    # because we wanted to minimize the frequency of reading
    # information_schema. Now that this function is wrapped behind diskusage
    # and has a cache, this is no longer a concern.
    #
    # IMPORTANT: Callers that are tallying up disk usage are expected to
    # check for disk_usage_include_sqldbs and not call for diskusage if they
    # do not need it.
    #
    my $useinfoschema = exists $self->{'cpconf'}{'use_information_schema'} ? $self->{'cpconf'}{'use_information_schema'} : 1;
    my %DISKUSAGE     = map { $_ => 0 } @db_list;

    if ( !$useinfoschema && $self->is_remote_mysql() ) {
        warn "“use_information_schema” is off. Because MySQL is remote, though, the system must use INFORMATION_SCHEMA to determine MySQL disk usage.\n";
        $useinfoschema = 1;
    }

    if ($useinfoschema) {
        my $db_list_q = join ',', map { $self->safesqlstring($_) } @db_list;

        # INFORMATION_SCHEMA is slow if MySQL < 5.6.6
        # see http://www.percona.com/blog/2013/12/03/innodb_stats_on_metadata-slow-queries-information_schema/
        # Include InnoDB disk Usage
        my $dbh = $self->{'dbh'};
        if ( my $stats_expiry_sql = Cpanel::MysqlUtils::Compat::get_information_schema_stats_expiry() ) {
            $dbh->do($stats_expiry_sql);
        }
        my $query = "select TABLE_SCHEMA as DB,SUM(DATA_LENGTH)+SUM(INDEX_LENGTH) AS SPACEUSED from information_schema.tables WHERE TABLE_SCHEMA IN ($db_list_q) GROUP BY TABLE_SCHEMA;";
        my $q     = $dbh->prepare($query);
        $q->execute();
        while ( my $data = $q->fetchrow_hashref() ) {
            $DISKUSAGE{ $data->{'DB'} } = $data->{'SPACEUSED'};
        }
        $q->finish();
    }
    else {
        my $dbh = $self->{'dbh'};
        my $q   = $dbh->prepare("show variables like '%datadir%';");
        $q->execute();
        my $data    = $q->fetchrow_arrayref();
        my $datadir = $data->[1];
        $q->finish();
        while ( -l $datadir ) {
            $datadir = readlink $datadir;
        }
        if ( $datadir !~ /\/$/ ) { $datadir .= '/'; }
        my @DIRS;

        Cpanel::Autodie::opendir( my $MDD, $datadir );
        push @DIRS, readdir $MDD;
        closedir $MDD;

        # CPANEL-29053: The raw @DIRS cannot be directly compared to the
        # cooked @db_list, so un-cook that before converting to a regex.
        # CPANEL-23938: The match must be anchored to avoid matching a substring of an unrelated database name.
        my $db_regex = '\A(?:' . join( '|', map { quotemeta( Cpanel::MysqlUtils::DirName::database_to_dir($_) ) } @db_list ) . ')\Z';
        @DIRS = grep( /$db_regex/, @DIRS );
        my $i;
        for ( $i = 0; $i <= $#DIRS; $i++ ) {
            $DIRS[$i] = $datadir . $DIRS[$i];
        }
        if ( $#DIRS == -1 ) { return; }
        foreach my $dir (@DIRS) {
            next if ( !-d $dir );    #from case 3859
            my @DS     = split( /\//, $dir );
            my $dbname = Cpanel::MysqlUtils::DirName::dir_to_database( $DS[-1] );
            $DISKUSAGE{$dbname} += ( stat($dir) )[7];

            Cpanel::Autodie::opendir( my $DD, $dir );
            while ( my $file = readdir $DD ) {
                next if ( $file =~ /^\.+$/o );
                $DISKUSAGE{$dbname} += ( stat( $dir . '/' . $file ) )[7];
            }
        }
    }

    return %DISKUSAGE;
}

#NOTE: This does NOT apply a database prefix! (Should it??)
sub create_db {
    my ( $self, $dbname ) = @_;

    local $@;
    if ( !eval { Cpanel::Validate::DB::Name::verify_mysql_database_name($dbname) } ) {
        my $err = $@;
        return ( 0, $self->_log_error_and_output_return( Cpanel::LocaleString->new( '[_1]', $err->to_string() ) ) );
    }

    my $map = $self->_get_map();

    if ( $self->db_exists($dbname) ) {
        return ( 0, $self->_log_error_and_output_return( Cpanel::LocaleString->new( 'The database “[_1]” already exists.', $dbname ) ) );
    }

    $self->{'logger'}->info( "Creating MySQL database $dbname for user " . $self->{'cpuser'} );

    if ( $self->sendmysql( "CREATE DATABASE " . Cpanel::MysqlUtils::Quote::quote_identifier($dbname) ) ) {
        $self->_unlink_user_mysql_db_count();

        unlink( _get_userdatastore_dir( $self->{'cpuser'} ) . '/mysql-db-count' );

        $map->{'owner'}->add_db($dbname);
        $self->_save_map_hash($map);

        $self->updateprivs($dbname);
        $self->queue_dbstoregrants();
        $self->queue_dbindex();

        $self->_clear_disk_usage_cache();

        #Update Privs always reloads the db
        return 1;

    }
    else {
        return ( 0, $self->_log_error_and_output_return( Cpanel::LocaleString->new( 'The system could not create the database “[_1]”.', $dbname ) ) );
    }
}

sub _get_userdatastore_dir ($username) {
    require Cpanel::UserDatastore;
    return Cpanel::UserDatastore::get_path($username);
}

sub _unlink_user_mysql_db_count {
    my ($self) = @_;

    my $privs      = Cpanel::AccessIds::ReducedPrivileges->new( $self->{'cpuser'} );
    my $count_path = Cpanel::PwCache::gethomedir($>) . '/.cpanel/datastore/mysql-db-count';
    Cpanel::Autowarn::unlink($count_path);

    return;
}

#For parity with PostgresAdmin.pm
*raw_create_db = \&create_db;

#Returns an array of arrays: ( [table, msg_type, msg_text], ...)
#Table name does NOT include the database name.
sub repair_database {
    my ( $self, $dbname ) = @_;

    return $self->_db_maintenance( 'REPAIR', $dbname );
}

#Same return structure as repair_database.
sub check_database {
    my ( $self, $dbname ) = @_;

    return $self->_db_maintenance( 'CHECK', $dbname );
}

sub _db_maintenance {
    my ( $self, $op, $dbname ) = @_;

    Cpanel::Context::must_be_list();

    $self->_verify_db_in_map($dbname);

    my $dbh = $self->{'dbh'};

    my $full_w = $dbh->{'mysql_serverversion'} >= 50002 ? 'FULL' : q<>;

    my $dbname_q = $dbh->quote_identifier($dbname);

    my $tbl_q = $dbh->prepare("SHOW $full_w TABLES IN $dbname_q");
    $tbl_q->execute();

    my @ret;

    while ( my @tbl_info = $tbl_q->fetchrow_array() ) {
        next if $full_w && $tbl_info[1] =~ m<view>i;

        my $full_table_q = "$dbname_q." . $dbh->quote_identifier( $tbl_info[0] );

        my $check = $dbh->prepare("$op TABLE $full_table_q");
        $check->execute();
        while ( my @result = $check->fetchrow_array() ) {

            $result[0] =~ s<\A\Q$dbname\E\.><>;

            # Table format is "Table Op(eration) Msg_type Msg_text"
            # Op is always $op, so we discard that column
            splice @result, 1, 1;
            push @ret, \@result;
        }
    }

    return @ret;
}

sub reload_db {
    my $self = shift;

    Cpanel::Mysql::Flush::flushprivs();

    return '';
}

sub rename_database {
    my ( $self, @args ) = @_;

    my $return = $self->SUPER::rename_database(@args);

    $self->_clear_disk_usage_cache();

    return $return;
}

# Even MySQL 5.0 considers mysql.host to be obsolete.
# MySQL 5.6.7 stopped creating it. (MariaDB seems never to have created it.)
sub _has_mysql_host_table {
    my ($self) = @_;

    return 0 < $self->{'dbh'}->do( "SHOW TABLES in `mysql` like ?", undef, 'host' );
}

#This will die() on failure.
#NOTE: This does NOT add a DB prefix.
sub drop_db {
    my ( $self, $dbname ) = @_;

    my $map = $self->_get_map();
    if ( $self->{'cpuser'} ne 'root' && !$map->{'map'}->user_owns_db( $self->{'cpuser'}, $dbname ) ) {
        return $self->_log_error_and_output( Cpanel::LocaleString->new( "The user “[_1]” is not authorized to delete the database “[_2]”.", $self->{'cpuser'}, $dbname ) );
    }

    my $escaped_dbname = Cpanel::MysqlUtils::Quote::escape_pattern($dbname);

    # TODO: Breakout MysqlUtils::Rename::rename_database's code that drops the privs into a module
    # so it can be used below instead
    my $DB_MYSQL = $self->DB_MYSQL();

    #----------------------------------------------------------------------
    #First, remove the DB map entry.

    $map = $self->_get_map();
    $map->{'owner'}->remove_db($dbname);
    $self->_save_map_hash($map);

    #----------------------------------------------------------------------
    #As far as the cPanel user is concerned, the DB is now deleted.
    #Let’s make the DB totals recache:

    my $user_datastoredir = _get_userdatastore_dir( $self->{'cpuser'} );

    my @to_unlink = map { "$user_datastoredir/mysql-$_" } qw(
      db-usage
      disk-usage
      db-count
    );

    $self->_clear_disk_usage_cache();

    for my $f (@to_unlink) {
        next if !-f $f;
        unlink $f or warn "Failed to unlink($f): $!";
    }

    $self->_unlink_user_mysql_db_count();

    #----------------------------------------------------------------------
    #Now remove privileges on the DB.

    # Explicitly specify mysql database when modifying it
    $self->_sendmysql_untrapped( "DELETE FROM $DB_MYSQL.db WHERE Db=?;", {}, $escaped_dbname );

    #Failures here are nonfatal.
    if ( $self->_has_mysql_host_table() ) {
        $self->sendmysql( "DELETE FROM $DB_MYSQL.host WHERE Db=?;", undef, $escaped_dbname );
    }

    $self->_sendmysql_untrapped( "DELETE FROM $DB_MYSQL.tables_priv WHERE Db=?;",  {}, $escaped_dbname );
    $self->_sendmysql_untrapped( "DELETE FROM $DB_MYSQL.columns_priv WHERE Db=?;", {}, $escaped_dbname );

    # Reload permissions for changes to mysql database to take effect
    $self->reload_db();

    $self->queue_dbstoregrants();

    #----------------------------------------------------------------------
    #Finally, delete the database itself.

    $self->{'logger'}->info("Dropping MySQL database “$dbname” for user “$self->{'cpuser'}” …");

    try {
        $self->_sendmysql_untrapped( "DROP DATABASE " . Cpanel::MysqlUtils::Quote::quote_identifier($dbname) );
    }
    catch {
        local $@ = $_;
        die if !try { $_->isa('Cpanel::Exception::Database::Error') };
        die if !$_->failure_is('ER_DB_DROP_EXISTS');
    };

    return 1;
}

sub _clear_disk_usage_cache {
    my ($self) = @_;

    require Cpanel::Mysql::DiskUsage;
    Cpanel::Mysql::DiskUsage->delete( $self->{'cpuser'} );

    return;
}

# dbuser is optional
sub updatehosts {
    my ( $self, $dbuser ) = @_;

    my $map = $self->_get_map();
    if ( length $dbuser && $self->{'cpuser'} ne 'root' && !$map->{'map'}->user_owns_dbuser( $self->{'cpuser'}, $dbuser ) ) {
        return $self->_log_error_and_output( Cpanel::LocaleString->new( "The user “[_1]” is not authorized to update hosts “[_2]”.", $self->{'cpuser'}, $dbuser ) );
    }

    my $althost           = $self->getmysqlalthost();
    my @access_hosts      = Cpanel::Mysql::Hosts::get_system_access_hosts();
    my %CURRENT_HOST_LIST = map { $_ => 1 } $self->listhosts();
    my %hosts_to_add;

    foreach my $access_host (@access_hosts) {
        $hosts_to_add{$access_host} = 1 if !$CURRENT_HOST_LIST{$access_host};
    }

    if ( $althost ne 'localhost' ) {
        my $hostname = Cpanel::Hostname::gethostname();
        my $mainip   = Cpanel::DIp::MainIP::getmainserverip();

        # Only update hosts if not specified in @access_hosts
        $hosts_to_add{$mainip}   = 1 if !$CURRENT_HOST_LIST{$mainip};
        $hosts_to_add{$hostname} = 1 if !$CURRENT_HOST_LIST{$hostname};
    }

    #Only reload the database if we actually did something
    if ( scalar keys %hosts_to_add ) {
        $self->_addhosts( [ keys %hosts_to_add ], $dbuser );
    }
    return ( scalar keys %hosts_to_add );
}

sub updateprivs {
    my ( $self, $dbname ) = @_;

    my $user;

    #approved v2
    {
        my $map = $self->_get_map();

        #TODO: This logic looks suspect...
        #comparing a dbowner to a cpusername should not happen...?

        $user = Cpanel::DB::Utils::username_to_dbowner( $map->{'owner'}->name() );

        if ( $self->{'cpuser'} ne $user ) {
            if ( $self->{'cpuser'} ne 'root' && !$map->{'map'}->user_owns_dbuser( $self->{'cpuser'}, $user ) ) {
                return $self->_log_error_and_output( Cpanel::LocaleString->new( "The user “[_1]” is not authorized to update privileges for “[_2]”.", $self->{'cpuser'}, $user ) );
            }
        }
        if ($dbname) {
            if ( $self->{'cpuser'} ne 'root' && !$map->{'map'}->user_owns_db( $self->{'cpuser'}, $dbname ) ) {
                return $self->_log_error_and_output( Cpanel::LocaleString->new( "The user “[_1]” is not authorized to update privileges for “[_2]” on the database “[_3]”.", $self->{'cpuser'}, $user, $dbname ) );
            }
        }
    }

    my @users      = ($user);
    my $temp_users = Cpanel::Session::Temp::Active::get_all_active_user_temp_sessions( $self->{'cpuser'} );
    if ( $temp_users && @{$temp_users} ) {
        foreach my $temp_user ( @{$temp_users} ) {
            push @users, $temp_user->[0] if $temp_user->[0];
        }
    }

    my ( $password_hashes_status, $user_password_hashes ) = $self->_password_hashes( \@users );

    if ( !$password_hashes_status ) {

        # if $password_hashes_status is false
        # $user_password_hashes is an error string
        return $self->_log_error_and_output( Cpanel::LocaleString->new( "Error encountered while fetching data: [_1]", $user_password_hashes ) );
    }

    if (%$user_password_hashes) {
        my %users_hash =
          map  { $_ => { 'pass' => $user_password_hashes->{$_}{'password'}, 'pass_is_hashed' => 1 } }    # format for _dbowner_to_all
          grep { length $user_password_hashes->{$_} }                                                    # only users that have a password can be processed (should be all of them)
          keys %{$user_password_hashes};

        # Try to get the cpanel users' account password
        # in sync if REMOTE_PASSWORD is available.
        my $envpass = $self->_get_env_pass_if_available();
        if ( !$ENV{'APITOOL'} && $envpass ) {
            $users_hash{$user} = { 'pass' => $envpass, 'pass_is_hashed' => 0 };
        }

        if ( scalar keys %users_hash ) {
            return $self->_dbowner_to_all_with_ownership_checks(
                'method' => 'GRANT',
                'users'  => \%users_hash,
                ( $dbname ? ( 'database' => $dbname ) : () )
            );
        }
    }

    return;
}

#
# drop_user : remove from mysql but not from dbmap
#
# Currently only called form the transfer system to be able
# to remove a user without updating the dbmap.
#  We can likely remove this after the untrusted restore
#  project ships.
#
sub drop_user {
    my ( $self, $drop_user ) = @_;

    return unless defined $drop_user && $drop_user ne '';

    my $map = $self->_get_map();

    # never drop root user
    if ( lc($drop_user) eq 'root' ) {
        return $self->_log_error_and_output( Cpanel::LocaleString->new( "The user “[_1]” is not authorized to drop the user “[_2]”.", $self->{'cpuser'}, $drop_user ) );
    }

    # however they can drop themselves for some reason
    elsif ( $self->{'cpuser'} ne 'root' && $self->{'cpuser'} ne $drop_user && !$map->{'map'}->user_owns_dbuser( $self->{'cpuser'}, $drop_user ) ) {
        return $self->_log_error_and_output( Cpanel::LocaleString->new( "The user “[_1]” is not authorized to drop the user “[_2]”.", $self->{'cpuser'}, $drop_user ) );
    }

    $self->_drop_user($drop_user);

    if ( $drop_user ne $self->{'cpuser'} ) {
        require Cpanel::MysqlUtils::Rename;
        Cpanel::MysqlUtils::Rename::change_definer_of_database_objects( $self->{'dbh'}, $drop_user, $self->{'cpuser'} );
    }

    return '';
}

sub grantable_privileges {
    my ($self) = @_;

    my $privs_hr = Cpanel::Mysql::Privs::get_mysql_privileges_lookup( $self->{'dbh'} );

    my @privs = sort keys %$privs_hr;

    return @privs;
}

#NOTE: The order of arguments here is different from addusertodb().
#NOTE: This does NOT add a prefix.
sub addusertodb_literal_privs {
    my ( $self, $dbuser, $dbname, $privs_ar ) = @_;

    if ($privs_ar) {
        my %valid_privs = Cpanel::Mysql::Privs::get_mysql_privileges_lookup( $self->{'dbh'} );
        $valid_privs{$_} = 1 for ( 'ALL', 'ALL PRIVILEGES' );

        my @invalid = grep { !exists $valid_privs{$_} } @$privs_ar;

        if (@invalid) {
            die Cpanel::Exception::create( 'InvalidParameter', 'The following [numerate,_1,is not a valid MySQL privilege,are not valid MySQL privileges]: [join,~, ,_2]', [ scalar(@invalid), \@invalid ] );
        }
    }
    else {
        $privs_ar = [];
    }

    return $self->_do_addusertodb( $dbuser, $dbname, @$privs_ar );
}

sub _do_addusertodb {
    my ( $self, $dbuser, $dbname, @new_privs ) = @_;

    $self->_verify_db_in_map($dbname);
    $self->_verify_dbuser_in_map($dbuser);

    my $safe_dbname = Cpanel::MysqlUtils::Quote::quote_pattern_identifier($dbname);

    #XXX: Needs better error reporting
    my @HOSTS = $self->_memorized_get_host_list();

    my $privs = join( ',', @new_privs );

    my $dbh = $self->{'dbh'};

    my $row_name = Cpanel::MysqlUtils::Compat::get_mysql_user_auth_field();

    my ($pw_hash) = $dbh->selectrow_array( "SELECT $row_name FROM mysql.user WHERE User=? LIMIT 1", undef, $dbuser );

    # if the user doesn't have a password set, do not add it to the database
    if ( !length $pw_hash ) {
        die Cpanel::Exception->create( 'This system will not add the database user “[_1]” to the database “[_2]” because this user does not have a password.', [ $dbuser, $dbname ] );
    }

    my $grant_obj = Cpanel::MysqlUtils::Grants->new();
    $grant_obj->db_privs($privs);
    $grant_obj->quoted_db_obj('*');    #"quoted" so we don't work on the `*` table.
    $grant_obj->quoted_db_name($safe_dbname);

    my ( @user_hosts_pass_hash_arr, @user_host_arr );
    foreach my $host (@HOSTS) {
        push @user_hosts_pass_hash_arr, { user => $dbuser, host => $host, 'hashed_password' => $pw_hash };
        push @user_host_arr, Cpanel::MysqlUtils::Quote::quote($dbuser) . '@' . Cpanel::MysqlUtils::Quote::quote($host);
    }

    my %current_privs = $self->_usergrants( $dbuser, \@HOSTS );

    my $grant_recipients_sql = join( ' , ', @user_host_arr );
    if ( $current_privs{$dbname} && @{ $current_privs{$dbname} } ) {

        # If the user didn't have privleges to $safe_dbname,
        # which is very likely, an exception was thrown
        $dbh->do("REVOKE ALL ON $safe_dbname.* FROM $grant_recipients_sql; /* addusertodb */");
    }
    if ($privs) {
        foreach my $user_host_pass_hr (@user_hosts_pass_hash_arr) {
            my $usage_grant_req;

            # If a user doesn't exist, CREATE it, so the GRANT will work right after
            my $stored_pw_hash_row = $self->_get_pw_hash_row( $user_host_pass_hr->{'user'}, $user_host_pass_hr->{'host'} );
            if ( !$stored_pw_hash_row ) {
                ## CREATE new user
                $usage_grant_req = $grant_obj->to_string_for_users_manage( 'CREATE', $user_host_pass_hr );
                $dbh->do("$usage_grant_req /* addusertodb */");
            }
        }

        # Now that we know we have all the users created, issue the grants
        my $grant_privs_req = $grant_obj->to_string_for_users(@user_hosts_pass_hash_arr);
        $dbh->do("$grant_privs_req /* addusertodb */");
    }

    my $map = $self->_get_map();
    $map->{'owner'}->add_db_for_dbuser( $dbname, $dbuser );
    $self->_save_map_hash($map);

    $self->queue_dbstoregrants();

    return 1;
}

sub checkbinlog {
    my ($self) = @_;
    return Cpanel::Mysql::Privs::checkbinlog($self);
}

# This fails out if either the DB or the DBuser does not exist.
sub deluserfromdb_fatal {
    my ( $self, $dbname, $dbuser ) = @_;

    if ( $self->{'cpuser'} ne 'root' ) {
        $self->_verify_db_in_map($dbname);
        $self->_verify_dbuser_in_map($dbuser);
    }

    return _deluserfromdb(@_);
}

sub _deluserfromdb {
    my ( $self, $dbname, $dbuser ) = @_;

    my $revoke_recipients_sql = $self->_create_revoke_recipients_sql_for_users( 'REVOKE', { $dbuser => {} } );

    my $map = $self->_get_map();

    my $safe_dbname = Cpanel::MysqlUtils::Quote::quote_pattern_identifier($dbname);
    if ( length $revoke_recipients_sql ) {
        try {
            $self->_sendmysql_untrapped("REVOKE ALL ON $safe_dbname.* FROM $revoke_recipients_sql; /* deluserfromdb */");
        }
        catch {
            local $@ = $_;
            die if !try { $_->failure_is('ER_NONEXISTING_GRANT') };
        };
    }

    $map->{'owner'}->remove_db_for_dbuser( $dbname, $dbuser );
    $self->_save_map_hash($map);

    $self->queue_dbstoregrants();

    return 1;
}

# This will NOT fail if the DB or DBuser exists.
# It will delete all vestiges of the user/DB relationship,
# including DB map and grants.
*deluserfromdb_if_not_exists = \*_deluserfromdb;

#This is actually several operations: an update of the password for the given
#dbuser on every one of the cpuser's access hosts.
#
#Prior to 11.48, this die()d in the event of any failure.
#As of 11.48, it now behaves thus:
#
#- If the first SET PASSWORD fails for a reason other than a missing grant,
#die() with whatever that error was.
#
#- If nothing succeeds and every failure is a missing grant, then die() with a
#UserMissing exception.
#
#- In all other cases return a hashref: {
#   failures => [
#       {
#           host => <string that names the host whose SET PASSWORD failed>,
#           error => <C::Ex::Db::Error object that describes the failure>,
#       },
#   ],
#}
#
#NOTE that this means that even a fully successful call returns a hash with a
#"failures" array--that array will simply be empty in that case.
#
#TODO: create a set_password_hash() method
#
sub set_password {
    my ( $self, $dbuser, $dbpass ) = @_;

    $self->_verify_dbuser_in_map($dbuser);

    Cpanel::PasswdStrength::Check::verify_or_die( app => 'mysql', pw => $dbpass );

    #NOTE: Ideally this would be done in a transaction,
    #but MySQL does an implicit commit on SET PASSWORD.
    #cf. https://dev.mysql.com/doc/refman/5.5/en/implicit-commit.html
    my @failures;
    my $succeeded;

    # We could use _memorized_get_host_list here, but if someone has
    # done a manual GRANT, (as in the unit test) that list is
    # out-of-date.
    foreach my $host ( $self->_get_host_list() ) {
        try {

            Cpanel::MysqlUtils::Compat::Password::set_user_password_dbh(
                dbh      => $self->{'dbh'},
                user     => $dbuser,
                host     => $host,
                password => $dbpass,
            );

            $succeeded++;
        }
        catch {

            #If we haven't already changed state, and if the failure
            #is something besides a missing grant, then go ahead and die().
            die $_ if !$succeeded && !_err_is_missing_grant($_);

            push @failures, { host => $host, error => $_ };
        };
    }

    #If everything failed, and every failure was a missing grant, then
    #the DB map and MySQL are out of sync.
    #
    if ( !$succeeded && !grep { !_err_is_missing_grant( $_->{'error'} ) } @failures ) {
        die "set_password was unexpectedly missing failed hosts." if !@failures;    #Should never happen, but just in case.
        die Cpanel::Exception::create( 'Database::UserMissing', [ name => $dbuser, engine => 'mysql' ] );
    }

    $self->queue_dbstoregrants();

    return { failures => \@failures };
}

#NOTE: static function, NOT a method
sub _err_is_missing_grant {
    my ($err) = @_;

    return undef if !try { $err->isa('Cpanel::Exception::Database::Error') };

    return ( $err->get('error_code') eq Cpanel::Mysql::Error::ER_PASSWORD_NO_MATCH() ) ? 1 : undef;
}

#NOTE: This does NOT add a DB prefix.
sub deluser {
    my ( $self, $dbuser ) = @_;

    return unless defined $dbuser;

    # if you run the mysql delete command with user 'xxx ' then 'xxx' is deleted....
    #    we need to catch it as soon as possible
    $dbuser =~ s/\s+$//;

    my $map = $self->_get_map();

    if ( $dbuser eq Cpanel::DB::Utils::username_to_dbowner( $self->{'cpuser'} ) ) {
        return $self->_log_error_and_output( Cpanel::LocaleString->new( "The user “[_1]” is not authorized to delete its own [asis,MySQL] user ([_2]).", $self->{'cpuser'}, $dbuser ) );
    }

    # nobody can delete the user root...
    if ( !$map->{'map'}->user_owns_dbuser( $self->{'cpuser'}, $dbuser )
        || lc($dbuser) eq 'root' ) {
        return $self->_log_error_and_output( Cpanel::LocaleString->new( "The user “[_1]” is not authorized to delete user “[_2]”.", $self->{'cpuser'}, $dbuser ) );
    }

    $self->_drop_user($dbuser);

    $map = $self->_get_map();
    $map->{'owner'}->remove_dbuser($dbuser);
    $self->_save_map_hash($map);

    if ( $dbuser ne $self->{'cpuser'} ) {
        require Cpanel::MysqlUtils::Rename;
        Cpanel::MysqlUtils::Rename::change_definer_of_database_objects( $self->{'dbh'}, $dbuser, $self->{'cpuser'} );
    }

    $self->queue_dbstoregrants();

    return 1;
}

sub get_innodb_status {
    my $self = shift;
    my @status;

    my $dbh = $self->{'dbh'};
    my $q   = $dbh->prepare('SHOW ENGINE INNODB STATUS;');
    $q->execute or return;
    while ( my $data = $q->fetchrow_arrayref ) {
        last if ( $data->[0] =~ m/ERROR/i );
        push @status, $data->[0];
    }
    $q->finish();
    return @status;
}

sub delhost {
    my ( $self, $host ) = @_;

    $self->clear_memorized_hosts_lists();    # clear the memorized hosts if we add one
                                             #approved v2
    my %user_list = map { $_ => 1 } $self->{'cpuser'}, $self->listusers();

    my $user_hosts_map = Cpanel::MysqlUtils::Grants::Users::get_all_hosts_for_users( $self->{'dbh'}, [ keys %user_list ] );

    require Cpanel::Mysql::Remote::Notes;
    my $notes_obj = Cpanel::Mysql::Remote::Notes->new(
        username => $self->{'cpuser'},
    );
    $notes_obj->delete($host);

    foreach my $user ( keys %{$user_hosts_map} ) {
        if ( grep { $_ eq $host } @{ $user_hosts_map->{$user} } ) {
            my $err;

            try {
                $self->_sendmysql_untrapped( "DROP USER ?@? /* delhost */;", undef, $user, $host );
            }
            catch {
                $err = $_;
            };

            $self->_has_error_handler($err) if $err;
        }
    }

    $self->queue_dbstoregrants();

    return;
}

#TODO: Could we just use listprivs() here?
sub _get_dbuser_privileges_on_db {
    my ( $self, $dbuser, $dbname ) = @_;

    my ( $err, @grants );
    try {
        @grants = $self->{'dbh'}->show_grants( $dbuser, Cpanel::MysqlUtils::MyCnf::Basic::get_grant_host() );
    }
    catch {
        if ( !try { $_->failure_is('ER_NONEXISTING_GRANT') } ) {
            $err = $_;
        }
    };

    return ( [], undef ) if $err;    # ok as they may not have any grants

    my $quoted_dbname = Cpanel::MysqlUtils::Quote::quote_pattern_identifier($dbname);

    my $hashed_password;
    my @privs;

    for my $grant_txt (@grants) {
        my $grant;

        try {
            $grant = Cpanel::MysqlUtils::Grants->new($grant_txt);
        }
        catch {
            $self->{'logger'}->warn("Error ($_) while parsing grant: $grant_txt");
        };

        next if !$grant;

        if ( $grant->db_privs() eq 'USAGE' ) {
            try { $hashed_password = $grant->hashed_password() };
            next;
        }
        next if $grant->quoted_db_name() ne $quoted_dbname;

        @privs = split m{\s*,\s*}, $grant->db_privs();
        last;
    }

    return ( \@privs, $hashed_password );
}

sub addhost {
    my ( $self, $host ) = @_;

    return $self->addhosts( [$host] );
}

sub addhosts {
    my ( $self, $hosts_ref ) = @_;

    return $self->_addhosts($hosts_ref);
}

sub _addhosts {
    my ( $self, $hosts_ref, $adminuser ) = @_;

    return 1 if not @$hosts_ref;

    $self->clear_memorized_hosts_lists();    # clear the memorized hosts if we add one

    my @safe_hosts = grep { length $_ && $_ ne 'NULL' } map { $self->safesqlstring( $_, 1 ) } @{$hosts_ref};

    return if !@safe_hosts;

    my $map     = $self->_get_map();
    my $dbowner = Cpanel::DB::Utils::username_to_dbowner( $adminuser || $map->{'owner'}->name() );

    my @USERS   = $self->listusers();
    my @DBS     = $self->listdbs();
    my %DBUSERS = $self->listusersindb(@DBS);

    my %ALLUSERS = map { $_ => 1 } ( @USERS, $dbowner );

    my ( $password_hashes_status, $user_password_hashes ) = $self->_password_hashes( [ keys %ALLUSERS ] );

    if ( !$password_hashes_status ) {

        # if $password_hashes_status is false
        # $user_password_hashes is an error string
        return $self->_log_error_and_output( Cpanel::LocaleString->new( "Error encountered while fetching data: [_1]", $user_password_hashes ) );
    }

    #Just create one object and change its properties to get each GRANT statement.
    my $grant_obj = Cpanel::MysqlUtils::Grants->new();
    $grant_obj->db_privs('USAGE');
    $grant_obj->quoted_db_obj('*');    #"quoted" so we don't work on the `*` table.
    $grant_obj->quoted_db_name('*');

    my @user_hosts;
    my @user_hosts_alter;
    foreach my $host (@$hosts_ref) {
        foreach my $dbuser ( keys %ALLUSERS ) {
            my $hashed_dbpass = $user_password_hashes->{$dbuser}{'password'};
            next if !$hashed_dbpass;

            my $stored_pw_hash_row = $self->_get_pw_hash_row( $dbuser, $host );
            if ($stored_pw_hash_row) {
                my $stored_pw_hash = $stored_pw_hash_row->[0];

                # If it exists and the pass hasn't changed, no need to do anything
                next if $stored_pw_hash eq $hashed_dbpass;

                # If it exists but the pass hash changed, add it to the list of users we'll be ALTERing
                push @user_hosts_alter, { user => $dbuser, host => $host, 'hashed_password' => $hashed_dbpass };
            }
            else {
                # This is a new user, so add it to the list we'll CREATE
                push @user_hosts, { user => $dbuser, host => $host, 'hashed_password' => $hashed_dbpass };
            }
        }
    }
    return if !@user_hosts && !@user_hosts_alter;    # There may be not users with passwords at this point

    for my $user_host_hr (@user_hosts) {
        my $usage_grant_req = $grant_obj->to_string_for_users_manage( 'CREATE', $user_host_hr );
        $self->_do_sql_for_addhosts($usage_grant_req);
    }
    for my $user_host_hr (@user_hosts_alter) {
        my $usage_grant_req = $grant_obj->to_string_for_users_manage( 'ALTER', $user_host_hr );
        $self->_do_sql_for_addhosts($usage_grant_req);
    }

    # Now combine all the privs into a hash so we can do a grant for each priv set.
    my %DBPRIVS;
    foreach my $dbname (@DBS) {
        foreach my $dbuser ( @{ $DBUSERS{$dbname} }, $dbowner ) {
            my ( $privs_ar, $hashed_dbpass ) = $self->_get_dbuser_privileges_on_db( $dbuser, $dbname );
            next if !@$privs_ar;
            my $privs_str = join ', ', sort @$privs_ar;
            $DBPRIVS{$dbname}{$privs_str}{$dbuser} = 1;
        }
    }

    foreach my $dbname ( keys %DBPRIVS ) {
        foreach my $privs_str ( keys %{ $DBPRIVS{$dbname} } ) {
            my @dbusers_with_privset = keys %{ $DBPRIVS{$dbname}{$privs_str} };

            $grant_obj->db_privs($privs_str);
            $grant_obj->db_name($dbname);    #NOT "quoted" this time!

            foreach my $host (@$hosts_ref) {
                foreach my $dbuser (@dbusers_with_privset) {
                    my $priv_user_host  = { user => $dbuser, host => $host };
                    my $privs_grant_req = $grant_obj->to_string_for_users($priv_user_host);

                    $self->_do_sql_for_addhosts($privs_grant_req);
                }
            }
        }
    }

    $self->queue_dbstoregrants();

    return;
}

# This returns an arrayref so we can distinguish
# “user exists but has no password” from “user doesn’t exist”.
sub _get_pw_hash_row ( $self, $dbuser, $host ) {
    my $auth_field_sql = Cpanel::MysqlUtils::Compat::get_mysql_user_auth_field();

    my $sql = "SELECT $auth_field_sql FROM mysql.user WHERE BINARY user=? AND BINARY host=?";
    my $dbh = $self->{'dbh'};

    return $dbh->selectrow_arrayref( $sql, undef, $dbuser, $host );
}

sub _do_sql_for_addhosts ( $self, $command ) {
    local $@;
    eval { $self->dbh_do("$command /* _addhosts */"); 1 } or do {
        $self->{'logger'}->warn("GRANT statement “$command” failed: $@");
    };

    return;
}

sub countdbs {
    my $self = shift;
    my @DBS  = $self->listdbs();

    if (@DBS) {
        return scalar @DBS;
    }
    elsif ( $self->running() ) {
        return '0';
    }
    else {
        return 'NA';
    }
}

sub listusersindb {
    my $self = shift;
    my %DBUSERS;

    my $map = $self->_get_map();
    foreach my $db ( $map->{'owner'}->dbs() ) {
        foreach my $user ( $db->users() ) {
            next if $user->name() =~ m{^\Q$Cpanel::Session::Constants::TEMP_USER_PREFIX\E};
            next if $user->name() eq $map->{'owner'}->name();
            push @{ $DBUSERS{ $db->name() } }, $user->name();
        }
    }

    return %DBUSERS;
}

sub listprivs {
    my ( $self, $user, $host, $checkdb ) = @_;

    die "Need a user!" if !length $user;

    $self->_verify_dbuser_in_map($user);

    $host ||= 'localhost';

    my %PRIVS;

    my $dbh = $self->{'dbh'};

    my @grant_txts;
    eval { @grant_txts = $dbh->show_grants( $user, $host ); 1 } or do {
        if ( !try { $@->failure_is('ER_NONEXISTING_GRANT') } ) {
            die $self->_log_error_and_output_return( Cpanel::LocaleString->new( "Error encountered while fetching data: [_1]", scalar $@->to_string() ) );
        }
    };

    for my $grant (@grant_txts) {
        my $gobj = Cpanel::MysqlUtils::Grants::parse($grant) or next;
        next if $gobj->quoted_db_name() eq '*';

        next if length $checkdb && $gobj->db_name() ne $checkdb;

        $PRIVS{ $gobj->db_name() } = $gobj->db_privs() =~ s<\A\s+|\s+\z><>gr;
    }

    return %PRIVS;
}

sub get_mysql_server_privs {
    my ( $self, $user, $host, $include_admin ) = @_;

    $host ||= 'localhost';

    my @privs;
    my $parse_privilege = sub {
        my ( $privilege, $context, $comment ) = @_;

        return if !$include_admin && $context =~ m{admin}i;

        #MySQL returns privileges here capitalized, not allcaps.
        #Applications generally expect these strings to be allcaps.
        push @privs, [ uc $privilege, $comment ];
    };

    my $data = [];
    my $dbh  = $self->{'dbh'};
    my $q    = $dbh->prepare('SHOW PRIVILEGES;');
    eval {
        $q->execute;
        while ( $data = $q->fetchrow_arrayref ) {
            $parse_privilege->( @{$data} );
        }
        $q->finish();
    };

    return @privs;
}

sub dbcache {
    my ( $self, $skip_update ) = @_;

    if ($skip_update) {
        $self->updatehosts();
    }
    else {
        $self->updateprivs();
    }

    my @DBS = $self->listdbs();

    if (@DBS) {
        my $diskused;
        my $disk_usage_ref = $self->diskusage();
        foreach my $db ( keys %$disk_usage_ref ) {
            $diskused += ( $disk_usage_ref->{$db} ||= 0 );
            print "DBDISKUSED\t$db\t$disk_usage_ref->{$db}\n";
        }
        print "DISKUSED\t$diskused\n";
    }
    else {
        print "DISKUSED\t0\n";
    }

    my %DBUSERS = $self->listusersindb(@DBS);
    foreach my $db (@DBS) {
        print "DB\t${db}\n";
        foreach my $user ( @{ $DBUSERS{$db} } ) {
            print "DBUSER\t${db}\t${user}\n";
        }
    }
    foreach my $user ( $self->listusers() ) {
        print "USER\t${user}\n";
        my %PRIVS = $self->listprivs( $user, 'localhost' );
        foreach my $db ( keys %PRIVS ) {
            print "PRIVS\t${user}\t${db}\t$PRIVS{$db}\n";
        }
    }
    print map { "HOST\t$_\n" } $self->listhosts();
    my $althost = $self->getmysqlalthost();
    print "ALTHOST\t${althost}\n";
    print "ISREMOTE\t" .  ( $self->is_remote_mysql() ) . "\n";
    print "ISRUNNING\t" . ( $self->running() ) . "\n";

    return;
}

# Either:
#
#   - Cpanel::Mysql::safesqlstring("abc'def", $strip_end_quotes_yn)
#   - $cp_mysql_obj->safesqlstring("abc'def", $strip_end_quotes_yn)
#
# The 2nd argument is a boolean that controls whether to strip the
# leading/trailing quotes from the quoted string. So if that value
# is truthy, then instead of “'abc\'def'” you’ll get just “abc\'def”.
#
sub safesqlstring {
    my $self = shift;

    my $safe;
    if ( $self->{'dbh'} && $self->{'dbh'}->can('quote') ) {
        $safe = $self->{'dbh'}->quote(shift);
    }
    elsif ( ref $self eq __PACKAGE__ ) {
        $safe = Cpanel::MysqlUtils::Quote::quote(shift);
    }
    else {    # so the old style will work
        $safe = Cpanel::MysqlUtils::Quote::quote($self);
    }

    $safe =~ s/^'|'$//g if shift();
    return $safe;
}

sub routines {
    my ( $self, $database_user ) = @_;

    my @stash = $self->list_routines($database_user);

    if ( scalar @stash ) {
        my $routines = join ', ', @stash;
        return $routines;
    }
    return $self->sendmysql( 'use ' . $self->DB_MYSQL() );
}

=head2 list_routines([$database_user])

Retrieve a list of routines for a single user or all database users and hosts.
Uses the definer column in INFORMATION_SCHEMA.ROUTINES to find routines where the definer is user@host
If no $database_users is specified all users and hosts for the account are considered.

=head3 ARGUMENTS

=over

=item database_user - string - OPTIONAL

Valid database user. When passed, only routines available to that user are returned.

=back

=head3 RETURNS

In list context it returns a list of strings  - The list of routines prefixed with the database name they are associated with.

In scalar context it returns the number of routines in the list.

=head3 EXCEPTIONS

=over

=item only rethrows from other methods

=back

=cut

sub list_routines {
    my ( $self, $database_user ) = @_;

    my @stash;
    my @user_list = $self->listusersandhosts();
    my @definers;

    for my $entry (@user_list) {

        my ( $user, $host ) = @{$entry};
        if ( defined($database_user) ) {
            if ( $user eq $database_user ) {
                push @definers, $self->safesqlstring( sprintf( "%s@%s", $user, $host ) );
            }
        }
        else {
            push @definers, $self->safesqlstring( sprintf( "%s@%s", $user, $host ) );
        }

    }

    if ( scalar @definers ) {
        my $user_list = join ",", @definers;
        my $dbh       = $self->{'dbh'};

        $self->sendmysql('use information_schema');
        my $sth = $dbh->prepare(qq/SELECT ROUTINE_SCHEMA, ROUTINE_NAME FROM ROUTINES WHERE DEFINER IN ($user_list);/);
        $sth->execute();

        while ( my $data = $sth->fetchrow_arrayref ) {
            push @stash, $data->[0] . '.' . $data->[1];
        }
    }

    return @stash;

}

sub db_exists {
    my ( $self, $db ) = @_;

    my $dbh = $self->{'dbh'};

    my $sth = $dbh->prepare(qq/SHOW DATABASES WHERE `Database` = ?/);
    $sth->execute($db);

    my @stash;
    while ( my $data = $sth->fetchrow_arrayref() ) {
        push @stash, $data->[0];
    }
    return scalar @stash;
}

sub _password_hashes {
    my ( $self, $users ) = @_;

    my %user_passes;
    foreach my $user (@$users) {
        my ( $privs_ar, $hashed_dbpass ) = $self->_get_dbuser_privileges_on_db($user);
        if ($hashed_dbpass) {
            $user_passes{$user} = { 'password' => $hashed_dbpass };
        }
    }

    # We want to return an empty list if there
    # is no error since the user may not have
    # been created yet.  This is specifically important
    # for updateprivs because it currently gets called before
    # the dbowner is created.
    if ( !scalar keys %user_passes && $DBI::errstr ) {
        $self->{'logger'}->warn($DBI::errstr);
        return ( 0, $DBI::errstr );
    }
    else {
        return ( 1, \%user_passes );
    }
}

#Consider using test_login_credentials() instead.
sub test_password {
    my ( $self, $dbuser, $pass ) = @_;

    my $map = $self->_get_map();
    if ( $self->{'cpuser'} ne 'root' && !$map->{'map'}->user_owns_dbuser( $self->{'cpuser'}, $dbuser ) ) {
        return $self->_log_error_and_output( Cpanel::LocaleString->new( "The user “[_1]” is not authorized to access user “[_2]” to test the password.", $self->{'cpuser'}, $dbuser ) );
    }

    return $self->_test_login_credentials_without_dbmap_check( $dbuser, $pass );
}

sub test_login_credentials {
    my ( $self, $dbuser, $pass ) = @_;

    $self->_verify_dbuser_in_map($dbuser);

    return $self->_test_login_credentials_without_dbmap_check( $dbuser, $pass );
}

sub _test_login_credentials_without_dbmap_check {
    my ( $self, $dbuser, $pass ) = @_;

    my $dbh = $self->{'dbh'};

    my $row_name = Cpanel::MysqlUtils::Compat::get_mysql_user_auth_field();

    # NOTE: The PASSWORD function does not exist on MySQL 8 and there is no
    # alternative to replace it.
    # As such, do what the source code does. '*' . HEX(SHA1(SHA1($PASSWORD)))
    require Cpanel::MysqlUtils::Password;
    my $pw_hash = Cpanel::MysqlUtils::Password::native_password_hash($pass);
    my $data    = $dbh->selectrow_hashref( "SELECT User FROM mysql.user WHERE User=? AND $row_name = ? LIMIT 1;", {}, $dbuser, $pw_hash );

    return ref $data ? 1 : 0;
}

sub fetch_temp_users {
    my ($self) = @_;

    my $dbh = $self->{'dbh'};

    require Cpanel::Database;
    my $key_field = Cpanel::Database->new()->fetch_temp_users_key_field;
    my $data      = $dbh->selectall_hashref( "SELECT user FROM mysql.user WHERE user LIKE 'cpses\\_%';", $key_field );

    my $err = $dbh->errstr();

    return ( 0, $err ) if $err;
    return ( 1, $data );
}

sub queue_dbindex {
    my ($self) = @_;

    return if $self->{'disable_queue_dbindex'};

    Cpanel::ServerTasks::schedule_task( ['MysqlTasks'], 3, 'dbindex' );
    return 1;
}

sub rename_dbuser {
    my ( $self, $oldname, $newname ) = @_;

    my $ret = $self->SUPER::rename_dbuser( $oldname, $newname );

    return $ret;
}

sub _rename_dbuser_in_server {
    my ( $self, $oldname, $newname ) = @_;

    Cpanel::Validate::DB::User::verify_mysql_dbuser_name($newname);
    require Cpanel::MysqlUtils::Rename;

    my $ret;
    try {
        $ret = Cpanel::MysqlUtils::Rename::rename_user( $self->{'dbh'}, $oldname, $newname );
    }
    catch {
        if ( UNIVERSAL::isa( $_, 'Cpanel::Exception::Database::UserNotFound' ) ) {
            die Cpanel::Exception::create( 'Database::UserMissing', [ name => $oldname, engine => 'mysql' ] );
        }

        die $_;
    };

    return $ret;
}

sub _rename_database_in_server {
    my ( $self, $oldname, $newname ) = @_;

    Cpanel::Validate::DB::Name::verify_mysql_database_name($newname);
    require Cpanel::MysqlUtils::Rename;

    my $ret;
    try {
        $ret = Cpanel::MysqlUtils::Rename::rename_database( $self->{'dbh'}, $oldname, $newname );
    }
    catch {
        if ( $_ && ( $_->get('error_code') // '' eq Cpanel::Mysql::Error::ER_BAD_DB_ERROR() ) ) {

            die Cpanel::Exception::create( 'Database::DatabaseMissing', [ name => $oldname, engine => 'mysql' ] );
        }

        die $_;
    };

    return $ret;
}

sub _drop_user {
    my ( $self, $drop_user ) = @_;

    my ($err);
    try {
        Cpanel::MysqlUtils::Grants::Users::drop_user_in_mysql( $self->{'dbh'}, $drop_user );
    }
    catch {
        $err = $_;
    };

    # For legacy compat, we trap and log the error instead of generating an exception
    if ($err) {
        $self->_log_error_and_output( Cpanel::LocaleString->new( "The system failed to drop the MySQL user “[_1]” because of an error: [_2]", $drop_user, Cpanel::Exception::get_string($err) ) );
    }

    return;
}

1;
