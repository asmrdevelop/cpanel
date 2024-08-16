package Whostmgr::Transfers::SystemsBase::MysqlBase;

# cpanel - Whostmgr/Transfers/SystemsBase/MysqlBase.pm
#                                                  Copyright 2022 cPanel, L.L.C.
#                                                           All rights reserved.
# copyright@cpanel.net                                         http://cpanel.net
# This code is subject to the cPanel license. Unauthorized copying is prohibited

use cPstrict;

our $VERSION = '1.9';

use parent qw(Whostmgr::Transfers::SystemsBase::DBBase);

use Try::Tiny;

use Socket ();

use Cpanel::Rand::Get          ();
use Cpanel::PwCache            ();
use Cpanel::MysqlUtils::Rename ();
use Cpanel::Mysql::Error       ();

use Cpanel::Alarm                        ();
use Cpanel::Autodie                      ();
use Cpanel::ChildErrorStringifier        ();
use Cpanel::Kill::Single                 ();
use Cpanel::DB::Map                      ();
use Cpanel::DB::Map::Reader              ();
use Cpanel::DB::Map::Collection::Index   ();
use Cpanel::DB::Utils                    ();
use Cpanel::Exec                         ();
use Cpanel::Exception                    ();
use Cpanel::FileUtils::Read              ();
use Cpanel::LoadModule                   ();
use Cpanel::LocaleString                 ();
use Cpanel::Mysql                        ();
use Cpanel::MysqlUtils::MyCnf::Basic     ();
use Cpanel::MysqlUtils::Unicode          ();
use Cpanel::MysqlUtils::Version          ();
use Cpanel::MysqlUtils::Quote            ();
use Cpanel::Sereal::Decoder              ();
use Cpanel::Sereal::Encoder              ();
use Cpanel::Validate::DB::Name           ();
use Cpanel::Validate::LineTerminatorFree ();

my $MYSQL_COMMAND_TIME_LIMIT = 14400;    # 4 hours

my $MAX_MYSQL_MEMORY_ALLOWED = 1 << 30;  #1 GiB

sub cleanup {
    my ($self) = @_;

    if ( $self->{'_mysql_obj_with_root_privs'} ) {
        $self->{'_mysql_obj_with_root_privs'}->destroy();
    }

    delete $self->{'_has_super_priv'};

    return 1;
}

sub _init_self_variables {
    my ($self) = @_;

    $self->{'_mysql_host'}                = Cpanel::MysqlUtils::MyCnf::Basic::getmydbhost() || 'localhost';
    $self->{'_mysql_obj_with_root_privs'} = Cpanel::Mysql->new( { cpuser => 'root' } );
    $self->{'_dbh_with_root_privs'}       = $self->{'_mysql_obj_with_root_privs'}->{'dbh'};

    return;
}

sub dbh_with_root_privs {
    my ($self) = @_;
    return $self->{'_dbh_with_root_privs'};
}

sub mysql_obj_with_root_privs {
    my ($self) = @_;
    return $self->{'_mysql_obj_with_root_privs'};
}

# Called from subclasses.
#
# $db is a hashref of:
#   old_name - old DB name
#   name     - new DB name
#   sql_fh
#   parent_callback - optional
#   child_start_callback - optional
#
sub _create_db_and_import_as_newuser_from_fh {
    my ( $self, $db ) = @_;

    $self->utils()->ensure_user_mysql_access();

    my ( $orig_dbname, $dbname ) = @{$db}{qw( old_name  name )};

    my $name_error;
    try {
        Cpanel::Validate::LineTerminatorFree::validate_or_die($orig_dbname);
        Cpanel::Validate::LineTerminatorFree::validate_or_die($dbname);
    }
    catch {
        $name_error = $_;
    };

    if ($name_error) {
        return ( 0, _locale()->maketext( 'The system could not restore the MySQL database “[_1]” as “[_2]” because of an error: [_3]', $orig_dbname, $dbname, Cpanel::Exception::get_string($name_error) ) );
    }

    my ( $create_ok, $create_err ) = $self->_create_normal_mysql_db( $orig_dbname, $dbname );
    return ( 0, $create_err ) if !$create_ok;

    #Create a DB map file if it doesn’t already exist on the system.
    if ( !Cpanel::DB::Map::Reader::cpuser_exists( $self->newuser() ) ) {
        Cpanel::DB::Map->new_allow_create( { cpuser => $self->newuser() } );
    }

    my ( $grant_ok, $grant_err ) = $self->_grant_temp_access_to_normal_mysql_db($dbname);
    return ( 0, $grant_err ) if !$grant_ok;

    my ( $dbi_ok, $dbi_cmds ) = $self->_parse_and_run_dbi_statements_as_newuser($db);
    if ( !$dbi_ok ) {
        my $err;
        try {
            $self->{'_dbh_with_root_privs'}->do( 'DROP DATABASE ' . Cpanel::MysqlUtils::Quote::quote_identifier($dbname) );
        }
        catch {
            $err = $_;
        };

        if ($err) {
            $self->warn( _locale()->maketext( "Failed to remove empty DB “[_1]”: [_2]", $dbname, Cpanel::Exception::get_string($err) ) );
        }
        else {
            $self->warn( _locale()->maketext( "Removed empty DB for failed restore of “[_1]”.", $orig_dbname ) );
        }

        $self->save_databases_in_homedir('mysql');

        return ( 0, $dbi_cmds );
    }

    $self->_check_for_and_warn_about_utf8mb4_conversions_for_db($dbname);

    return 1;
}

sub _user_temp_mysql_passwd {
    my ($self) = @_;
    return $self->{'_user_temp_mysql_passwd'} ||= Cpanel::Rand::Get::getranddata(10);
}

#mysqldump includes DELIMITER statements, which only the mysql command-line
#utility can parse effectively. So we need to strip those out and send them
#through DBI separately.
sub _parse_and_run_dbi_statements_as_newuser ( $self, $db ) {

    my $newuser = $self->newuser();

    my ( $orig_dbname, $sql_fh, $parent_cb, $child_cb ) = @{$db}{qw( old_name  sql_fh  parent_callback  child_start_callback )};

    return if !defined $sql_fh || !defined $newuser;

    my ( $ok, $err );

    my %dbname_changes = map { $_ => $self->new_dbname_name($_) } $self->_archive_dbnames();

    my $dbh_attrs_hr = $self->dbh_with_root_privs()->attributes();
    my $mysql_host   = $dbh_attrs_hr->{'mysql_socket'} || $dbh_attrs_hr->{'host'};

    # sanity-check:
    die "Failed to determine MySQL host??" if !$mysql_host;

    my %restore_data = (
        username             => $newuser,
        old_dbname           => $orig_dbname,
        new_dbname           => $db->{'name'},
        mysql_host           => $mysql_host,
        user_mysql_password  => $self->_user_temp_mysql_passwd(),
        admin_mysql_username => $dbh_attrs_hr->{'Username'},
        admin_mysql_password => $dbh_attrs_hr->{'Password'},
        dbname_changes       => \%dbname_changes,
    );

    #----------------------------------------------------------------------
    #NOTE: Unfortunately, to be secure about things, we need to slurp the
    #SQL file that contains the DB contents.
    #If MySQL had an equivalent of pg_restore, we could just delegate this
    #to that utility, but all we get for command-line restores is the "mysql"
    #utility, which allows arbitrary shell command execution, which is too
    #dangerous. We could try to filter for that, but it's safer just
    #to use DBI (which doesn't understand shell escapes).
    #----------------------------------------------------------------------
    #In order to avoid slurping a huge "line" of data, we fork and set rlimit.

    $self->out( _locale()->maketext( "Spawning restoration subprocess for “[_1]” …", $db->{'name'} ) );

    Cpanel::Autodie::socketpair( my $psock, my $csock, Socket::AF_UNIX, Socket::SOCK_STREAM, 0 );

    my $pid = Cpanel::Exec::forked(
        [
            '/usr/local/cpanel/bin/restore_mysql_for_account_restore',
            '--config-fd' => fileno($csock),
            '--sql-fd'    => fileno($sql_fh),
        ],
        sub {
            close $psock;

            require Cpanel::FHUtils::FDFlags;
            Cpanel::FHUtils::FDFlags::set_non_CLOEXEC($csock);
            Cpanel::FHUtils::FDFlags::set_non_CLOEXEC($sql_fh);

            $child_cb->() if $child_cb;
        },
    );

    my $alarm = Cpanel::Alarm->new(86400);    # XXX TODO check
    local $SIG{'ALRM'} = sub {
        Cpanel::Kill::Single::safekill_single_pid($pid);
        die "MySQL restore exceeded timeout!\n";
    };

    my $wrote = Cpanel::Autodie::syswrite(
        $psock,
        Cpanel::Sereal::Encoder::create()->encode( \%restore_data ),
    );
    Cpanel::Autodie::shutdown( $psock, Socket::SHUT_WR );

    close $csock;
    close $sql_fh;

    $self->out( _locale()->maketext( "Restoring database in subprocess (PID [_1]) …", $pid ) );

    if ($parent_cb) {
        warn if !eval { $parent_cb->(); 1 };
    }

    $self->out( _locale()->maketext( "Transfer complete. Awaiting subprocess completion …", $pid ) );

    # This will block until the MySQL restore is done and the child
    # process reports back to us.
    my $result_blob = do { local $/; <$psock> };

    waitpid $pid, 0;

    my $child_result_obj = Cpanel::ChildErrorStringifier->new($?);

    $self->out( _locale()->maketext( "The database restoration subprocess for “[_1]” has ended.", $db->{'name'} ) );

    # No reason to parse the response if the subprocess ended in failure.
    if ( !$child_result_obj->CHILD_ERROR() ) {
        try {
            my $result_hr = Cpanel::Sereal::Decoder::create()->decode($result_blob);

            if ( my $result_dg_hr = $result_hr->{'utf8mb4_downgrade'} ) {
                my $dg_hr = $self->{'_utf8mb4_downgrade'}{ $db->{'name'} } ||= {};

                @{$dg_hr}{ keys %$result_dg_hr } = values %$result_dg_hr;
            }

            $ok = 1;
        }
        catch {
            warn "Failed to process the subprocess’s response: $_";
        };
    }

    my $payload;

    if ( $child_result_obj->CHILD_ERROR() ) {

        # case CPANEL-10871: The child may segfault on global destruction due to case CPANEL-9494
        # even though everything was successful. We never set $ok to 0 here anymore in case
        # as a successful read from $forked_dbi_calls->return() indicates this condition.
        #
        # We will however warn at the end of this block.
        #
        if ( $child_result_obj->signal_code() ) {
            my $signal = try { $child_result_obj->signal_name() } || $child_result_obj->signal_code();
            if ( $signal eq 'ALRM' ) {
                $err = _locale()->maketext('The MySQL restore process was aborted because it timed out.');
            }
            else {
                $err = _locale()->maketext( 'The MySQL restore process died from the “[_1]” signal.', $signal );
            }
        }
        else {
            my $error = try { $child_result_obj->error_name() } || $child_result_obj->error_code();
            $err = _locale()->maketext( 'The MySQL restore process exited with the error “[_1]”.', $error );
        }
        $self->warn($err);
    }

    if ($ok) {
        $self->out( _locale()->maketext( "The system has restored the contents of the database “[_1]”.", $db->{'name'} ) );
    }
    else {
        $err = $payload;
    }

    if ( !$ok ) {
        $err ||= _locale()->maketext( "The system encountered an unknown error while restoring MySQL statements: [_1]", $child_result_obj->autopsy() );
    }

    # No need to catch disconnect errors here
    # as we do not care if a disconnect fails
    # because it would likely not be useful
    # information, and the object will
    # eventually be destroyed anyways.
    return ( $ok, $err );
}

sub _grant_temp_access_to_normal_mysql_db {
    my ( $self, $dbname ) = @_;

    my $newuser = $self->newuser();
    my $dbowner = Cpanel::DB::Utils::username_to_dbowner($newuser);
    my $err;

    $self->out( _locale()->maketext( "Granting “[_1]” access to “[_2]” with temporary password …", $dbowner, $dbname ) );

    # This adds the dbowner permission on the database
    #
    # We need to do this with the cpuser set to the new user with the ownership checks disabled
    # to avoid root's mysql hosts getting granted as well
    #
    my ( $status, $message );
    try {
        ( $status, $message ) = $self->_do_cpanel_mysql_with_newuser_privs(
            sub {
                my ($mysql_obj_with_cpuser_privs) = @_;
                return $mysql_obj_with_cpuser_privs->add_dbowner_to_all_without_ownership_checks( $dbowner, $self->_user_temp_mysql_passwd(), $Cpanel::Mysql::PASSWORD_PLAINTEXT, $dbname );
            },
        );
    }
    catch {
        $err = $_;
    };

    if ($err) {
        my $err_as_text = Cpanel::Exception::get_string($err);
        return ( 0, "Failed to grant “$dbowner” access to “$dbname”: $err_as_text" );
    }
    elsif ( !$status ) {
        return ( 0, "Failed to grant “$dbowner” access to “$dbname”: $message" );
    }
    else {
        return ( 1, "Granted “$dbowner” access to “$dbname”" );
    }
}

#%opts is described inline below.
#
sub __rename_out_of_the_way {
    my ( $self, %opts ) = @_;

    for (
        'obj_name',
        'statement',     #passed to _find_unique_name_variant as a DBI $sth
        'exclude',       #passed to _find_unique_name_variant()
        'max_length',    #passed to _find_unique_name_variant()
        'rename_func_name',
        'does_not_exist_cr',
        'will_rename_phrase',
        'failed_rename_phrase',
    ) {
        die "Missing “$_”!" if !exists $opts{$_};
    }

    my $obj_name = $opts{'obj_name'};

    my $dbh = $self->{'_dbh_with_root_privs'};

    my $name_to_rename_as = $self->_find_unique_name_variant(
        name       => $obj_name,
        max_length => $opts{'max_length'},
        statement  => $dbh->prepare( $opts{'statement'} ),
        exclude    => $opts{'exclude'},
    );

    $self->out( $opts{'will_rename_phrase'}->clone_with_args( $obj_name, $name_to_rename_as )->to_string() );

    my $name_to_rename_as_q = $dbh->quote_identifier($name_to_rename_as);

    my $renamer_cr = Cpanel::MysqlUtils::Rename->can( $opts{'rename_func_name'} );
    try {
        $renamer_cr->( $dbh, $obj_name, $name_to_rename_as );
    }
    catch {

        #No need to warn if what we were going to rename is just gone now.
        if ( !$opts{'does_not_exist_cr'}->() ) {
            $self->warn( $opts{'failed_rename_phrase'}->clone_with_args( $obj_name, Cpanel::Exception::get_string($_) )->to_string() );
        }
    };

    return $name_to_rename_as;
}

sub _rename_db_out_of_the_way {
    my ( $self, $db_name ) = @_;

    return $self->__rename_out_of_the_way(
        obj_name             => $db_name,
        statement            => 'SELECT 1 FROM INFORMATION_SCHEMA.SCHEMATA WHERE SCHEMA_NAME = ?',
        max_length           => $Cpanel::Validate::DB::Name::max_mysql_dbname_length,
        exclude              => [ grep { defined } $self->_get_new_db_names() ],
        does_not_exist_cr    => sub { $_->get('error_code') eq Cpanel::Mysql::Error::ER_DB_DROP_EXISTS() },
        rename_func_name     => 'rename_database',
        will_rename_phrase   => Cpanel::LocaleString->new('The system will rename the unmanaged database “[_1]” to “[_2]”.'),
        failed_rename_phrase => Cpanel::LocaleString->new('The system failed to rename the database “[_1]” because of an error: [_2]'),
    );
}

sub _create_normal_mysql_db {
    my ( $self, $old_dbname, $dbname ) = @_;

    my $extractdir = $self->extractdir();

    my $newuser = $self->newuser();

    $self->out( _locale()->maketext( "Restoring the database “[_1]” as “[_2]” …", $old_dbname, $dbname ) );

    my $mysql_dbh_with_root_privs = $self->{'_dbh_with_root_privs'};

    local $mysql_dbh_with_root_privs->{'PrintWarn'}  = 0;
    local $mysql_dbh_with_root_privs->{'PrintError'} = 0;

    my ($err);
    try {
        Cpanel::Validate::DB::Name::verify_mysql_database_name($dbname);
    }
    catch {
        $err = $_;
    };
    if ($err) {
        my $err_msg = _locale()->maketext( "The system is unable to restore the MySQL database “[_1]” because of an error: [_2]", $dbname, Cpanel::Exception::get_string($err) );
        $self->warn($err_msg);
        return ( 0, $err_msg );
    }

    if ( $mysql_dbh_with_root_privs->db_exists($dbname) ) {
        my $dbindex          = Cpanel::DB::Map::Collection::Index->new( { 'db' => 'MYSQL' } );
        my $old_cpuser_owner = $dbindex->get_dbuser_by_db($dbname);

        if ( defined $old_cpuser_owner ) {
            $self->out( _locale()->maketext( "The system will overwrite [_1]’s existing database “[_2]”.", $old_cpuser_owner, $dbname ) );
            my $old_mysql = Cpanel::Mysql->new( { cpuser => $old_cpuser_owner } );
            $old_mysql->drop_db($dbname);
        }
        else {
            $self->_rename_db_out_of_the_way($dbname);
        }
    }

    if ( try { $mysql_dbh_with_root_privs->do( 'CREATE DATABASE ' . $mysql_dbh_with_root_privs->quote_identifier($dbname) ) } ) {
        $self->out( _locale()->maketext( "The system has created a new database named “[_1]”.", $dbname ) );
    }
    elsif ( $old_dbname ne $dbname ) {
        $self->set_skip_db($old_dbname);    # skip restoring the failed db
        return ( 0, _locale()->maketext( 'The system failed to create the database “[_1]” because of an error: [_2]', $dbname, $mysql_dbh_with_root_privs->errstr() ) );
    }

    return $self->_import_charset_and_collation_for_db( $old_dbname, $dbname );
}

sub _import_charset_and_collation_for_db {
    my ( $self, $old_dbname, $dbname ) = @_;

    my $extractdir     = $self->extractdir();
    my $db_create_file = "$extractdir/mysql/$old_dbname.create";

    if ( -e $db_create_file ) {

        my $char_set;
        my $coll;

        my $err;
        try {
            Cpanel::FileUtils::Read::for_each_line(
                $db_create_file,
                sub {
                    my ($iter) = @_;

                    if (/DEFAULT CHARACTER SET ([^\s]+) (?:COLLATE ([^\s]+))?/) {
                        ( $char_set, $coll ) = ( $1, $2 );
                        $iter->stop();
                    }
                }
            );
        }
        catch {
            $err = $_;
        };
        return ( 0, $err->to_locale_string() ) if $err;

        if ($char_set) {
            my $mysql_dbh_with_root_privs = $self->{'_dbh_with_root_privs'};

            #https://dev.mysql.com/doc/refman/5.5/en/charset-unicode.html
            if ( ( $char_set =~ m<\Autf8mb[34]\z> ) && !Cpanel::MysqlUtils::Unicode::has_utf8mb4($mysql_dbh_with_root_privs) ) {
                if ( $char_set =~ s<\A(utf8mb[34])\z><utf8> ) {
                    if ( $1 eq 'utf8mb4' ) {
                        $self->{'_utf8mb4_downgrade'}{$dbname}{'default'} = undef;
                    }
                }
            }

            my $db_q      = $mysql_dbh_with_root_privs->quote_identifier($dbname);
            my $charset_q = $mysql_dbh_with_root_privs->quote($char_set);

            my $alter_statement = "ALTER DATABASE $db_q DEFAULT CHARACTER SET $charset_q";
            if ($coll) {
                if ( ( $coll =~ m<\Autf8mb[34]> ) && !Cpanel::MysqlUtils::Unicode::has_utf8mb4($mysql_dbh_with_root_privs) ) {
                    if ( $coll =~ s<\A(utf8mb[34])><utf8> ) {
                        if ( $1 eq 'utf8mb4' ) {
                            $self->{'_utf8mb4_downgrade'}{$dbname}{'default'} = undef;
                        }
                    }
                }

                # MySQL 8+: Collation opt of 'utf8mb4_0900_ai_ci' needs downgrading
                # to 'utf8mb4_general_ci' to ensure graceful degradation
                # Only want this if the version IS NOT 8 basically.
                if ( $coll eq 'utf8mb4_0900_ai_ci' && ( Cpanel::MysqlUtils::Version::mysqlversion() lt 8 || Cpanel::MysqlUtils::Version::mysqlversion() gt 9 ) ) {
                    $coll = 'utf8mb4_general_ci';
                }

                $alter_statement .= ' COLLATE ' . $mysql_dbh_with_root_privs->quote($coll);
            }

            my ($ok);
            try {
                $ok = $mysql_dbh_with_root_privs->do($alter_statement);
            }
            catch {
                $err = $_;
            };
            if ( !$ok && !$err ) {
                $err = try { $mysql_dbh_with_root_privs->errstr(); } || $DBI::errstr;
            }
            if ($err) {
                $self->warn( _locale()->maketext( 'The system failed to execute “[_1]” because of an error: [_2]', $alter_statement, Cpanel::Exception::get_string($err) ) );
            }
        }
    }

    return 1;
}

sub _check_for_and_warn_about_utf8mb4_conversions_for_db {
    my ( $self, $db ) = @_;

    if ( $self->{'_utf8mb4_downgrade'}{$db} ) {
        $self->warn(
            _locale()->maketext(
                'The system has downgraded [asis,UTF-8] data in the restored database “[_1]” because your [asis,MySQL] server does not support four-byte [asis,UTF-8] encoding. If the database archive contains any characters that lie outside Unicode’s [output,url,_2,Basic Multilingual Plane], the system may not have restored them. You should manually check for data corruption in the restored database.',
                $db, 'http://www.unicode.org/roadmaps/bmp/'
            )
        );
    }

    return 1;
}

sub _archive_mysql_dir {
    my ($self) = @_;

    return $self->extractdir() . '/mysql';
}

#Until we can refactor Cpanel/Mysql.pm, we need to mock the cpmysql admin here
sub _do_cpanel_mysql_with_newuser_privs {
    my ( $self, $action ) = @_;

    my $user = $self->newuser();

    # Ensure Cpanel::Mysql never writes file as root to the users homedir
    my $homedir = Cpanel::PwCache::gethomedir($>);
    local $ENV{'HOME'} = $homedir;
    local $Cpanel::homedir = $homedir;

    local $ENV{'USER'}        = $user;
    local $ENV{'USERNAME'}    = $user;
    local $ENV{'REMOTE_USER'} = $user;

    local $ENV{'REMOTE_PASSWORD'};    # Ensure that Mysql.pm does not change the password
    local $ENV{'CPRESELLER'};
    local $ENV{'WHM50'};

    my ($user_temp_mysql_passwd) = $self->_user_temp_mysql_passwd();
    if ($user_temp_mysql_passwd) {

        # In case 51221  CPRESELLER now checks for an explicit empty string
        # We need to turn off CPRESELLER and WHM50 to avoid
        # create_dbowner in Mysql.pm ignoring REMOTE_PASSWORD
        $ENV{'CPRESELLER'} = q{};
        $ENV{'WHM50'}      = 0;
    }

    my $mysql_obj_with_cpuser_privs = Cpanel::Mysql->new( { cpuser => $self->newuser() } );

    local $mysql_obj_with_cpuser_privs->{'disable_queue_dbstoregrants'} = 1;

    my @ret = $action->($mysql_obj_with_cpuser_privs);

    $mysql_obj_with_cpuser_privs->destroy();

    return wantarray ? @ret : $ret[0];
}

my $_locale;

sub _locale {
    return $_locale ||= do {
        Cpanel::LoadModule::load_perl_module('Cpanel::Locale');
        Cpanel::Locale->get_handle();
    };
}

1;
