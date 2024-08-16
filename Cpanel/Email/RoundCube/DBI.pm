package Cpanel::Email::RoundCube::DBI;

# cpanel - Cpanel/Email/RoundCube/DBI.pm           Copyright 2024 cPanel, L.L.C.
#                                                           All rights reserved.
# copyright@cpanel.net                                         http://cpanel.net
# This code is subject to the cPanel license. Unauthorized copying is prohibited

## REVIEW NOTE: this is not new code; extracted from ::RoundCube.pm

## note: this module uses DBI (including introspective features like &table_info
##   and &last_insert_id) and cannot be used within compiled code

use cPstrict;

use Try::Tiny;
use File::Basename ();

use Cpanel::AccessIds::ReducedPrivileges ();
use Cpanel::Email::RoundCube             ();
use Cpanel::Exception                    ();
use Cpanel::JSON                         ();
use Cpanel::DBI                          ();
use Cpanel::LoadFile                     ();
use Cpanel::MysqlUtils::Connect          ();
use Cpanel::SafeRun::Object              ();
use Cpanel::FileUtils::Move              ();
use Cpanel::Logger                       ();
use Cpanel::SafetyBits                   ();
use Cpanel::Validate::AccountData        ();
use Cpanel::Locale                       ();
use Cpanel::MysqlUtils::Quote            ();
use Cpanel::FileUtils::RaceSafe::SQLite  ();

# For testing
our $rc_dir = '/usr/local/cpanel/base/3rdparty/roundcube';
my %schema_info = (
    'roundcube-version' => {
        'initial' => sub ($dbtype) {
            return "$rc_dir/SQL/$dbtype.initial.sql";
        },
        'updates' => sub ($dbtype) {

            # NOTE: If nothing is found here, permissions probably bad on dir. Needs +x for globbing
            return map {
                my $file = $_;
                my ($key) = $file =~ m/(\d{10}).*\.sql$/;
                $key ||= 'unknown';
                $key => $file
            } _get_sql_from_dir("$rc_dir/SQL/$dbtype");
        },
    },
    'calendar-caldav-version' => {
        'initial' => sub ($dbtype) {
            return "$rc_dir/plugins/calendar/drivers/caldav/SQL/$dbtype.initial.sql";
        },
        'updates' => sub ($dbtype) {
            return map {
                my $file = $_;
                my ($key) = $file =~ m/(\d{10}).*\.sql$/;
                $key ||= 'unknown';
                $key => $file
            } _get_sql_from_dir("$rc_dir/plugins/calendar/drivers/caldav/SQL/$dbtype");
        },
    },
    'calendar-database-version' => {
        'initial' => sub ($dbtype) {
            return "$rc_dir/plugins/calendar/drivers/database/SQL/$dbtype.initial.sql";
        },
        'updates' => sub ($dbtype) {
            return map {
                my $file = $_;
                my ($key) = $file =~ m/(\d{10}).*\.sql$/;
                $key ||= 'unknown';
                $key => $file
            } _get_sql_from_dir("$rc_dir/plugins/calendar/drivers/database/SQL/$dbtype");
        },
    },
    'libkolab-version' => {
        'initial' => sub ($dbtype) {
            return "$rc_dir/plugins/libkolab/SQL/$dbtype.initial.sql";
        },
        'updates' => sub ($dbtype) {
            return map {
                my $file = $_;
                my ($key) = $file =~ m/(\d{10}).*\.sql$/;
                $key ||= 'unknown';
                $key => $file
            } _get_sql_from_dir("$rc_dir/plugins/libkolab/SQL/$dbtype");
        },
    },
    'broken' => {
        'initial' => \&_broken_full,
    },
);

# Used to avoid globbing, though if the dir isn't +x the open on the file
# will fail as well, so we don't gain much other than it not simply failing
# silently to grab files list on bad permissions.
sub _get_sql_from_dir ($dir) {
    opendir( my $dh, $dir ) or die "Can't open $dir for reading: $!";
    return map { "$dir/$_" } grep { rindex( $_, ".sql" ) == length($_) - 4 } readdir($dh);
}

my %deferrals = (
    '2021100300' => 'sqlite.2023030100.migration',
);

# So, roundcube has *always* had a set of certain tables even from before
# they even issued schema update files in 2008. Unfortunately, some mysql
# dumps *as late as 2014* do not even contain these! As such these are quite
# clearly broken DBs that are probably in need of manual repair.
# That said, we can *at least* try to impose some semblance of normalcy
# based on a fallback set of schema statements.
sub _broken_full ($dbtype) {
    return "/usr/local/cpanel/src/3rdparty/gpl/roundcube_schema/repair/$dbtype";
}

our $logger = Cpanel::Logger->new();

##############################
## DATABASE HANDLING

## regarding return values: database operations will cascade an undef up the
## chain, so that the caller (e.g. bin/update-roundcube-db) can restore the
## archive; return values are more forgiving only on the first run through of
## the schema update, as we have to safely assume a schema version of 0.2b;
## this assumption likely happens on a 0.5 schema machine

## final thought: DBI operations often return a "zero results but still true"
## value of "0E0"... on MySQL.

## main entry point
sub ensure_schema_update {
    my ( $dbh, $db_type ) = @_;

    my $db_versions_ar = get_schema_versions_from_db($dbh);
    my $db_versions_hr = { map { my $ar = $_; $ar->[0] => $ar->[1] } @$db_versions_ar };
    my $versions_str   = join( "\n", map { "  $_ - $db_versions_hr->{$_}" } sort keys(%$db_versions_hr) );
    $logger->info("Detected database versions:\n$versions_str");

    my $needs_run_ar = get_schema_update_files( $db_versions_hr, $db_type );

    if ( !scalar(@$needs_run_ar) ) {
        $logger->info("All schema already applied. Nothing to do...");
        return 1;
    }
    my %deferred;
    foreach my $file (@$needs_run_ar) {

        # CPANEL-42798... sometimes the ordering is too hard to get right
        # without extra hinting. See %deferrals hash defined above.
        my $basename = File::Basename::basename( $file, ".sql" );
        if ( $deferrals{$basename} && grep { $deferrals{$basename} eq File::Basename::basename( $_, '.sql' ) } @$needs_run_ar ) {
            $logger->info("Deferring run of $basename until $deferrals{$basename}...");
            $deferred{ $deferrals{$basename} } = $file;
            next;
        }

        # Dies on mysql failure, warns on sqlite failure.
        _try_to_apply( $file,                       $dbh );
        _try_to_apply( delete $deferred{$basename}, $dbh ) if ( $deferred{$basename} );
    }

    return 1;
}

sub _try_to_apply ( $file, $dbh ) {
    my $err;
    try {

        $logger->info("Applying $file...");
        my $sql = Cpanel::LoadFile::load($file);

        # DBI still lives in the dark ages RE error reporting.
        my $err_tarp = 'Unknown Error';
        local $SIG{__WARN__} = sub { $err_tarp = $_[0] };

        # Allow multiple statements in do() so that schema will apply
        local $dbh->{'sqlite_allow_multiple_statements'} = 1;
        my $ret = $dbh->do($sql);
        if ($ret) {

            # Great success. Ensure that RC schema version is updated
            # to reflect the schema file name, as RC isn't the best at
            # updating this itself within its' own schema files.
            my ( $ver, $migration ) = $file =~ m/(\d+|initial)(\.migration)?\.sql$/;

            # RC only started tracking db version in 2013
            if ( $ver ne 'initial' && $ver gt '2013011000' ) {
                my $name2update = $migration ? 'calendar-database-version' : 'roundcube-version';
                my $update      = 'UPDATE `system` SET `value`=? WHERE `name`=?';
                my $rv;
                local $@;
                eval {
                    my $sth = $dbh->prepare($update);
                    $rv = $sth->execute( $ver, $name2update );
                };
                die "Couldn't update `system` table to set $name2update=$ver!" if !$rv || $@;
            }
        }
        else {

            # Sqlite failure path. Should probably force die on both, but while
            # we have the situation of "unclear database schema version"
            # it can't realistically be insisted upon for sqlite.
            $logger->warn("Schema update failed for $file: $err_tarp");
        }
    }
    catch {
        $err = $_;
    };
    if ($err) {

        # MySQL failure path... So far all the servers in the "wild" seem
        # caught by either the fixer schema or other workarounds. That along
        # with the relatively low usage of MySQL has so far meant that dying
        # here isn't (yet) causing big problems.
        my $error  = Cpanel::Exception::get_string($err);
        my $errstr = "Problem encountered during schema update:\n\tSchema file: $file\n\tError: $error";
        die $errstr;
    }
    return;
}

sub convert_sqlite2_to_sqlite3 {
    my $source = shift;

    # this is a simple dump using DBI to convert the sqlite2 to a sqlite3 file

    # check if file has a non-zero size
    return unless -s $source;

    # check if file is a known sqlite2 db
    # cannot rely on `file` to get the version number, but if available use it
    my $run = Cpanel::SafeRun::Object->new(
        'program' => 'file',
        'args'    => [$source],
        stderr    => \*STDERR,
    );
    my $type = $run->stdout();
    my $version;
    if ( $type && ( $type =~ /:\s+sqlite\s*([0-9]+)/i || $type =~ /:\s+SQLite database \(Version ([0-9]+)\)/i ) ) {
        $version = $1;
    }

    # Since we can't rely on `file`, then bail out only if we get positive confirmation that this an sqlite db and NOT version 2.
    return if ( $version && $version != 2 );

    my @path       = split( '/', $source );
    my $short_path = "$path[-2]/$path[-1]";
    print "INFO - converting $short_path from SQLite 2 to SQLite 3\n";

    my $destination = "$source.converted";
    unlink $destination if -e $destination;

    # This may return falsey if the source file is corrupted in a way that
    # DBD::SQlite can immediately detect it, before any other checks are
    # performed.
    my $dbh = _get_dbh( $source, "dbi:SQLite2:dbname=$source" );
    return unless $dbh;

    # A connected db handle does not guarantee a usable database. Some
    # corrupted dbs can pass an integrity_check but are not able to list any
    # tables.  Others can list tables but not pass the integrity_check. There
    # will be other ways a database can be broken that we can't detect here,
    # but these checks will cover the worst cases.
    my $found_errors;
    try {
        # integrity_check returns one row with string "ok" if it passes
        my $check = $dbh->selectrow_arrayref('PRAGMA integrity_check');
        if ( ref $check ne 'ARRAY' || !defined $check->[0] || $check->[0] ne 'ok' ) {
            print "WARN - 'PRAGMA integrity_check' found errors on $short_path - is it a valid sqlite file?\n";
            $found_errors = 1;
        }
        elsif ( !$dbh->tables( q{%}, q{%}, q{%}, q{'TABLE', 'VIEW'} ) ) {
            print "WARN - $short_path does not contain any tables - is it a valid sqlite2 file?\n";
            $found_errors = 1;
        }
    }
    catch {
        print "WARN - Sanity checks failed for $short_path: " . $_->get('message') . "\n";
        $found_errors = 1;
    };
    return if $found_errors;

    my $dbh3   = _get_dbh( $destination, "dbi:SQLite:dbname=$destination" ) or return;
    my @tables = $dbh->tables( q{%}, q{%}, q{%}, q{'TABLE', 'VIEW'} );

    foreach my $table (@tables) {
        my $sth   = $dbh->table_info( '', '', $table );
        my $tinfo = $sth->fetchall_arrayref();
        next unless my $schema = $tinfo->[0][5];
        $dbh3->do($schema);

        my $read = $dbh->prepare("select * from $table");
        my $write;
        next unless $read && $read->execute;
        while ( my $row = $read->fetchrow_arrayref ) {
            my $cols = scalar @$row;
            $write ||= $dbh3->prepare( "insert into $table values ( " . join( ', ', map { '?' } 1 .. $cols ) . " )" ) or next;
            $write->execute(@$row);
        }
    }

    $dbh->disconnect();
    $dbh3->disconnect();

    my $time = time();
    my ( $sec, $min, $hour, $mday, $mon, $year ) = localtime($time);
    my $timestamp = sprintf( '%04d%02d%02d%02d%02d%02d.sqlite2', $year + 1900, $mon + 1, $mday, $hour, $min, $sec );

    # preserve permission and owner
    my ( $mode, $uid, $gid ) = ( stat($source) )[ 2, 4, 5 ];
    my $permissions = $mode & 07777;

    return unless Cpanel::FileUtils::Move::safemv( $source, "$source.$timestamp" );
    my $ok = Cpanel::FileUtils::Move::safemv( $destination, $source );

    my @to_update = ("$source.$timestamp");
    push @to_update, $source if $ok;

    for my $f (@to_update) {
        Cpanel::SafetyBits::safe_chown( $uid, $gid, $f );
        Cpanel::SafetyBits::safe_chmod( $permissions, $uid, $f );
    }

    return $ok;
}

sub get_schema_versions_from_db ($dbh) {
    die "No database handle" unless ref $dbh;
    my ( $sth, $rv );

    # Tested, works on sqlite and MySQL.
    my @tables = map { m/\.["`]([a-zA-Z_-]+)["`]$/ } $dbh->tables();

    my %sqls = (
        'system' => [
            'SELECT `name`, `value` FROM `system` WHERE `name` IN (?,?,?,?);',
            qw{roundcube-version libkolab-version calendar-database-version calendar-caldav-version},
        ],
        'cp_schema_version' => [
            'SELECT `applied` FROM `cp_schema_version` ORDER BY `version_id` DESC LIMIT 1;',
        ],
    );
    foreach my $table2check (qw{system cp_schema_version contactgroups users}) {
        next if !grep { $_ eq $table2check } @tables;

        # Just run all schema updates, lord knows how old this is
        return [ [ 'roundcube-version', 1 ] ] if $table2check eq 'users';

        # Found this one out due to trial, error and a very evil integration
        # test. If contactgroups exists but session does not, the schema is
        # in fact broken. Instead choose a specially crafted repair schema
        # based off the current "initial" schema.
        return [ [ 'broken', 0 ] ] if $table2check eq 'contactgroups' && !grep { $_ eq 'session' } @tables;

        # So, we should have filtered out everything that doesn't have sql in
        # tables2check right now, but if this is somehow not true, just move on.
        next if !defined $sqls{$table2check};

        # On extremely old (earlier than 2013) sqlite2 DBs, you won't even have
        # the system table. We had our own table to check this during such time.
        # Otherwise check the table roundcube uses to store schema versions.
        local $@;
        my $err;
        local $SIG{__WARN__} = sub { $err = $_; };
        my ( $rv, $data );
        eval {
            my $sth = $dbh->prepare( shift @{ $sqls{$table2check} } );
            $rv   = $sth->execute( @{ $sqls{$table2check} } );
            $data = $dbh->selectall_arrayref($sth);
        };
        next if $@ || !$rv || !scalar @$data;

        # It turns out RC's own schema updates (and ours) have not
        # been real good at keeping the roundcube-version OR cp_schema_version
        # updated.
        # In the case that the `collected_addresses` table exists yet responses
        # does not, then just apply everything past the table which created
        # collected_addresses. That should at least fix things going forward.
        # In this case we shouldn't have to worry about calendar updates,
        # as we're up to date enough that roundcube itself should be able to
        # handle it without this tool.
        if (
            scalar(
                grep {
                    my $tbl = $_;
                    grep { my $wanted = $_; $tbl eq $wanted } qw{collected_addresses responses}
                } @tables
            ) == 1
        ) {
            $data = [ [ 'roundcube-version', '2020122900' ], grep { $_->[0] eq 'calendar-database-version' } $data->@* ];
        }

        return $data if $table2check eq 'system';

        # We did not `applied` time in epoch format. Most unfortunate.
        # At least only people with these crazy old DBs have to pay the
        # price.
        require DateTime::Format::Strptime;
        my $strp = DateTime::Format::Strptime->new(
            'pattern' => '%F %T',    # 2013-12-31 23:55:00
        );
        my $d_obj = $strp->parse_datetime( @{ $data->[0] }[0] );

        # 2012081700 (00 is just whatever you want it to be).
        # That said, the "jitter" between when we recorded a timestamp
        # and when schema updates actually came out means our test database
        # will in fact miss out on some schema. As such, fudge the time to
        # be a the start of the year.
        return [ [ 'roundcube-version', $d_obj->strftime("%Y010100") ] ];
    }

    return [ [ 'none', 'Inital schema likely not installed' ] ] if !$rv || $@;
    return $dbh->selectall_arrayref($sth);
}

sub get_schema_update_files ( $db_versions_hr, $dbtype ) {
    my @needed;
    my @keys = exists $db_versions_hr->{'broken'} ? ('broken') : ('roundcube-version');
    push @keys, ( 'libkolab-version', 'calendar-caldav-version', 'calendar-database-version' );
    foreach my $key (@keys) {
        if ( !$db_versions_hr->{$key} ) {    # First time install
            push @needed, $schema_info{$key}->{'initial'}->($dbtype);
        }
        else {                               # Update only
            my %updates = $schema_info{$key}->{'updates'}->($dbtype);
            push @needed, ( sort map { $updates{$_} } grep { exists $db_versions_hr->{$key} and $_ > $db_versions_hr->{$key} } keys(%updates) );
        }
    }

    return \@needed;
}

# Mainly here because tests for this expect crazy
sub _get_dbh ( $db_fullpath, $dsn ) {
    my ( $dbh, $err );
    try {
        $dbh = Cpanel::DBI->connect( $dsn, '', '' );
    }
    catch {
        $err = $_;
    };
    if ( !$dbh || $err ) {    # Create if not exists/crazy
        my $new_sqlite = Cpanel::FileUtils::RaceSafe::SQLite->new(
            path => $db_fullpath,
        );

        $dbh = $new_sqlite->dbh();
    }

    return $dbh;
}

##############################
sub sqlite_schema_updates_for_user {
    my ( $sysuser, $RCUBE_VERSION, $dbs_ref ) = @_;
    for my $dbinfo (@$dbs_ref) {
        try {
            my $db_fullpath = sprintf( '%s/%s', $dbinfo->{base_dir}, $dbinfo->{db_fname} );

            my $convert_db = sub { convert_sqlite2_to_sqlite3($db_fullpath) };
            Cpanel::AccessIds::ReducedPrivileges::call_as_user( $convert_db, $sysuser );

            my $archive_update_restore_coderef = sub {
                return unless Cpanel::Email::RoundCube::archive_sqlite_roundcube($dbinfo);
                Cpanel::Email::RoundCube::prune_roundcube_archives(
                    $dbinfo->{base_dir}, $dbinfo->{db_fname} . '.\d+',
                    "$dbinfo->{db_fname}.latest"
                );

                ## SOMEDAY: in the event the logging is too verbose (in that it
                ##   obscures actual problems), then the deepest context (more
                ##   than likely _run_update_files) is going to need $dbinfo in
                ##   order to declare its context (i.e. an update for 'sysuser'
                ##   on email account 'email'@'domain'); there are several ways
                ##   technically to get the information there, but the easiest
                ##   would be to pass it thru the chain as a optional last
                ##   positional arg

                my $dsn = "dbi:SQLite:dbname=" . $db_fullpath;
                my $dbh = _get_dbh( $db_fullpath, $dsn );
                return unless ensure_schema_update( $dbh, 'sqlite', $RCUBE_VERSION );

                $dbh->disconnect();

                ## note: can't really restore the backup, as it now relates to the wrong schema;
                ##   and presumably can't use the current; until we understand the extent of this
                ##   problem, provide good logging
                return 1;
            };

            print "\n#########################\n";
            my $email =
              defined $dbinfo->{domain}
              ? sprintf( "%s@%s", $dbinfo->{user}, $dbinfo->{domain} )
              : $dbinfo->{user};
            print "Performing updates as user '$sysuser' on email account '$email'\n";
            print "The sqlite database is $dbinfo->{base_dir}/$dbinfo->{db_fname}\n";

            my $rv = Cpanel::AccessIds::ReducedPrivileges::call_as_user( $archive_update_restore_coderef, $sysuser );
            ## note: can't really do anything with the return value, as we need to determine
            ##   the types of problems we might encounter
        }
        catch {
            local $@ = $_;
            warn;
        };
    }
    return 1;
}

##############################
## THE CONFLICTING UID RESOLVER

## ASSUMPTIONS (which hold true for present-day 0.5.1)
## foreign keys are named the same as what they map to
## the only numeric datatypes currently used are INT and TINYINT
## primary keys that are not auto increments are really foreign keys
##   (specifically, part of a compound foreign key) (see contactgroupmembers)

my @UID_SOLVER_TABLES = (
    {
        name => 'users',
    },

    {
        name    => 'contacts',
        depends => [
            [ users => 'user_id' ],
        ],
    },

    {
        name    => 'contactgroups',
        depends => [
            [ users => 'user_id' ],
        ],
    },

    {
        name    => 'contactgroupmembers',
        depends => [
            [ contactgroups => 'contactgroup_id' ],
            [ contacts      => 'contact_id' ],
        ],
    },

    {
        name    => 'identities',
        depends => [
            [ users => 'user_id' ],
        ],
    },

);

sub mysql_db_connect {
    my ( $dbname, $host, $user, $pass, $attrs, $port ) = @_;

    $user ||= 'roundcube';
    $pass ||= Cpanel::Email::RoundCube::get_roundcube_password();
    $port ||= 3306;

    my %opts = (
        RaiseError => 1,
        PrintError => 1,
        host       => $host,
    );
    for my $key ( keys %opts ) {
        if ( defined $attrs && exists $attrs->{$key} ) {
            $opts{$key} = $attrs->{$key};
        }
    }
    my $dbh = Cpanel::MysqlUtils::Connect::get_dbi_handle(
        ( $dbname ? ( database => $dbname ) : () ),
        dbserver   => $opts{'host'},
        dbuser     => $user,
        dbpass     => $pass,
        dbport     => $port,
        extra_args => {
            RaiseError => $opts{'RaiseError'},
            PrintError => $opts{'PrintError'}
        }
    );
    return $dbh;
}

sub uid_solver {
    my ( $src_dbh, $dest_dbh, $owner, $old_owner ) = @_;

    if ( !length $owner ) {
        die Cpanel::Exception::create( 'MissingParameter', 'Provide the owner of the “[_1]” data.', ['Roundcube'] );
    }
    elsif ( !length $old_owner ) {
        die Cpanel::Exception::create( 'MissingParameter', 'Provide the previous owner of the “[_1]” data.', ['Roundcube'] );
    }

    my $tblinfo;
    {
        ## get meta-information for CATALOG and SCHEMA, just in case
        my $sth_tblinfo = $dest_dbh->table_info( '', '', '', 'TABLE' );
        $tblinfo = $sth_tblinfo->fetchrow_hashref();
    }

    #Copy this structure as a fail-safe so that, if we ever do
    #two of these operations in the same process, the first won't
    #affect the second.
    my @uid_solver_tables = @{ Cpanel::JSON::Load( Cpanel::JSON::Dump( \@UID_SOLVER_TABLES ) ) };

    for my $table (@uid_solver_tables) {
        my $sth_colinfo = $dest_dbh->column_info(
            $tblinfo->{'TABLE_CAT'}, $tblinfo->{'TABLE_SCHEM'},
            $table->{name},          '%'
        );

        my ( @columns, @primary_keys, %needs_quote );
        while ( my $row = $sth_colinfo->fetchrow_hashref() ) {
            my $column_name = $row->{COLUMN_NAME};
            if ( $row->{mysql_is_pri_key} && $row->{mysql_is_auto_increment} ) {
                push( @primary_keys, $column_name );
            }
            else {
                push( @columns, $column_name );
            }
            ## quotes are not needed for INT and TINYINT
            unless ( $row->{TYPE_NAME} =~ m/INT$/ ) {
                $needs_quote{$column_name} = 1;
            }
        }
        $table->{columns} = \@columns;
        ## put the column names in single quotes. only really needed for `reply-to`
        my @columns_str = map { Cpanel::MysqlUtils::Quote::quote_identifier($_) } @columns;
        $table->{columns_str}  = join( ', ', @columns_str );
        $table->{primary_keys} = \@primary_keys;
        $table->{needs_quote}  = \%needs_quote;
    }

    my $account_validator_coderef = Cpanel::Validate::AccountData::generate_object_owner_validation( $owner, $logger );
    my $new_uids                  = {};
    my %seen_user_ids;
    for my $table (@uid_solver_tables) {
        my $tblname = $table->{name};
        my $sql     = "SELECT * FROM $tblname";
        my $sth     = $src_dbh->prepare($sql);
        my $rv      = $sth->execute();
        while ( my $row = $sth->fetchrow_hashref() ) {
            if ( defined $table->{depends} ) {
                ## modifies $row in place
                if ( !_massage( $row, $table, $new_uids ) ) {
                    $logger->info( _locale()->maketext( "The system will skip data in table “[_1]” because it could not migrate the UID because it does not belong to “[_2]”.", $table->{'name'}, $old_owner ) );
                    next;
                }
            }

            if ( $table->{'name'} eq 'users' ) {
                if ( length $old_owner && $row->{'username'} eq $old_owner && $old_owner ne $owner ) {
                    $row->{'username'} = $owner;
                }
                if ( !$account_validator_coderef->( $row->{'username'}, $Cpanel::Validate::AccountData::ALLOW_VALID ) ) {
                    $logger->info( _locale()->maketext( "The system did not import the user “[_1]” because it does not belong to: “[_2]”.", $row->{'username'}, $old_owner ) );
                    next;
                }
                if ( $seen_user_ids{ $row->{'username'} } ) {

                    # This doesn't account for if we have already seen the username so we we swap
                    # this it will be wrong the second time and it will fail with "DBD::mysql::st execute failed: Cannot add or update a child row: a foreign key constraint fails (`roundcube`.`contacts`, CONSTRAINT `user_id_fk_contacts` FOREIGN KEY (`user_id`) REFERENCES `users` (`user_id`) ON DELETE CASCADE ON UPDATE CASCADE)"

                    $logger->info( _locale()->maketext( "The system did not import the user “[_1]” with userid “[_2]” because it is a duplicate.", $row->{'username'}, $row->{'user_id'} ) );
                    $new_uids->{'users'}->{'user_id'}->{ $row->{'user_id'} } = $seen_user_ids{ $row->{'username'} };
                    next;
                }
            }
            my $insert_sql = _get_sql( $dest_dbh, $table, $row );

            # print "$insert_sql\n";

            my $sth = $dest_dbh->prepare($insert_sql);
            my $rv  = $sth->execute();

            for my $primary_key ( @{ $table->{primary_keys} } ) {
                ## SOMEDAY: maybe skip this completely if contactgroupmemebers
                my $prev_id = $row->{$primary_key};

                my $new_id = $dest_dbh->last_insert_id(
                    $tblinfo->{'TABLE_CAT'}, $tblinfo->{'TABLE_SCHEM'},
                    $tblname,                $primary_key
                );

                # eg. ID 1406 becomes 141 (users - user_id) [, roundcube, users, user_id]
                # print "ID $prev_id becomes $new_id ($tblname - $primary_key) [$tblinfo->{'TABLE_CAT'}, $tblinfo->{'TABLE_SCHEM'}, $tblname, $primary_key]\n";
                # $logger->info( "ID $prev_id becomes $new_id ($tblname - $primary_key) [$tblinfo->{'TABLE_CAT'}, $tblinfo->{'TABLE_SCHEM'}, $tblname, $primary_key]" );
                #
                $new_uids->{$tblname}->{$primary_key}->{$prev_id} = $new_id;

                if ( $tblname eq 'users' && $primary_key eq 'user_id' ) {
                    $seen_user_ids{ $row->{'username'} } = $new_id;
                }
            }
        }
    }

    return 1;
}

sub _massage {
    my ( $row, $table, $new_uids ) = @_;
    for my $dependency ( @{ $table->{depends} } ) {
        my ( $foreign_key_tbl, $foreign_key ) = @$dependency;
        my $prev_value = $row->{$foreign_key};
        if ( exists $new_uids->{$foreign_key_tbl}->{$foreign_key}->{$prev_value} ) {
            $row->{$foreign_key} = $new_uids->{$foreign_key_tbl}->{$foreign_key}->{$prev_value};
        }
        else {
            return 0;
        }
    }
    return 1;
}

sub _get_sql {
    my ( $dbh, $table, $row ) = @_;

    my $cols = $table->{columns_str};
    my @vals;
    for my $col ( @{ $table->{columns} } ) {
        my $val = $row->{$col};
        if ( exists $table->{needs_quote}->{$col} ) {
            push( @vals, $dbh->quote($val) );
        }
        else {
            ## CPANEL-10102: currently, the default value is *only* used by the
            ##   recently introduced 'failed_login_counter' column (the only
            ##   integer-based nullable column in the five tables this code is
            ##   interested in); the default value of empty string was
            ##   generating a SQL statement that had syntax problems
            ##   (i.e. "..., NULL, , 'en_US',...")
            push( @vals, defined $val ? $val : q{NULL} );
        }
    }
    my $vals = join( ', ', @vals );

    my $quoted_table = $dbh->quote_identifier( $table->{'name'} );

    # use replace rather than insert in case of some entries remain from a previous account
    return qq[REPLACE INTO $quoted_table ($cols) VALUES ($vals)];
}

my $locale;

sub _locale {
    return $locale ||= Cpanel::Locale->get_handle();
}

1;
