package Cpanel::Pkgacct::Components::Mysql;

# cpanel - Cpanel/Pkgacct/Components/Mysql.pm      Copyright 2022 cPanel, L.L.C.
#                                                           All rights reserved.
# copyright@cpanel.net                                         http://cpanel.net
# This code is subject to the cPanel license. Unauthorized copying is prohibited

use strict;
use warnings;

use parent 'Cpanel::Pkgacct::Component';

use Cpanel::Autodie                 ();
use Cpanel::Autowarn                ();
use Cpanel::CpuWatch::Suspend       ();
use Cpanel::MysqlUtils::MyCnf::Full ();
use Cpanel::MysqlUtils::Command     ();
use Cpanel::MysqlUtils::Suspension  ();
use Cpanel::DbUtils                 ();
use Cpanel::Mysql::Basic            ();
use Cpanel::Mysql::Backup           ();
use Cpanel::MysqlUtils::Version     ();
use Cpanel::MysqlUtils::Connect     ();
use Cpanel::FileUtils::Write        ();
use Cpanel::MysqlUtils::Dump        ();
use Cpanel::Email::RoundCube        ();
use Cpanel::SafeRun::Simple         ();
use Cpanel::ChildErrorStringifier   ();
use Cpanel::LoadModule              ();
use Cpanel::Logger                  ();

use Try::Tiny;

our $PRIVS_FILE = "mysql.sql";

# CPANEL-24565: Lowered to 32 for MySQL 5.6 SEGV
my $MAX_IDS_TO_DUMP_AT_ONCE_TO_AVOID_SEGV = 32;

# This is ER_CANT_AGGREGATE_NCOLLATIONS, which in English comes out as
# “Illegal mix of collations for operation '%s'”. Ideally we’d look for
# something more than this pattern, but we can’t be sure the description
# will be in English, and “ER_CANT_AGGREGATE_NCOLLATIONS” won’t be part
# of the output.  We also need to match “ER_CANT_AGGREGATE_3COLLATIONS”
#
my $MYSQL_ILLEGAL_COLLATIONS_ERROR_STRING_REGEX = '\(127[01]';

#TODO: This logic was moved from the scripts/pkgacct script and should
#be audited for error responsiveness.
sub perform {    ## no critic(Subroutines::ProhibitExcessComplexity)  -- Refactoring this function is a project, not a bug fix

    my ($self) = @_;

    require Cpanel::Services::Enabled;
    if ( !Cpanel::Services::Enabled::is_provided("mysql") ) {
        return $self->_save_from_grants_file();
    }

    my $uid     = $self->get_uid();
    my $domains = $self->get_domains();

    my $is_incremental    = $self->get_is_incremental();
    my $work_dir          = $self->get_work_dir();
    my $user              = $self->get_user();
    my $output_obj        = $self->get_output_obj();
    my $cpconf            = $self->get_cpconf();
    my $new_mysql_version = $self->get_new_mysql_version();
    my $suspended         = $self->get_suspended();
    my $OPTS              = $self->get_OPTS();                # See /usr/local/cpanel/bin/pkgacct process_args for a list of possible OPTS

    # The arguments are documented in /usr/local/cpanel/bin/pkgacct.pod
    # In this module, we use
    # - running_under_cpbackup
    # - mysql_backup_type
    # - db_backup_type

    local $OPTS->{'mysql_backup_type'} = $OPTS->{'mysql_backup_type'} || $OPTS->{'db_backup_type'};

    #mysql block requires loading Config so we do it after we fork
    if ( $OPTS->{'running_under_cpbackup'} ) {
        $output_obj->out( "Entering timeout safety mode for MySQL (suspending cpuwatch)\n", @Cpanel::Pkgacct::NOT_PARTIAL_TIMESTAMP );
    }

    # The connection to the MySQL server may timeout if
    # we allow cpuwatch to suspend us.
    my $cpuwatch_suspend = Cpanel::CpuWatch::Suspend->new();    # will unsuspend cpuwatch when the object is destroyed

    my @mysqldumps;
    my $mysqldump = Cpanel::DbUtils::find_mysqldump();

    my $open_files_limit_file = "$work_dir/mysql/openfileslimit";
    my $mycnf                 = Cpanel::MysqlUtils::MyCnf::Full::etc_my_cnf();
    if ( $mycnf->{'mysqld'}{'open_files_limit'} ) {
        Cpanel::FileUtils::Write::overwrite_no_exceptions( $open_files_limit_file, $mycnf->{'mysqld'}{'open_files_limit'}, 0600 );
    }

    $output_obj->out( 'Determining mysql dbs...', @Cpanel::Pkgacct::PARTIAL_TIMESTAMP );

    if ($suspended) {
        Cpanel::MysqlUtils::Suspension::unsuspend_mysql_users($user);
    }

    my $data_ref;

    if ( $> != 0 ) {
        $data_ref = $self->run_admin_backupcmd( '/usr/local/cpanel/bin/cpmysqlwrap', 'BACKUPJSON' );
    }
    else {
        $data_ref = $self->_fetch_mysql_backup();
    }
    if ($suspended) {
        Cpanel::MysqlUtils::Suspension::suspend_mysql_users($user);
    }

    my %LASTUPDATETIMES = %{ $data_ref->{'LASTUPDATETIMES'} };
    my @DBS             = @{ $data_ref->{'LISTDBS'} };
    my $mysql           = Cpanel::DbUtils::find_mysql();

    my $mysqldump_ver = Cpanel::MysqlUtils::Dump::mysqldump_version();
    $output_obj->out( "...mysqldump version: $mysqldump_ver...", @Cpanel::Pkgacct::PARTIAL_TIMESTAMP );

    ## which dictates $mysql_can_be_cached
    my $old_mysql_version = Cpanel::MysqlUtils::Version::get_mysql_version_with_fallback_to_default($user);
    $output_obj->out( "...mysql version: $old_mysql_version...", @Cpanel::Pkgacct::PARTIAL_TIMESTAMP );
    my @downgrade_options = $self->_downgrade_mysql( $old_mysql_version, $new_mysql_version );

    my $mysql_can_be_cached = !@downgrade_options;

    $output_obj->out( "Saving mysql privs...", @Cpanel::Pkgacct::PARTIAL_TIMESTAMP );
    if ( ( $data_ref->{'DUMPSQL'} && ( ref $data_ref->{'DUMPSQL'} eq 'ARRAY' ) ) && ( !$mysql_can_be_cached || $self->_db_needs_backup( 'mysql', 'mysql', "$work_dir/mysql-timestamps/mysql", ["$work_dir/$PRIVS_FILE"], \%LASTUPDATETIMES ) ) ) {
        Cpanel::FileUtils::Write::overwrite( "$work_dir/$PRIVS_FILE",            "-- cPanel mysql backup\n" . join( '', @{ $data_ref->{'DUMPSQL'} } ), 0600 );
        Cpanel::FileUtils::Write::overwrite( "$work_dir/mysql-timestamps/mysql", time(),                                                               0600 );
    }
    $output_obj->out( "Done\n", @Cpanel::Pkgacct::NOT_PARTIAL_TIMESTAMP );

    # Save the authorization information in a JSON dump, as the plugin type is not saved anywhere else
    $output_obj->out( "Saving mysql authentication information...", @Cpanel::Pkgacct::PARTIAL_TIMESTAMP );
    if ( ( $data_ref->{'SQLAUTH'} && ( ref $data_ref->{'SQLAUTH'} eq 'HASH' ) ) ) {
        require Cpanel::JSON;
        Cpanel::FileUtils::Write::overwrite( "$work_dir/$PRIVS_FILE" . '-auth.json', Cpanel::JSON::Dump( $data_ref->{'SQLAUTH'} ), 0600 );
    }
    $output_obj->out( "Done\n", @Cpanel::Pkgacct::NOT_PARTIAL_TIMESTAMP );

    # Due to the way we call show_grants() from all over, we need a separate function to get the hash plugin type. Not ideal, but requires a hefty rewrite otherwise
    if ( ( $data_ref->{'DUMPSQL'} && ( ref $data_ref->{'DUMPSQL'} eq 'ARRAY' ) ) ) {
        foreach my $line ( @{ $data_ref->{'DUMPSQL'} } ) {
            if ( $line =~ m/ TO \'(.+)\'\@\'(.+)\' / ) {

                # _get_hash_plugin_type_for_user_and_host($1,$2);
            }
        }
    }

    $output_obj->out( 'Storing MySQL databases...', @Cpanel::Pkgacct::PARTIAL_TIMESTAMP );

    foreach my $db ( sort @DBS ) {
        $db =~ s/\n//g;

        my $sqlfile = "$work_dir/mysql/${db}.sql";

        next if ( $mysql_can_be_cached && !$self->_db_needs_backup( 'mysql', $db, "$work_dir/mysql-timestamps/$db", [$sqlfile], \%LASTUPDATETIMES ) );

        try {
            $output_obj->out( "Storing database $db\n", @Cpanel::Pkgacct::PARTIAL_TIMESTAMP );

            my $tempfile;

            my ( $schema, $dump_class );

            if ($>) {
                $dump_class = 'Cpanel::MysqlUtils::Dump::User';

                require Cpanel::AdminBin::Call;
                $schema = Cpanel::AdminBin::Call::call( 'Cpanel', 'mysql', DUMP_SCHEMA => $db );
            }
            else {
                $dump_class = 'Cpanel::MysqlUtils::Dump::Root';

                $schema = Cpanel::MysqlUtils::Dump::dump_database_schema($db);
            }

            Cpanel::FileUtils::Write::overwrite( "$work_dir/mysql/$db.create", $schema );

            Cpanel::LoadModule::load_perl_module($dump_class);

            if ( $OPTS->{'mysql_backup_type'} ne 'name' ) {
                my $mode = $OPTS->{'mysql_backup_type'} eq 'schema' ? 'nodata' : 'all';

                $dump_class->dump_data(
                    dbname => $db,
                    mode   => $mode,
                    get_fh => sub {
                        if ($tempfile) {
                            Cpanel::Autowarn::unlink($tempfile);
                        }

                        $tempfile = $sqlfile . substr( rand, 1 );
                        Cpanel::Autodie::open( my $wfh, '>', $tempfile );
                        return $wfh;
                    },
                );

                Cpanel::Autodie::rename( $tempfile => $sqlfile );
            }
        }
        catch {
            my $exception = $_;

            if ( try { $exception->isa('Cpanel::Exception::ProcessFailed') } ) {
                my $error = $exception->get('stderr');

                $output_obj->warn( "$error\n", @Cpanel::Pkgacct::NOT_PARTIAL_TIMESTAMP );
            }
            else {
                $output_obj->warn( Cpanel::Exception::get_string($exception) . "\n", @Cpanel::Pkgacct::NOT_PARTIAL_TIMESTAMP );
            }
        };
    }

    $output_obj->out( "Done\n", @Cpanel::Pkgacct::NOT_PARTIAL_TIMESTAMP );

    ##############################
    # RoundCube
    my $now_before_roundcube = time();
    my $rcube_dump_fname     = "$work_dir/mysql/roundcube.sql";
    if ( $> == 0 && exists $cpconf->{'roundcube_db'}
        and ( $cpconf->{'roundcube_db'} eq 'sqlite' ) ) {
        ## pass: roundcube.db is in homedir.tar. The logic reads better if this is blank block.
    }
    elsif ( $> == 0 && Cpanel::MysqlUtils::Command::db_exists('roundcube') && ( !$mysql_can_be_cached || $self->_db_needs_backup( 'mysql', 'roundcube', "$work_dir/mysql-timestamps/roundcube", [$rcube_dump_fname], \%LASTUPDATETIMES, ) ) ) {
        try {
            my $user_ids;
            my $roundcube_dbh;
            if ( exists $data_ref->{'ROUNDCUBEIDS'} ) {
                chomp( $user_ids = $data_ref->{'ROUNDCUBEIDS'} );
            }
            else {
                $roundcube_dbh ||= Cpanel::MysqlUtils::Connect::get_dbi_handle( 'database' => 'roundcube' );
                my $sql_dnslist = join( ',', map { $roundcube_dbh->quote($_) } grep { index( $_, '*' ) == -1 } @{$domains} );
                my $user_ids_ar = $roundcube_dbh->selectall_arrayref( "SELECT user_id FROM users WHERE BINARY username = ? OR BINARY SUBSTRING_INDEX(username,'\@',-1) IN (${sql_dnslist});", {}, $user );
                $user_ids = join( ',', map { $_->[0] } @$user_ids_ar );
            }

            ## TODO: determine schema downgrade (via --roundcube and RoundCube::get_version_info)

            if ($user_ids) {
                my $rcube_dumps_ar = $self->_compute_roundcube_dumps(
                    $user_ids,         $mysql, \@downgrade_options, $work_dir,
                    $rcube_dump_fname, $roundcube_dbh
                );
                push( @mysqldumps, @$rcube_dumps_ar );

                if ( open( my $fh, '>', "$work_dir/meta/rcube_version" ) ) {
                    my ($RCUBE_VERSION) = Cpanel::Email::RoundCube::get_cached_version();
                    print {$fh} $RCUBE_VERSION;
                    close $fh;
                }
            }
            else {
                my $time_stamp_file = "$work_dir/mysql-timestamps/roundcube";
                if ( open( my $time_stamp_file_fh, '>', $time_stamp_file ) ) {
                    print {$time_stamp_file_fh} $now_before_roundcube;
                    close($time_stamp_file_fh);

                    # If we've gotten to this point on an incremental backup, there isn't any
                    # Roundcube data for the user in the database. If that's the case, overwrite the
                    # dump file that's here as it contains stale data.
                    if ( open( my $sql_fh, '>', $rcube_dump_fname ) ) {
                        print {$sql_fh} "-- Roundcube database place holder file\n";
                        close($sql_fh) or do {
                            $output_obj->warn( "Could not close '$rcube_dump_fname' due to an error: $!\n", @Cpanel::Pkgacct::NOT_PARTIAL_TIMESTAMP );
                        };
                    }
                    else {
                        $output_obj->warn( "Could not open '$rcube_dump_fname' due to an error: $!\n", @Cpanel::Pkgacct::NOT_PARTIAL_TIMESTAMP );
                    }
                }
            }

        }
        catch {
            local $@ = $_;
            warn;
        };

    }
    $output_obj->out( "...Done\n", @Cpanel::Pkgacct::NOT_PARTIAL_TIMESTAMP );

    ##############################
    if (@mysqldumps) {    #only fork if we actually have databases to backup

        # This section is now only for Roundcube data
        # since we do other MySQL dumps above independently.

        $output_obj->out( 'Storing Roundcube’s data...', @Cpanel::Pkgacct::PARTIAL_TIMESTAMP );

        my $STATUS_OK      = 0;
        my $STATUS_ERROR   = 1;
        my $STATUS_WARNING = 2;

        my $child_status = $self->run_dot_event(
            sub {
                my $status = $STATUS_OK;

                $0 = "pkgacct - ${user} - mysql copy child";
                foreach my $dumpref (@mysqldumps) {
                    $dumpref->{'incremental'}    = $is_incremental;
                    $dumpref->{'user'}           = $user;
                    $dumpref->{'output_obj'}     = $output_obj;
                    $dumpref->{'db_backup_type'} = $OPTS->{'mysql_backup_type'};
                    my $dump_result = $self->_mysqldumpdb($dumpref);

                    if ( $dump_result->{'status'} != 0 ) {
                        my $warn_message = "Failed to dump database $dumpref->{'db'}: " . Cpanel::ChildErrorStringifier->new( $dump_result->{'status'} )->autopsy();
                        Cpanel::Logger::warn($warn_message);
                        $output_obj->warn( $warn_message, @Cpanel::Pkgacct::NOT_PARTIAL_TIMESTAMP );
                        if ( $dump_result->{'errors'} =~ m{Unknown database} ) {
                            $status = $STATUS_WARNING unless $status == $STATUS_ERROR;
                        }
                        else {
                            $status = $STATUS_ERROR;
                        }
                    }
                }
                return $status;    # will exit with this code
            },
        );

        if ( $child_status != 0 ) {
            my $child_error = Cpanel::ChildErrorStringifier->new($child_status);
            if ( $child_error->error_code() == $STATUS_ERROR ) {
                $output_obj->error( "\nERROR: Failed to dump one or more databases\n", @Cpanel::Pkgacct::NOT_PARTIAL_TIMESTAMP );
            }
            elsif ( $child_error->error_code() == $STATUS_WARNING ) {
                $output_obj->warn( "\nWARNING: There was a problem dumping one or more databases\n", @Cpanel::Pkgacct::NOT_PARTIAL_TIMESTAMP );
            }
        }
    }

    $output_obj->out( "...Done\n", @Cpanel::Pkgacct::NOT_PARTIAL_TIMESTAMP );
    if ( $OPTS->{'running_under_cpbackup'} ) {
        $output_obj->out( "Leaving timeout safety mode for MySQL (unsuspending cpuwatch)\n", @Cpanel::Pkgacct::NOT_PARTIAL_TIMESTAMP );
    }

    return 1;
}

sub _save_from_grants_file {

    my ($self) = @_;

    my $output_obj = $self->get_output_obj();
    my $work_dir   = $self->get_work_dir();
    my $user       = $self->get_user();

    $output_obj->out( "MySQL is not enabled on this system, saving privileges from the user‘s grants file … ", @Cpanel::Pkgacct::NOT_PARTIAL_TIMESTAMP );

    my $status = 0;

    try {

        require Cpanel::DB::GrantsFile;
        my $grants_db = Cpanel::DB::GrantsFile::read_for_cpuser($user);

        my $grants = "";
        if ( $grants_db->{"MYSQL"} ) {
            foreach my $db_user ( keys %{ $grants_db->{MYSQL} } ) {
                $grants .= join( "\n", @{ $grants_db->{MYSQL}{$db_user} } ) . "\n";
            }
        }

        Cpanel::FileUtils::Write::overwrite( "$work_dir/$PRIVS_FILE", "-- cPanel mysql backup\n$grants\n", 0600 );
        $output_obj->out( "Done\n", @Cpanel::Pkgacct::NOT_PARTIAL_TIMESTAMP );

        $status = 1;
    }
    catch {
        require Cpanel::Exception;
        $output_obj->warn( "Failed to read grants file\n" . Cpanel::Exception::get_string($_), @Cpanel::Pkgacct::NOT_PARTIAL_TIMESTAMP );
    };

    return $status;
}

sub _compute_roundcube_dumps {    ## no critic qw(Subroutines::ProhibitManyArgs)
    my ( $self, $user_ids, $mysql, $ar_downgrade_options, $work_dir, $rcube_dump_fname, $roundcube_dbh ) = @_;

    $roundcube_dbh ||= Cpanel::MysqlUtils::Connect::get_dbi_handle( 'database' => 'roundcube' );
    ## note: src server emits 'CREATE TABLE' statements, which necessitates a '--force' when
    ##   reimporting the .sql file
    ## considered adding --no-create-db and --create-options, but these seem to be default
    my @options = (
        @$ar_downgrade_options,
        '--skip-add-drop-table',
        '--complete-insert',
        '--quote-names',
        '--quick',
        '--where',
    );

    my @rv;
    my @user_ids_list = split( m{,}, $user_ids );
    my $append        = 0;
    while ( my @user_ids_list_small_enough_to_pass_to_mysqldump = splice( @user_ids_list, 0, $MAX_IDS_TO_DUMP_AT_ONCE_TO_AVOID_SEGV ) ) {
        my $user_ids_chunk = join( ',', @user_ids_list_small_enough_to_pass_to_mysqldump );
        push @rv, {
            'options'         => [ ( $append ? ('--no-create-info') : () ), @options, qq{user_id IN ($user_ids_chunk)} ],
            'db'              => 'roundcube',
            'time-stamp-file' => "$work_dir/mysql-timestamps/roundcube",
            'file'            => $rcube_dump_fname,
            ## SOMEDAY: note how ::RoundCube does a mysqldump with --ignore-table;
            ##   this would solve the problem of not knowing if contactgroups, etc.
            ##   are installed! Except contactgroupmembers do not directly use user_id...
            'table'  => [ 'users', 'identities', 'contacts', 'contactgroups' ],
            'append' => $append,
        };
        $append++;
    }

    # We used to index the backup on contacts. We now use
    # contactgroups since the user is much less likely to have
    # so many contactgroups that mysqldump can’t run due to the number
    # of arguments.  This is the same fix that was done in
    # case CPANEL-14019 for convert_roundcube_mysql2sqlite
    #
    my $contactgroup_ids_ar = $roundcube_dbh->selectall_arrayref("SELECT contactgroup_id FROM contactgroups WHERE user_id IN ($user_ids)");

    ## best to always write the CREATE TABLE for contactgroupmembers, even if there is
    ##   no associated data; this is consistent with the handling of the other
    ##   potentially empty tables
    my %args = (
        'db'              => 'roundcube',
        'time-stamp-file' => "$work_dir/mysql-timestamps/roundcube",
        'file'            => $rcube_dump_fname,
        'table'           => ['contactgroupmembers'],
        'append'          => 1
    );
    if ( $contactgroup_ids_ar && @$contactgroup_ids_ar ) {
        my $chunk = 0;
        while ( my @contactgroup_ids_list_small_enough_to_pass_to_mysqldump = splice( @$contactgroup_ids_ar, 0, $MAX_IDS_TO_DUMP_AT_ONCE_TO_AVOID_SEGV ) ) {
            my $contactgroup_ids_chunk = join( ',', map { $_->[0] } @contactgroup_ids_list_small_enough_to_pass_to_mysqldump );
            push @rv,
              {
                'options' => [ ( $chunk ? ('--no-create-info') : () ), @options, qq{contactgroup_id IN ($contactgroup_ids_chunk)} ],
                %args,
              };
            $chunk++;
        }
    }
    else {
        push @rv, { 'options' => [ @options, 0 ], %args };
    }

    return \@rv;
}

sub _timestamp {
    my ( $self, $file ) = @_;

    if ( $file && open( my $fh, '>', $file ) ) {
        print {$fh} time();
        close($fh);
    }

    return;
}

sub _mysqldumpdb {
    my ( $self, $args ) = @_;

    my @options         = @{ $args->{'options'} };
    my $user            = $args->{'user'};
    my $db              = $args->{'db'};
    my $table           = $args->{'table'};
    my $file            = $args->{'file'};
    my $time_stamp_file = $args->{'time-stamp-file'};       #created before we do the dump in case something changes during the dump
    my $file_write_mode = $args->{'append'} ? '>>' : '>';
    my $output_obj      = $args->{'output_obj'};
    my $db_backup_type  = $args->{'db_backup_type'};

    # Make sure the console language is in a predictable tongue as we'll, unfortunately, need to look for a specific word in check_error_file
    local $ENV{'LANG'} = 'C';

    my $mysqldump = Cpanel::DbUtils::find_mysqldump();
    my @db        = ($db);
    my @tables;
    if ($table) {
        if ( ref $table ) {
            push @tables, @$table;
        }
        else {
            push @tables, $table;
        }
    }
    my $table_names = ( @tables ? join( ',', map { $db . '.' . $_ } @tables ) : $db );
    $output_obj->out( $table_names, @Cpanel::Pkgacct::PARTIAL_MESSAGE );

    $self->_timestamp($time_stamp_file);

    if ( $> != 0 && $ENV{'REMOTE_PASSWORD'} && !grep ( m{\-u}, @options ) ) {
        push @options, ( '-u', $user, '-p' . $ENV{'REMOTE_PASSWORD'} );
    }
    if ( !scalar @tables ) {
        my $create_file = $file;
        $create_file =~ s/\.sql$/.create/;
        $self->exec_into_file( $create_file, '>', [ $mysqldump, @options, '--databases', '--skip-triggers', '--no-data', '--no-create-info', '--', $db ], $args->{'incremental'} );
        my ( $create_ok, $errors ) = $self->_check_error_file( $table_names, $create_file . '.err' );
        if ( !$create_ok && $errors =~ m{$MYSQL_ILLEGAL_COLLATIONS_ERROR_STRING_REGEX}o ) {
            $self->exec_into_file( $create_file, '>', [ $mysqldump, _set_default_char_set_utf8(@options), '--databases', '--skip-triggers', '--no-data', '--no-create-info', '--', $db ], $args->{'incremental'} );
            ( $create_ok, $errors ) = $self->_check_error_file( $table_names, $create_file . '.err' );
            if ($create_ok) {
                $output_obj->success("The system successfully retried the dump operation using a default character set of “utf8”.");
            }
        }
    }
    my $status;
    my $errors;
    my $bytes_saved = 0;
    my $dump_ok     = 0;
    my $attempts    = 0;
    my ( $begin_point, $end_point );
    if ( $db_backup_type ne 'name' ) {

        while ( !$dump_ok && ++$attempts <= 2 ) {
            if ( $attempts == 2 && $> == 0 ) {
                my $mysqlcheck = Cpanel::DbUtils::find_mysqlcheck();
                $output_obj->warn("The system is attempting to repair the database “$db” in order to obtain a successful dump.");
                $self->system_to_output_obj( $mysqlcheck, '--repair', '--', @db, @tables );

            }
            my @cmdline = ( $mysqldump, @options, ( $db_backup_type eq 'schema' ? ('--no-data') : () ), '--routines', '--', @db, @tables );

            ( $begin_point, $end_point, $status ) = $self->exec_into_file( $file, $file_write_mode, \@cmdline, $args->{'incremental'} );
            ( $dump_ok, $errors ) = $self->_check_error_file( $table_names, $file . '.err' );
            if ( !$dump_ok && $errors =~ m{$MYSQL_ILLEGAL_COLLATIONS_ERROR_STRING_REGEX}o ) {
                ( $begin_point, $end_point, $status ) = $self->exec_into_file( $file, $file_write_mode, [ _set_default_char_set_utf8(@cmdline) ], $args->{'incremental'} );
                ( $dump_ok, $errors ) = $self->_check_error_file( $table_names, $file . '.err' );
                if ($dump_ok) {
                    $output_obj->success("The system successfully retried the dump operation using a default character set of “utf8”.");
                }

            }
        }
        $bytes_saved = int( $end_point - $begin_point );

        if ( !$dump_ok ) {
            my $warn_message = join( '.', @db ) . ': mysqldump failed -- database may be corrupt';
            Cpanel::Logger::warn($warn_message);
            $output_obj->warn( $warn_message, @Cpanel::Pkgacct::NOT_PARTIAL_TIMESTAMP );
        }
        $output_obj->out( '(' . $bytes_saved . ' bytes) ', @Cpanel::Pkgacct::NOT_PARTIAL_TIMESTAMP );
    }

    return {
        'bytes_saved'   => $bytes_saved,
        'errors_logged' => $dump_ok ? 0 : 1,
        'status'        => $status,
        'errors'        => $errors,
    };
}

# TODO: Cpanel::Pkgacct::Components::Mysql::_check_error_file would be nice as a generic module
# along with Cpanel::Pkgacct::exec_into_file and Cpanel::Pkgacct::simple_exec_into_file
sub _check_error_file {
    my ( $self, $header, $file ) = @_;

    my $output_obj = $self->get_output_obj();
    my $ok         = 1;

    my $errors = '';
    if ( -e $file ) {
        if ( -s _ && open( my $fh, '<', $file ) ) {
            while ( my $line = readline($fh) ) {

                # Case 99893 - when this message is received the table is still exported
                next if $line =~ / deprecated /i;
                $errors .= $line;

                chomp($line);
                $output_obj->warn( $header . ': ' . $line, @Cpanel::Pkgacct::NOT_PARTIAL_TIMESTAMP );
                Cpanel::Logger::warn( $header . ': ' . $line );
                $ok = 0;
            }
            close($fh);
        }
        unlink($file);
    }
    return ( $ok, $errors );
}

sub _db_needs_backup {    ## no critic qw(Subroutines::ProhibitManyArgs)

    # $mysqldatadir is not used
    my ( $self, $db_type, $db_name, $target_sql_file, $sql_files, $update_times_cache_ref ) = @_;

    my $output_obj = $self->get_output_obj();

    my $is_incremental = $self->get_is_incremental();

    #print "[_db_needs_backup] entry\n";
    return 1 if !$is_incremental;

    # Eventually we could support postgres if we had a fast way to check to see when the database
    # was last updated.

    foreach my $file (@$sql_files) {
        if ( !-e $file ) { return 2; }
        if ( -z _ )      { return 1; }    #check for failed backups
    }

    # If it is an incremental backup we check to see if the
    # it has changed and skip the backup if it has not
    my $target_sql_file_mtime = ( stat($target_sql_file) )[9];

    my $now = time();

    #print "[_db_needs_backup][$db_name] target_sql_file_mtime=$target_sql_file_mtime\n";
    return 1 if !$target_sql_file_mtime || $target_sql_file_mtime > $now;

    my $last_update_time = ( exists $update_times_cache_ref->{$db_name} && $update_times_cache_ref->{$db_name} ) ? $update_times_cache_ref->{$db_name} : Cpanel::SafeRun::Simple::saferun( '/usr/local/cpanel/bin/' . $db_type . 'tool', 'LASTUPDATETIME', $db_name );
    chomp($last_update_time);

    #print "[_db_needs_backup][$db_name] last_update_time=$last_update_time\n";
    #print "[_db_needs_backup][$db_name] now=$now\n";

    return 1 if ( !$last_update_time
        || $last_update_time > $target_sql_file_mtime
        || $last_update_time > $now );

    #print "[_db_needs_backup][$db_name] Skipping backup of database $db_name last backup time = [$target_sql_file_mtime], last update time = [$last_update_time]\n";

    my $last_update_time_localtime      = localtime($last_update_time);
    my $target_sql_file_mtime_localtime = localtime($target_sql_file_mtime);

    $output_obj->out("$db_name skipped (last change @ $last_update_time_localtime, current backup @ $target_sql_file_mtime_localtime)\n");

    return 0;    #no need to backup again
}

sub _downgrade_mysql {
    my ( $self, $old_server, $new_server ) = @_;

    return if ( !$new_server || $new_server eq 'default' || $new_server >= $old_server );

    my $downgrade_table = {
        '5.5' => { 'options' => [] },
        '5.1' => { 'options' => ['--skip-events'] },
        '5.0' => { 'options' => [ '--skip-routines', '--skip-triggers' ] },
        '4.1' => { 'options' => ['--compatible=mysql40'] },
        '4.0' => { 'options' => [] },
    };

    my @downgrade_order = sort { $b <=> $a } keys %{$downgrade_table};

    my @options = ();
    foreach my $version (@downgrade_order) {
        last if $new_server >= $version;

        if ( ( $old_server >= $version ) && ( $new_server < $version ) ) {
            push @options, @{ $downgrade_table->{$version}{'options'} };
        }
    }
    return @options;
}

sub _fetch_mysql_backup {
    my ($self)     = @_;
    my $user       = $self->get_user();
    my $cpconf     = $self->get_cpconf();
    my $domains_ar = $self->get_domains();

    die "no domains??" if !@$domains_ar;

    my $ob = Cpanel::Mysql::Basic->new( { 'cpconf' => $cpconf, 'cpuser' => $user, 'ERRORS_TO_STDOUT' => 1 } );
    return Cpanel::Mysql::Backup::fetch_backup_as_hr( $ob, $cpconf, $domains_ar );
}

sub _set_default_char_set_utf8 {
    my (@arr) = @_;

    # If Cpanel::MysqlUtils::Dump::minimum_version ever changes the --default-character-set
    # arg, this will need to be modified
    return map { index( $_, '--default-character-set' ) > -1 ? '--default-character-set=utf8' : $_ } @arr;
}

1;
