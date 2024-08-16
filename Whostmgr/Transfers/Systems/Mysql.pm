package Whostmgr::Transfers::Systems::Mysql;

# cpanel - Whostmgr/Transfers/Systems/Mysql.pm     Copyright 2022 cPanel, L.L.C.
#                                                           All rights reserved.
# copyright@cpanel.net                                         http://cpanel.net
# This code is subject to the cPanel license. Unauthorized copying is prohibited

use cPstrict;

# RR Audit: JNK

use Try::Tiny;

use Cpanel::Imports;

use Cpanel::Autodie                      ();
use Cpanel::Exception                    ();
use Cpanel::Carp                         ();
use Cpanel::DB::Map                      ();
use Cpanel::DB::Utils                    ();
use Cpanel::DIp::MainIP                  ();
use Cpanel::FileUtils::Dir               ();
use Cpanel::Hostname                     ();
use Cpanel::LoadFile                     ();
use Cpanel::LocaleString                 ();
use Cpanel::Mysql                        ();
use Cpanel::Mysql::Hosts                 ();
use Cpanel::Mysql::Remote::Notes         ();
use Cpanel::MysqlUtils::Grants           ();
use Cpanel::MysqlUtils::Support          ();
use Cpanel::MysqlUtils::Unquote          ();
use Cpanel::MysqlUtils::Version          ();
use Cpanel::MysqlUtils::Support          ();
use Cpanel::MysqlUtils::Suspension       ();
use Cpanel::Rand::Get                    ();
use Cpanel::Validate::DB::Name           ();
use Cpanel::Validate::DB::User           ();
use Cpanel::Validate::LineTerminatorFree ();
use Cpanel::MysqlUtils::MyCnf::Basic     ();

use parent qw(
  Whostmgr::Transfers::SystemsBase::MysqlBase
);

use constant {
    get_relative_time => 3,
    map_engine        => 'MYSQL',

    # CPANEL-15457: Done before Roundcube, since Roundcube restore will blow away cpuser MySQL password.
    get_prereq => [ 'Roundcube', 'MysqlRemoteNotes' ],

    get_phase                => 40,
    get_restricted_available => 1,
};

our $FIRST_MYSQL_VERSION_TO_BLOCK_OLD_PASSWORDS = 5.6;

our $MAX_DBNAME_LENGTH;
*MAX_DBNAME_LENGTH = \$Cpanel::Validate::DB::Name::max_mysql_dbname_length;

my $mysql_grants_file = 'mysql.sql';

my @REJECT_DBS = qw(
  *
  mysql
);

my @SILENTLY_IGNORE_DBS = (
    'logaholic',    #No longer supported in the product
    'roundcube',    #Now handled in a separate module
);

sub get_summary {
    my ($self) = @_;
    return [ $self->_locale()->maketext('This restores [asis,MariaDB]/[asis,MySQL] databases, users, and grants.') ];
}

sub unrestricted_restore {
    my ($self) = @_;

    #    my ( $map_ok, $map_msg ) = $self->_restore_dbmap();
    #    return ( 0, $map_msg ) if !$map_ok;

    return $self->_restore_mysql();
}

{
    no warnings 'once';
    *restricted_restore = \&unrestricted_restore;
}

sub _restore_mysql {
    my ($self) = @_;

    #'locale' just makes data dumps cumbersome to scroll through.
    delete $self->{'locale'};

    $self->start_action("Preparing MySQL restore …");

    my ( $init_ok, $err ) = $self->_init();
    return ( 0, $err ) if !$init_ok;

    my $extractdir = $self->extractdir();
    my ( $dir_err, $dir_nodes_ar );
    if ( -d $self->_archive_mysql_dir() ) {
        try {
            $dir_nodes_ar = Cpanel::FileUtils::Dir::get_directory_nodes( $self->_archive_mysql_dir() );
        }
        catch {
            $dir_err = $_;
        };
        return ( 0, $self->_locale()->maketext( "The system failed to examine the archive’s MySQL data directory because of an error: [_1]", $dir_err->to_string() ) ) if $dir_err;
    }
    $self->debug( "MySQL Archive dir: " . $self->_archive_mysql_dir() );

    my @DB_FILES = $dir_nodes_ar ? ( grep { m{\.sql\z} } @$dir_nodes_ar ) : ();
    my %db_file_to_orig_name;
    foreach my $db_file (@DB_FILES) {
        my ( $orig_db_name, $name_error );
        try {
            $orig_db_name = $self->_get_db_name_from_path($db_file);
            $self->debug("Found DB to restore: $orig_db_name");
        }
        catch {
            $name_error = $_;
        };
        if ($name_error) {
            $self->{'_utils'}->add_skipped_item( $self->_locale()->maketext( 'The system could not restore the MySQL database file “[_1]” because of an error: [_2]', $db_file, Cpanel::Exception::get_string($name_error) ) );
            next;
        }
        $db_file_to_orig_name{$db_file} = $orig_db_name;
    }

    $self->{'_archive_dbnames'} = [@DB_FILES];
    s{\.sql\z}{} for @{ $self->{'_archive_dbnames'} };

    require Cpanel::Services::Enabled;
    if ( !Cpanel::Services::Enabled::is_provided("mysql") ) {
        $self->debug("MySQL is disabled, saving grants and returning...");

        $self->save_databases_in_homedir('mysql') if @DB_FILES;
        return $self->_restore_grants_file();
    }

    my $init_err;
    try {
        $self->_init_self_variables();
    }
    catch {
        $init_err = $_;
    };

    if ($init_err) {
        $self->save_databases_in_homedir('mysql') if @DB_FILES;
        return ( 0, Cpanel::Exception::get_string($init_err) );
    }

    if ( $self->_should_restore_databases() ) {
        $self->_set_dbname_updates_hash( [ values %db_file_to_orig_name ] );

        $self->_determine_dbname_updates_for_restore_and_overwrite();
    }
    else {
        # even if they do not want to restore any databases, we need to map a
        # user to mysql for this user.

        $self->_map_cpuser_to_dbs( () );

        my @current_dbs;

        #We’re restoring a DB map, so we’ll use the tarball’s DB list.
        #But first we verify that the database actually exists.
        if ( $self->_should_restore_dbmap() ) {
            for my $dbname ( values %db_file_to_orig_name ) {
                if ( $self->{'_dbh_with_root_privs'}->db_exists($dbname) ) {
                    push @current_dbs, $dbname;
                }
                else {
                    $self->{'_utils'}->add_skipped_item( $self->_locale()->maketext( 'The archive contains a database named “[_1]”. Because no [asis,MySQL]/[asis,MariaDB] database with that name exists, the system will not restore this database.', $dbname ) );
                }
            }
        }

        #Not restoring a DB map means we’re just using what the account
        #already has set up.
        else {
            @current_dbs = $self->_do_cpanel_mysql_with_newuser_privs( sub { my ($mysql_obj_with_cpuser_privs) = @_; return $mysql_obj_with_cpuser_privs->listdbs(); } );
        }

        my %updates;
        @updates{@current_dbs} = @current_dbs;
        $self->{'_dbname_updates'} = \%updates;
    }

    my $grants_to_restore_ar = [];

    if ( -e "$extractdir/$mysql_grants_file" ) {
        my ( $ok, $grants_ar ) = $self->_read_and_sanitize_grants_for_dbs();

        if ($ok) {
            $grants_to_restore_ar = $grants_ar;
        }
        else {
            $self->warn( $self->_locale()->maketext( 'The system failed to read the archive’s [output,asis,MySQL] grants because of an error: [_1]', $grants_ar ) );
        }
    }

    if ( $self->_should_restore_databases() ) {
        $self->_restore_databases_and_map_them_to_cpuser( \%db_file_to_orig_name );
    }
    elsif ( $self->_should_restore_dbmap() ) {
        $self->_map_cpuser_to_dbs( values %{ $self->{'_dbname_updates'} } );
    }

    # This has always done nothing as users may not drop themselves
    # $self->_remove_grants_for_dbowner_with_temp_password();

    $self->_restore_dbowner_password_and_privs();

    $self->_determine_dbuser_updates_for_restore_and_overwrite();

    if ( $grants_to_restore_ar && @$grants_to_restore_ar ) {
        if ( !$self->_should_restore_databases() && $self->_should_restore_dbmap() ) {
            $self->_map_dbs_to_dbusers($grants_to_restore_ar);
        }
        else {
            $self->_restore_grants($grants_to_restore_ar);
        }
    }

    # Case HB-5555: Ensure "extra" local IPs are added to the list of hosts to restore, so the temp users created have their passwords ALTERed
    my $all_known_hosts_hr     = Cpanel::Mysql::Hosts::get_hosts_lookup();
    my $remote_hosts_hr        = $self->_get_hosts_from_remote_notes();
    my $combined_hosts_list_hr = { %$all_known_hosts_hr, %$remote_hosts_hr };
    $self->_restore_hosts($combined_hosts_list_hr);

    # Case CPANEL-11700: Ensure restored MySQL users aren't in a suspended state
    # This needs to happen after _restore_hosts() because only then
    # are all of the cpuser’s password hashes correct.
    Cpanel::MysqlUtils::Suspension::unsuspend_mysql_users( $self->newuser() );

    $self->start_action('Storing MySQL Grants');

    $self->_queue_dbstoregrants();

    return 1;
}

sub _get_hosts_from_remote_notes {
    my ($self) = @_;

    my $notes_obj = Cpanel::Mysql::Remote::Notes->new( username => $self->newuser() );

    my %note_hash = $notes_obj->get_all();

    my %host_hash = map { $_ => 1 } keys %note_hash;

    return \%host_hash;
}

sub _restore_grants_file {

    my ($self) = @_;

    $self->warn( $self->_locale()->maketext("[asis,MySQL]/[asis,MariaDB] is not enabled on this system. Restoring only the user’s grants file …") );

    $self->debug("Reading grant data from archive...");
    my ( $grants_ok, $grant_objs ) = $self->_read_raw_grant_objects_from_archive();
    return ( $grants_ok, $grant_objs ) if !$grants_ok;

    require Cpanel::MysqlUtils::MyCnf::Basic;
    my $mysql_host = Cpanel::MysqlUtils::MyCnf::Basic::getmydbhost() || 'localhost';

    foreach my $grant (@$grant_objs) {
        my $grant_host = $grant->db_host();
        $self->debug("Checking whether grant host $grant_host is valid...");
        if ( $grant_host ne $mysql_host ) {

            require Cpanel::Validate::DB::Host;
            if ( !Cpanel::Validate::DB::Host::mysql_host($grant_host) ) {
                $self->{'_utils'}->add_skipped_item( $self->_locale()->maketext( '“[_1]” is not a valid [output,asis,MySQL] host. The system will not restore grants pertaining to it.', $mysql_host ) );
                next;
            }

            $grant->db_host($mysql_host);
        }

    }

    $self->debug("Restoring grants file...");
    require Cpanel::DB::GrantsFile;
    my $grants_obj = Cpanel::DB::GrantsFile->new( $self->newuser() );
    $grants_obj->set_mysql_grants_as_objects($grant_objs)->save();

    return 1;
}

#This is relevant only when we directly create the mappings,
#which only seems to need to happen when the source and destination
#server use the same remote MySQL server.
sub _map_dbs_to_dbusers {
    my ( $self, $grants_ar ) = @_;

    my $map = $self->_get_mysql_map_object();

    my $dbserver = Cpanel::MysqlUtils::MyCnf::Basic::get_server();

    my $owner = $map->get_owner();
    for my $grant (@$grants_ar) {

        #Don’t need to restore USAGE grants because those
        #don’t go in the DB map.
        next if $grant->db_privs() eq 'USAGE';

        my $dbuser = $grant->db_user();

        #The cpuser already has full access to the DBs.
        next if $dbuser eq $self->newuser();

        my $dbname = $grant->db_name();

        if ( !defined $self->{'_dbuser_updates'}{$dbuser} ) {
            $self->{'_utils'}->add_skipped_item( $self->_locale()->maketext( 'Because no [asis,MySQL]/[asis,MariaDB] user named “[_1]” exists, the system will not restore the following grant: [_2]', $dbuser, $grant->to_string() ) );
            next;
        }

        if ( !defined $self->{'_dbname_updates'}{$dbname} ) {
            $self->{'_utils'}->add_skipped_item( $self->_locale()->maketext( 'Because no [asis,MySQL]/[asis,MariaDB] database named “[_1]” exists, the system will not restore the following grant: [_2]', $dbname, $grant->to_string() ) );
            next;
        }

        $owner->add_dbuser(
            {
                dbuser => $dbuser,
                server => $dbserver,
            }
        );
        $owner->add_db_for_dbuser( $dbname, $dbuser );
    }

    $map->save();

    $self->_queue_dbstoregrants();

    return;
}

sub _make_updated_names_hash {
    my ( $self, $names_ar, $stmt, $max_length ) = @_;

    my ( %updates, @failed );

    for my $name (@$names_ar) {
        next if exists $updates{$name};

        my %taken;
        $taken{ ( grep { $_ ne $name } @$names_ar ), values %updates } = ();

        try {
            $updates{$name} = $self->_find_unique_name_variant(
                name       => $name,
                exclude    => [ keys %taken ],
                statement  => $stmt,
                max_length => $max_length,
            );
        }
        catch {
            push @failed, { name => $name, error => $_ };
        };
    }

    return ( \%updates, \@failed );
}

sub _dbname_uniqueness_check_dbi_stmt {
    my ($self) = @_;

    my $mysql_dbh_with_root_privs = $self->{'_dbh_with_root_privs'};

    return $mysql_dbh_with_root_privs->prepare('SELECT SCHEMA_NAME FROM INFORMATION_SCHEMA.SCHEMATA WHERE SCHEMA_NAME = ?');
}

sub _dbuser_uniqueness_check_dbi_stmt {
    my ($self) = @_;

    my $mysql_dbh_with_root_privs = $self->{'_dbh_with_root_privs'};

    return $mysql_dbh_with_root_privs->prepare("SELECT GRANTEE FROM INFORMATION_SCHEMA.USER_PRIVILEGES WHERE SUBSTRING(GRANTEE, 1, LENGTH(QUOTE(?))) = QUOTE(?)");
}

sub _set_dbname_updates_hash {
    my ( $self, $names_ar ) = @_;

    my @filtered_names;
    for my $name (@$names_ar) {
        next if grep { $_ eq $name } @SILENTLY_IGNORE_DBS, @REJECT_DBS;
        push @filtered_names, $name;
    }

    my $failed_ar;
    ( $self->{'_dbname_updates'}, $failed_ar ) = $self->_make_updated_names_hash(
        \@filtered_names,
        $self->_dbname_uniqueness_check_dbi_stmt(),
        $MAX_DBNAME_LENGTH,
    );

    for my $failure (@$failed_ar) {
        $self->{'_utils'}->add_skipped_item( $self->_locale()->maketext( 'The system failed to find a suitable name for the archive’s MySQL database “[_1]” on this system because of an error: [_2]', $failure->{'name'}, Cpanel::Exception::get_string( $failure->{'error'} ) ) );
    }

    return $self->{'_dbname_updates'};
}

sub _set_dbuser_updates_hash {
    my ( $self, $names_ar ) = @_;

    if ( $self->{'_utils'}->{'flags'}->{'shared_mysql_server'} ) {
        my $dbh = $self->{'_dbh_with_root_privs'};

        my @names_to_map;
        for my $name (@$names_ar) {
            if ( $dbh->user_exists( $name, 'localhost' ) ) {
                push @names_to_map, $name;
            }
            else {
                $self->{'_utils'}->add_skipped_item( $self->_locale()->maketext( 'The archive contains a user named “[_1]”. Because no [asis,MySQL]/[asis,MariaDB] user with that name exists, the system will not restore this user.', $name ) );
            }
        }

        my %dummy;
        @dummy{@names_to_map} = @names_to_map;

        $self->{'_dbuser_updates'} = \%dummy;
    }
    else {
        my $failed_ar;
        ( $self->{'_dbuser_updates'}, $failed_ar ) = $self->_make_updated_names_hash(
            $names_ar,
            $self->_dbuser_uniqueness_check_dbi_stmt(),
            Cpanel::Validate::DB::User::get_max_mysql_dbuser_length(),
        );

        for my $failure (@$failed_ar) {
            $self->{'_utils'}->add_skipped_item( $self->_locale()->maketext( 'The system failed to find a suitable name for the archive’s MySQL database user “[_1]” on this system because of an error: [_2]', $failure->{'name'}, Cpanel::Exception::get_string( $failure->{'error'} ) ) );
        }
    }

    return $self->{'_dbuser_updates'};
}

sub _restore_grants {
    my ( $self, $grants_to_restore_ref ) = @_;

    $self->start_action('Restoring MySQL grants');
    $self->{'_archive_dbusers'} = [ map { $_->db_user() } @$grants_to_restore_ref ];

    my %dbusers;
    my @privileges;

    my %former_dbuser_name;

    ( $self->{'_dbh_version'} ) ||= Cpanel::MysqlUtils::MyCnf::Basic::get_server_version( $self->{'_dbh_with_root_privs'} );

    $self->debug("Checking grant information for details on what to do...");
    for my $grant_obj ( @{$grants_to_restore_ref} ) {
        next if $self->{'_failed_db_restore'}{ $grant_obj->db_name() };

        #Already done as the new user has already been granted access to all databases
        #by call add_dbowner_to_all.
        next if $grant_obj->db_user() eq Cpanel::DB::Utils::username_to_dbowner( $self->{'_old_cpuser'} );

        #Update this since it hasn't happened yet.
        my $new_dbuser = $self->new_dbuser_name( $grant_obj->db_user() );
        $former_dbuser_name{$new_dbuser} = $grant_obj->db_user();
        $self->debug("Looks like we can restore grants for '$former_dbuser_name{$new_dbuser}' as '$new_dbuser' without conflicts.");

        try {
            $dbusers{$new_dbuser}{'hashed_password'} = $grant_obj->hashed_password();
            $self->debug("Discovered hashed password information from grants for '$new_dbuser'.");
        }
        catch {
            try {
                $dbusers{$new_dbuser}{'password'} = $grant_obj->password();
                $self->debug("Discovered password from grants for '$new_dbuser'.");
            };
        };

        #This has already been updated.
        my $new_database = $grant_obj->db_name();

        my @new_privs = grep { $_ ne 'USAGE' } split m<\s*,\s*>, $grant_obj->db_privs();

        if (@new_privs) {
            push @privileges, [ $new_dbuser, $new_database, \@new_privs ];
            $self->debug( "Discovered restoreable grant for '$new_dbuser': " . join( ', ', @new_privs ) );
        }
    }

    # We must get rid of old passwords or
    # the passwduser_hash function will
    # fail without a visible error to the user
    # as it only goes to the error log.
    #
    # MySQL 5.6 will not allow old passwords to be used EVEN IF secure_auth is disabled
    #
    # > grep secure_auth /etc/my.cnf
    # secure_auth=0
    #
    # mysql> grant usage on *.* to 'happydog'@'localhost' identified by '__HIDDEN__';
    # ERROR 1827 (HY000): The password hash doesn't have the expected format. Check if the correct password algorithm is being used with the PASSWORD() function.
    $self->debug("Checking for old-style passwords or hexed password data...");

    foreach my $dbuser ( keys %dbusers ) {

        # Check to see if hash is in hex format and convert it back if needed
        my $hash_plugin_type = Cpanel::MysqlUtils::Grants::identify_hash_plugin( $dbusers{$dbuser}{'hashed_password'}, 0 );
        if ( $hash_plugin_type eq 'hex' ) {
            $self->debug("Hexed password detected for '$dbuser'. Unhexing.");
            $dbusers{$dbuser}{'hashed_password'} = Cpanel::MysqlUtils::Grants::unhex_hash( $dbusers{$dbuser}{'hashed_password'} );
        }

        if ( $self->_is_old_password( $dbusers{$dbuser}{'hashed_password'} )
            && Cpanel::MysqlUtils::Version::is_at_least( $self->{'_dbh_version'}, $FIRST_MYSQL_VERSION_TO_BLOCK_OLD_PASSWORDS ) ) {
            $self->debug("Old style password detected for '$dbuser'. Changing to random string.");
            delete $dbusers{$dbuser}{'hashed_password'};
            $dbusers{$dbuser}{'password'} = Cpanel::Rand::Get::getranddata(32);
            $self->warn(
                $self->_locale()->maketext(
                    "The system changed the password for the database user “[_1]” to a random string because the original password used an old and insecure format that is incompatible with MySQL version ([_2]). You must manually change the password for “[_1]” to match the original password in order to ensure that applications that use the credentials will continue to function.",
                    $dbuser, $self->{'_dbh_version'}
                )
            );
        }
    }

    my @restored_dbusers;
    $self->_do_cpanel_mysql_with_newuser_privs(
        sub {
            my ($mysql_obj_with_cpuser_privs) = @_;

            foreach my $new_dbuser ( keys %dbusers ) {
                my ( $ok, $err );

                my $former_name = $former_dbuser_name{$new_dbuser};

                if ( $new_dbuser eq $former_name ) {
                    if ( $self->system_already_has_dbuser_with_name($new_dbuser) ) {
                        my $former_owner = $self->get_preexisting_system_dbuser_owner($new_dbuser);
                        if ( defined $former_owner ) {
                            if ( $former_owner ne $self->newuser() ) {
                                $self->out( $self->_locale()->maketext( 'The system will overwrite [_1]’s database user “[_2]”.', $former_owner, $new_dbuser ) );
                                my $mysql = Cpanel::Mysql->new( { cpuser => $former_owner } );
                                $mysql->deluser($new_dbuser);
                            }
                        }
                        else {
                            $self->debug("Renaming old user out of the way for '$new_dbuser'.");
                            $self->_rename_dbuser_out_of_the_way($new_dbuser);
                        }
                    }
                }

                # Using passwduser & passwduser_hash instead of manipulating
                # 'pwstring' actually takes more code, so why bother. Just
                # set the property since it isn't private.
                my $user_exists = $mysql_obj_with_cpuser_privs->user_exists($new_dbuser) ? 1 : 0;
                local $mysql_obj_with_cpuser_privs->{'pwstring'} = $dbusers{$new_dbuser}->{password};
                my $spiel = $user_exists ? "create user" : "set password for";
                $self->debug("Attempting to $spiel '$new_dbuser'");
                ( $ok, $err ) = $mysql_obj_with_cpuser_privs->passwduser( $new_dbuser, $dbusers{$new_dbuser}->{password} || $dbusers{$new_dbuser}->{hashed_password}, $user_exists );

                if ($ok) {
                    push @restored_dbusers, $new_dbuser;
                    $self->debug( "Restored DB Users: " . join( ', ', @restored_dbusers ) );
                }
                else {
                    $self->warn($err);
                }
            }

            while (@privileges) {
                my ( $dbuser, $db, $privs_ar );

                try {
                    while ( my $priv = shift @privileges ) {
                        ( $dbuser, $db, $privs_ar ) = @$priv;
                        $self->debug( "Now we are restoring grant for '$dbuser' on $db: " . join( ', ', @$privs_ar ) );
                        $mysql_obj_with_cpuser_privs->addusertodb_literal_privs( $dbuser, $db, $privs_ar );
                    }
                }
                catch {
                    $self->warn( $self->_locale()->maketext( 'The system failed to grant privileges on the database “[_1]” to the user “[_2]” because of an error: [_3]', $db, $dbuser, Cpanel::Exception::get_string($_) ) );
                };
            }

            return;
        },
    );

    for my $newname (@restored_dbusers) {
        my $oldname = $former_dbuser_name{$newname};

        $self->{'_restored_dbusers'}{$oldname} = $newname;

        if ( $oldname ne $newname ) {
            $self->{'_utils'}->add_altered_item(
                $self->_locale()->maketext( "The system has restored the MySQL user “[_1]” as “[_2]”.", $oldname, $newname ),
                [
                    $self->_locale()->maketext("Rename"),
                    '/scripts5/manage_database_users',
                    { engine => 'mysql', name => $newname },
                ],
            );
        }
    }
    return;
}

sub _rename_dbuser_out_of_the_way {
    my ( $self, $username ) = @_;

    return $self->__rename_out_of_the_way(
        obj_name             => $username,
        statement            => 'SELECT 1 FROM mysql.user WHERE user = ?',
        max_length           => Cpanel::Validate::DB::User::get_max_mysql_dbuser_length(),
        exclude              => [ grep { defined } $self->_get_new_dbuser_names() ],
        does_not_exist_cr    => sub { UNIVERSAL::isa( $_, 'Cpanel::Exception::Database::UserNotFound' ) },
        rename_func_name     => 'rename_user',
        will_rename_phrase   => Cpanel::LocaleString->new('The system will rename the unmanaged database user “[_1]” to “[_2]”.'),
        failed_rename_phrase => Cpanel::LocaleString->new('The system failed to rename “[_1]” because of an error: [_2]'),
    );
}

sub _get_db_name_from_path {
    my ( $self, $db_file_path ) = @_;

    Cpanel::Validate::LineTerminatorFree::validate_or_die($db_file_path);

    my ($dbname) = ( $db_file_path =~ m{(?:.*/)?(.*)\z} );

    $dbname =~ s<\.sql\z><>;

    return $dbname;
}

sub _get_and_verify_new_dbname ( $self, $orig_dbname ) {
    my $dbname = $self->new_dbname_name($orig_dbname);

    my ($tryerr);
    try {
        Cpanel::Validate::DB::Name::verify_mysql_database_name($dbname);
    }
    catch {
        $tryerr = $_;
    };
    if ($tryerr) {
        my $err_msg = $self->_locale()->maketext( "The system cannot restore the MySQL database “[_1]” because of an error: [_2]", $dbname, Cpanel::Exception::get_string($tryerr) );
        $self->warn($err_msg);
        return ( 0, $err_msg );
    }

    return ( 1, $dbname );
}

sub _restore_db_file {
    my ( $self, %opts ) = @_;

    my $orig_dbname  = $opts{'old_db_name'};
    my $dbname       = $opts{'new_db_name'};
    my $db_file_path = $opts{'file'};

    Cpanel::Autodie::open( my $sql_fh, '<', $db_file_path );

    $self->out( locale()->maketext( "The database restoration subprocess for “[_1]” has opened the [asis,SQL] archive.", $dbname ) );

    my %db = (
        old_name => $orig_dbname,
        name     => $dbname,
        sql_fh   => $sql_fh,
    );

    # Case 106681
    # Postgres and Mysql handle db creation differently.
    # pkgacct passes a db_name.create and a db_name.sql file
    # over for Mysql.   If the db_name does not exist on the
    # original machine the db_name.create file exists without
    # a create database statement, a non trivial noop file.
    # We only process the .create file for charset info.
    # To tell if the db existed on the original file I need to
    # look in the create file for the create database statement.

    my $create_db_fname = $self->_archive_mysql_dir() . "/$orig_dbname.create";
    if ( -e $create_db_fname ) {
        my $IN;
        my $found_create_statement = 0;

        if ( open $IN, "<", $create_db_fname ) {
            $found_create_statement = grep /^\s*CREATE\s+DATABASE\b/i, <$IN>;
            close $IN;
        }

        if ( !$found_create_statement ) {

            # we have a non trivial noop file

            return ( 0, $self->_locale()->maketext( "The MySQL backup for the database “[_1]” is empty.", $dbname ) );
        }
    }

    my ( $ok, $err ) = $self->_create_db_and_import_as_newuser_from_fh( \%db );

    close $sql_fh;
    $self->out( locale()->maketext( "The database restoration subprocess for “[_1]” has closed the [asis,SQL] archive.", $dbname ) );

    if ( !$ok ) {
        return ( 0, "The system failed to reinstall the MySQL database “$orig_dbname” as “$dbname” because of an error: $err\n" );
    }

    return ( 1, $orig_dbname, $dbname );
}

sub _read_raw_grant_objects_from_archive {
    my ($self) = @_;
    if ( !$self->{'_grant_objects'} ) {
        my $extractdir  = $self->extractdir();
        my $grants_file = "$extractdir/$mysql_grants_file";

        # In the future, if we use a JSON dump of this data, this is where we should load it
        my @grants;
        if ( -s $grants_file ) {

            #TODO: Max size?
            my $import_grants_sql = Cpanel::LoadFile::loadfile($grants_file) or do {

                return ( 0, $self->_locale()->maketext( 'The system failed to load the file “[_1]” because of an error: [_2]', $grants_file, $! ) );
            };
            my @lines = split m{\n}, $import_grants_sql;

            # Just skip the "-- cPanel mysql backup" string
            my $index = 0;

            # Don't ceaselessly spam warnings in
            # t/integration/Whostmgr-Transfers-Systems-Mysql.t
            $index++ until ( !@lines || !$lines[$index] || index( $lines[$index], '-' ) == 0 );

            splice( @lines, $index, 1 );

            s{\A\s+|\s+\A}{}g for @lines;

            # DLM: Is this safeor even needed now?
            Cpanel::MysqlUtils::Unquote::unquote_pattern_identifier($_) for @lines;

            # s/\\\_/\_/g for @lines;
            local $SIG{'__DIE__'} = sub { };

            #Only accept lines that create a grant that points to the database.
            #Ignore everything else.
            @grants = map {
                try { Cpanel::MysqlUtils::Grants->new($_) } || ();
            } @lines;
        }

        $self->{'_grant_objects'} = \@grants;
    }

    return ( 1, $self->{'_grant_objects'} );
}

#Multi-arg return
#
#Payload (i.e., what's after the boolean) on success is a list of:
#   - restored grants (array ref)
#   - hosts to add (lookup hashref)
#
#NOTE: This will update the DB name in the grants that it returns.
#
sub _read_and_sanitize_grants_for_dbs {
    my ($self) = @_;
    die "_dbname_updates must be set first!" if !$self->{'_dbname_updates'};

    my ( $grants_ok, $grant_objs ) = $self->_read_raw_grant_objects_from_archive();
    return ( 0, $grant_objs ) if !$grants_ok;

    # Only accept dbs that have not been skipped
    my @dbs_to_accept = grep { !$self->should_skip_db($_) } keys %{ $self->{'_dbname_updates'} };

    my @db_matching_grant_objs;
    ( $self->{'_dbh_version'} ) ||= Cpanel::MysqlUtils::MyCnf::Basic::get_server_version( $self->{'_dbh_with_root_privs'} );
    for my $grant_obj (@$grant_objs) {

        if ( $grant_obj->db_privs() eq 'USAGE' ) {

            push @db_matching_grant_objs, $grant_obj;
        }
        else {
            my @dbs = grep { $grant_obj->matches_db_name($_) } @dbs_to_accept;
            for my $db (@dbs) {
                my $new_obj = Cpanel::MysqlUtils::Grants->new( $grant_obj->to_string() );
                $new_obj->db_name($db);
                push @db_matching_grant_objs, $new_obj;
            }

# TP TASK 23427: This is likely misleading to the user.  Since this shouldn't really affect them we have disabled showing
# this message.  The message is left as a comment as it does a good job of explaining what is going on above.
#if ( $grant_obj->db_name_has_wildcard() && @dbs ) {
#    my @privs = split m<\s*,\s*>, $grant_obj->db_privs();
#
#    my @mt_args = (
#        \@privs,
#        scalar(@privs),
#        $grant_obj->db_name_pattern(),
#        scalar(@dbs),
#        \@dbs,
#    );
#
#    $self->{'_utils'}->add_altered_item(
#        $self->_locale()->maketext( ## no extract maketext (for commented out code)
#            "This account backup contains a grant of the [list_and_quoted,_1] [numerate,_2,privilege,privileges] on any MySQL database that matches the pattern “[_3]”. For proper security, this system will only create [numerate,_4,an individual grant,individual grants] of [numerate,_2,that privilege,those privileges] on the [quant,_4,database,databases] from the archive that [numerate,_4,matches,match] the pattern. [numerate,_4,That database is,Those databases are] [list_and_quoted,_5].",
#            @mt_args
#        ),
#    );
#}
        }
    }

    # The EVENT and TRIGGER privileges were added in the same version 5.1.6
    my $server_supports_events_and_triggers = Cpanel::MysqlUtils::Support::server_supports_events( $self->{'_dbh_with_root_privs'} );

    my $local_host = Cpanel::Hostname::gethostname();
    my $local_ip   = Cpanel::DIp::MainIP::getmainserverip();

    my (@grants_to_restore);

    my %add_hosts = (
        $local_host => 1,
        $local_ip   => 1,
    );

    #NOTE: Leaving this in in case we decide to exclude privileges
    #in the future.
    #my %priv_is_allowed = (
    #    Cpanel::Mysql::Privs::get_mysql_privileges_lookup($dbh),
    #    'ALL'            => 1,
    #    'ALL PRIVILEGES' => 1,
    #);

  GRANT_OBJ:
    for my $grant (@db_matching_grant_objs) {

        next if !$grant || !$grant->db_privs();

        my $db_user = $grant->db_user();
        my ($err);
        try {
            Cpanel::Validate::DB::User::verify_mysql_dbuser_name($db_user);
        }
        catch {
            $err = $_;
        };
        if ($err) {
            $self->warn( $self->_locale()->maketext( "The system cannot grant privileges to the MySQL user “[_1]” because of an error: [_2]", $db_user, Cpanel::Exception::get_string($err) ) );
            next GRANT_OBJ;
        }

        my $quoted_old_db_name = $grant->quoted_db_name();
        my $old_db_name        = $grant->db_name();
        my $db;

        #Allow GRANT USAGE statements.
        if ( $quoted_old_db_name eq '*' && $grant->db_privs() eq 'USAGE' ) {
            $db = $quoted_old_db_name;
        }

        #Otherwise, only restore the grant if the DB was also restored.
        else {
            $db = $self->new_dbname_name($old_db_name);
            if ( !$self->_check_if_db_is_restored_and_warn_about_non_grant_restoration($old_db_name) ) {
                next GRANT_OBJ;
            }
        }

        if ( $db ne $old_db_name ) {
            $grant->db_name($db);
        }

        unless ( $db eq '*' && $grant->db_privs() eq 'USAGE' ) {
            try {
                Cpanel::Validate::DB::Name::verify_mysql_database_name($db);
            }
            catch {
                $err = $_;
            };
            if ($err) {
                $self->warn( $self->_locale()->maketext( "The system cannot grant privileges on the MySQL database “[_1]” because of an error: [_2]", $db, Cpanel::Exception::get_string($err) ) );
                next GRANT_OBJ;
            }
        }

        if ( $grant->db_privs() ne 'USAGE' ) {
            if ( grep { $_ eq $db } @REJECT_DBS ) {
                $self->warn("Unable to grant privileges to MySQL database “$db”. USAGE is the only general privilege allowed.");
                next GRANT_OBJ;
            }
            elsif ( !$server_supports_events_and_triggers && $grant->db_privs() =~ /(?:EVENT|TRIGGER)/i ) {
                $self->warn("Unable to grant privileges to MySQL user “$db_user”. EVENT and TRIGGER privileges are not supported before MySQL version 5.1.6.");
                next GRANT_OBJ;
            }
        }

        #If the db_host isn’t the system’s MySQL host, we pull it out into
        #%add_hosts and do it later (outside/past this function).
        my $grant_host = Cpanel::MysqlUtils::Unquote::unquote_identifier( $grant->db_host() );
        if ( $grant_host ne $self->{'_mysql_host'} ) {
            require Cpanel::Validate::DB::Host;
            if ( Cpanel::Validate::DB::Host::mysql_host($grant_host) ) {
                $add_hosts{$grant_host} = 1;
            }
            else {
                $self->{'_utils'}->add_skipped_item( $self->_locale()->maketext( '“[_1]” is not a valid [output,asis,MySQL] host. The system will not restore grants pertaining to it.', $self->{'_mysql_host'} ) );

                next GRANT_OBJ;
            }
            $grant->db_host( $self->{'_mysql_host'} );
        }

        push @grants_to_restore, $grant;
    }

    $self->_set_dbuser_updates_hash( [ map { $_->db_user() } @grants_to_restore ] );
    return ( 1, \@grants_to_restore, \%add_hosts );
}

sub _get_user_mysql_password_hash_from_archive {
    my ($self) = @_;

    if ( !exists $self->{'_user_mysql_password_hash'} ) {
        my ( $grants_ok, $grants_ar ) = $self->_read_raw_grant_objects_from_archive();
        return ( 0, $grants_ar ) if !$grants_ok;

        for my $grant (@$grants_ar) {
            next if $grant->db_user() ne $self->{'_old_cpuser'};

            my $pw_hash = try { $grant->hashed_password() };
            next if !$pw_hash;

            $self->{'_user_mysql_password_hash'} = $pw_hash;
            last;
        }

        $self->{'_user_mysql_password_hash'} ||= undef;
    }

    return ( 1, $self->{'_user_mysql_password_hash'} );
}

sub _queue_dbstoregrants {
    my ($self) = @_;

    my $ok = $self->_do_cpanel_mysql_with_newuser_privs(
        sub {
            my ($mysql_obj_with_cpuser_privs) = @_;

            local $mysql_obj_with_cpuser_privs->{'disable_queue_dbstoregrants'} = 0;

            return $mysql_obj_with_cpuser_privs->queue_dbstoregrants();
        }
    );

    if ( !$ok ) {
        $self->warn("The system failed to store grants.");
    }

    return 1;
}

sub _should_restore_dbmap {
    my ($self) = @_;

    $self->_should_restore_databases();

    return $self->{'_should_restore_dbmap'};
}

sub _should_restore_databases {
    my ($self) = @_;

    return $self->{'_should_restore_databases'} if defined $self->{'_should_restore_databases'};

    my $restore_databases = $self->disabled()->{'Mysql'}{'databases'} ? 0 : 1;
    my $restore_dbmap     = $self->disabled()->{'Mysql'}{'databases'} ? 0 : 1;

    if ( !$restore_databases ) {
        $self->{'_utils'}->add_skipped_item("MySQL database restoration is disabled (by request)");
    }
    if ( $self->{'_utils'}->{'flags'}->{'shared_mysql_server'} ) {
        $self->out( $self->_locale()->maketext('The system will not restore [output,asis,MySQL] databases because this system shares a [output,asis,MySQL] server with the source system.') );
        $restore_databases = 0;
    }

    $self->{'_should_restore_databases'} = $restore_databases;
    $self->{'_should_restore_dbmap'}     = $restore_dbmap;

    return $self->{'_should_restore_databases'};
}

sub _restore_dbowner_password_and_privs {
    my ($self) = @_;
    $self->start_action('Restoring MySQL privileges');

    #If the cpanel user's MySQL password was stored in the archive,
    #attempt to retrieve it and restore it below.
    #NOTE: We retrieve here rather than later because the segment below is,
    #at least as of March 2014, setUID.
    my ( $hashed_ok, $hashed_password ) = $self->_get_user_mysql_password_hash_from_archive();

    my $dbowner = Cpanel::DB::Utils::username_to_dbowner( $self->newuser() );

    # We must get rid of old passwords or
    # the add_dbowner_to_all function will
    # fail without a visible error to the user
    # as it only goes to the error log.
    #
    # MySQL 5.6 will not allow old passwords to be used EVEN IF secure_auth is disabled
    #
    # > grep secure_auth /etc/my.cnf
    # secure_auth=0
    #
    # mysql> grant usage on *.* to 'happydog'@'localhost' identified by '__HIDDEN__';
    # ERROR 1827 (HY000): The password hash doesn't have the expected format. Check if the correct password algorithm is being used with the PASSWORD() function.

    ( $self->{'_dbh_version'} ) ||= Cpanel::MysqlUtils::MyCnf::Basic::get_server_version( $self->{'_dbh_with_root_privs'} );
    if (   $hashed_ok
        && $self->_is_old_password($hashed_password)
        && Cpanel::MysqlUtils::Version::is_at_least( $self->{'_dbh_version'}, $FIRST_MYSQL_VERSION_TO_BLOCK_OLD_PASSWORDS ) ) {
        undef $hashed_password;

        $self->warn(
            $self->_locale()->maketext(
                "The system changed the password for the database user “[_1]” to a random string because the original password used an old and insecure format that is incompatible with MySQL version ([_2]). You must manually change the password for “[_1]” to match the original password in order to ensure that applications that use the credentials will continue to function.", $dbowner,
                $self->{'_dbh_version'}
            )
        );
    }

    return $self->_do_cpanel_mysql_with_newuser_privs(
        sub {
            my ($mysql_obj_with_cpuser_privs) = @_;

            if ($hashed_ok) {

                #The "1" indicates that the password is hashed.
                $mysql_obj_with_cpuser_privs->add_dbowner_to_all( $dbowner, $hashed_password, $Cpanel::Mysql::PASSWORD_HASHED );
            }
            else {
                $mysql_obj_with_cpuser_privs->add_dbowner_to_all( $dbowner, $self->_user_temp_mysql_passwd(), $Cpanel::Mysql::PASSWORD_PLAINTEXT );
            }

            #Add $newuser's privs for all DBs.
            return $mysql_obj_with_cpuser_privs->updateprivs();
        },
    );
}

sub _get_mysql_map_object {
    my ($self) = @_;

    # Allow creation of the DB map since we’re in the middle
    # of creating/restoring an account.

    return Cpanel::DB::Map->new_allow_create(
        {
            cpuser => $self->newuser(),
            db     => 'MYSQL',
        }
    );
}

sub _map_cpuser_to_dbs {
    my ( $self, @restored_databases ) = @_;

    my $mysql_map = $self->_get_mysql_map_object();

    my $mysql_owner = $mysql_map->get_owner( { owner => $self->newuser(), server => scalar Cpanel::MysqlUtils::MyCnf::Basic::get_server() } );
    $mysql_owner->add_db($_) for @restored_databases;
    $mysql_map->save();

    return 1;
}

sub _restore_databases_and_map_them_to_cpuser {
    my ( $self, $dbfiles_ref ) = @_;
    my @restored_databases;

    die "No!" if !$self->_should_restore_databases();

    $self->start_action('Restoring MySQL databases');

    for my $fs_node ( keys %{$dbfiles_ref} ) {
        my $old_db_name = $dbfiles_ref->{$fs_node};

        next if grep { $_ eq $old_db_name } @SILENTLY_IGNORE_DBS;

        # means we didn't restore it in this step
        next if $self->should_skip_db($old_db_name);

        if ( grep { $_ eq $old_db_name } @REJECT_DBS ) {
            $self->out("Skipping restore of “$old_db_name” database. Not allowed.");
            $self->{'_utils'}->add_dangerous_item("MySQL: skipped restore of “$old_db_name”.");
            next;
        }

        my $new_db_name = $self->new_dbname_name($old_db_name);

        my ($tryerr);
        try {
            Cpanel::Validate::DB::Name::verify_mysql_database_name($new_db_name);
        }
        catch {
            $tryerr = $_;
        };
        if ($tryerr) {
            $self->warn( $self->_locale()->maketext( "The system cannot restore the MySQL database “[_1]” because of an error: [_2]", $new_db_name, Cpanel::Exception::get_string($tryerr) ) );
            next;
        }

        my ( $ok, $err ) = $self->_restore_db_from_wherever( $old_db_name, $fs_node );

        if ($ok) {
            push @restored_databases, $new_db_name;
        }
        else {
            $self->{'_failed_db_restore'}{$new_db_name} = 1;
            $self->warn($err);
        }
    }

    $self->start_action('Restoring MySQL database mappings');
    $self->_map_cpuser_to_dbs(@restored_databases);

    return 1;
}

sub _restore_db_from_wherever ( $self, $orig_dbname, $fs_node ) {
    my ($ok);

    ( $ok, my $dbname ) = $self->_get_and_verify_new_dbname($orig_dbname);
    return ( $ok, $dbname ) if !$ok;

    my @other_returns;

    if ( $self->_should_stream_mysql_db() ) {
        ( $ok, @other_returns ) = $self->_restore_db_via_stream(
            old_db_name => $orig_dbname,
            new_db_name => $dbname,
        );
    }
    else {
        ( $ok, @other_returns ) = $self->_restore_db_file(
            'file'        => $self->_archive_mysql_dir() . "/$fs_node",
            'old_db_name' => $orig_dbname,
            'new_db_name' => $dbname,
        );
    }

    if ($ok) {
        $self->{'_restored_databases'}{$orig_dbname} = $dbname;

        if ( $orig_dbname ne $dbname ) {
            $self->{'_utils'}->add_altered_item(
                $self->_locale()->maketext( "The system has restored the MySQL database “[_1]” as “[_2]”.", $orig_dbname, $dbname ),
                [
                    $self->_locale()->maketext("Rename"),
                    '/scripts5/manage_databases',
                    { engine => 'mysql', name => $dbname },
                ],
            );
        }
    }

    return ( $ok, @other_returns );
}

sub _should_stream_mysql_db ($self) {
    return !!$self->{'_utils'}{'flags'}{'mysql_stream'};
}

sub _restore_db_via_stream ( $self, %opts ) {
    my $stream_config = $self->{'_utils'}{'flags'}{'mysql_stream'};

    if ( $stream_config->{'method'} eq 'plain' ) {
        my @func_opts = (
            api_token             => $stream_config->{'api_token'},
            api_token_username    => $stream_config->{'api_token_username'},
            api_token_application => $stream_config->{'application'},
            host                  => $stream_config->{'host'},

            %opts{'old_db_name'},

            output_obj => $self->utils()->logger(),

            import_cr => sub (%import_opts) {
                $import_opts{'old_name'}             = $opts{'old_db_name'};
                $import_opts{'name'}                 = $opts{'new_db_name'};
                $import_opts{'parent_callback'}      = delete $import_opts{'stream_cr'};
                $import_opts{'child_start_callback'} = delete $import_opts{'before_read_cr'};

                return $self->_create_db_and_import_as_newuser_from_fh(
                    \%import_opts,
                );
            },
        );

        require Whostmgr::Transfers::Systems::Mysql::Stream;
        return Whostmgr::Transfers::Systems::Mysql::Stream::restore_plain(@func_opts);
    }

    return ( 0, "Bad MySQL streaming method: [$stream_config->{'method'}]" );
}

sub _restore_hosts {
    my ( $self, $hosts_ref ) = @_;

    $self->start_action('Restoring MySQL access hosts');

    my %add_hosts = %$hosts_ref;

    return $self->_do_cpanel_mysql_with_newuser_privs(

        sub {
            my ($mysql_obj_with_cpuser_privs) = @_;

            $add_hosts{'localhost'} = 1 if !scalar keys %add_hosts;

            # No need to call updatehosts as addhosts will ensure
            # all the hosts are in sync. Also no need to remove duplicates
            # as addhosts is going to sort all that out

            return $mysql_obj_with_cpuser_privs->addhosts( [ keys %add_hosts ] );
        }
    );

}

sub _is_old_password {
    my ( $self, $hashed_password ) = @_;

    return ( defined $hashed_password && $hashed_password =~ m{\A[0-9a-f]{16}\z} ) ? 1 : 0;

}

1;
