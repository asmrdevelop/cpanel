package Cpanel::Mysql::Restore::Client;

# cpanel - Cpanel/Mysql/Restore/Client.pm          Copyright 2022 cPanel, L.L.C.
#                                                           All rights reserved.
# copyright@cpanel.net                                         http://cpanel.net
# This code is subject to the cPanel license. Unauthorized copying is prohibited

use cPstrict;

=encoding utf-8

=head1 NAME

Cpanel::Mysql::Restore::Client

=head1 SYNOPSIS

    my $result_hr = Cpanel::Mysql::Restore::Client::run( %opts );

=head1 DESCRIPTION

MySQL database restorations involve two processes: one to read the
L<mysqldump(1)> stream (e.g., from a network connection or a file), and
another process that parses that stream into MySQL statements then
gives them to MySQL. This module implements the latter process’s logic.

As of this writing, the reader process’s logic resides in
L<Whostmgr::Transfers::SystemsBase::MysqlBase>. It would be nice to
refactor that for use outside the transfer system.

=cut

#----------------------------------------------------------------------
# IMPLEMENTATION NOTE: This logic was refactored out of
# Whostmgr::Transfers::SystemsBase::MysqlBase.
#----------------------------------------------------------------------

use Try::Tiny;

use Cpanel::Imports;

# This module is a class, but we only instantiate it internally.
#
use parent 'Cpanel::Hash::ForObject';

use Cpanel::Alarm                                   ();
use Cpanel::DB::Utils                               ();
use Cpanel::Finally                                 ();
use Cpanel::FHUtils::Blocking                       ();
use Cpanel::Mysql::Constants                        ();
use Cpanel::MysqlDumpParse::Event                   ();    # PPI USE OK - used dynamically
use Cpanel::MysqlDumpParse::Routine                 ();    # PPI USE OK - used dynamically
use Cpanel::MysqlDumpParse::Table                   ();
use Cpanel::MysqlDumpParse::Trigger                 ();    # PPI USE OK - used dynamically
use Cpanel::MysqlDumpParse::View                    ();    # PPI USE OK - used dynamically
use Cpanel::MysqlUtils::Connect                     ();
use Cpanel::MysqlUtils::Grants                      ();
use Cpanel::MysqlUtils::InnoDB                      ();
use Cpanel::MysqlUtils::MyCnf::Basic                ();
use Cpanel::MysqlUtils::RemoteMySQL::ProfileManager ();
use Cpanel::MysqlUtils::Statements                  ();
use Cpanel::MysqlUtils::Unicode                     ();
use Cpanel::MysqlUtils::Version                     ();
use Cpanel::Rlimit                                  ();

sub _rename_dbs_in_event_body;

my %dump_parse_transform_attributes = (
    Routine => ['routine_db'],
    Trigger => [ 'trigger_db', 'table_db' ],
    View    => ['view_db'],
    Event   => [ 'event_db', \&_rename_dbs_in_event_body ],
);

#These are only tested with the last-released versions of these major MySQL
#versions, so we restrict the functionality to what we've tested.
my %minimum_version_for_restore_db_object = (
    View    => '5.0.51',    #added in 5.0.1
    Routine => '5.0.51',    #added in 5.0.3
    Trigger => '5.1.73',    #added in 5.1.6
    Event   => '5.1.73',    #CREATE EVENT had no DEFINER clause until 5.1.17.
);

use constant {
    _MAX_MYSQL_MEMORY_ALLOWED => 1 << 30,    #1 GiB
    _MYSQL_COMMAND_TIME_LIMIT => 14400,      # 4 hours
};

# MAINTAINER: Please keep in sync w/ POD below!
use constant _CONFIG_PROPERTIES => (
    'sql_fh',
    'output_obj',
    'username',
    'old_dbname',
    'new_dbname',
    'user_mysql_password',
    'mysql_host',
    'admin_mysql_username',
    'admin_mysql_password',
    'dbname_changes',
);

#----------------------------------------------------------------------

=head1 FUNCTIONS

=head2 $result_hr = run( %OPTS )

Runs the DB restore. Blocks until complete.

%OPTS are:

=over

=item * C<sql_fh> - A filehandle over which we will receive the
L<mysqldump(1)> stream.

=item * C<output_obj> - A L<Cpanel::Output> instance that
will receive output messages.

=item * C<username> - The DB owner’s system username.

=item * C<old_dbname> - The DB name on the system where it was backed up.

=item * C<new_dbname> - The DB name on the local system.

=item * C<user_mysql_password> (possibly a temporary one)

=item * C<dbname_changes> - A hashref of old->new DB names. This should
be for I<all> of the DB owner’s MySQL databases. This is necessary because
DBs can reference each other (e.g., via stored procedures).

=item * C<mysql_host> - Either the hostname of a remote MySQL server
B<OR> an absolute filesystem path to a local MySQL server’s UNIX socket.

Ordinarily this should just reflect cPanel & WHM’s configuration and so
I<could> be optional, except that for tests we use temporary MySQL
instances, and since this module usually runs across an C<exec()> from
its parent, we need a way for the parent to tell this interface the
path to the MySQL server’s listening socket.

=item * C<admin_mysql_username> and C<admin_mysql_password> - Administrator
credentials on the MySQL server that C<mysql_host> identifies. Again,
this could be optional but is necessary for tests anyway.

=back

Throws on error. Returns a hashref:

=over

=item * C<utf8mb4_downgrade> - A hashref that describes utf8mb4-downgrade
activity during the DB restore. Keys are new DB names, and values are
hashrefs:

=over

=item * C<variable> - Lookup hash of names of variable that have been
utf8mb4-downgraded.

=item * C<table> - Like C<variable> but for tables.

=back

=back

=cut

sub run (%opts) {
    my $self = __PACKAGE__->_new(%opts);

    $self->_admin_has_super_priv();

    my $config_obj = $self->{'_config'};

    my $dbowner = Cpanel::DB::Utils::username_to_dbowner(
        $config_obj->get('username'),
    );

    my $old_dbname = $config_obj->get('old_dbname');
    my $new_dbname = $config_obj->get('new_dbname');
    my $output_obj = $config_obj->get('output_obj');

    my $sql_fh = $config_obj->get('sql_fh');

    $output_obj->out( locale()->maketext( "Connecting to SQL server ([_1]) as “[_2]” in order to restore “[_3]” …", $config_obj->get('mysql_host'), $dbowner, $new_dbname ) );

    my $dbh = $self->_create_dbh(
        dbuser   => $dbowner,
        database => $new_dbname,
        dbpass   => $config_obj->get('user_mysql_password'),
    );

    my $disconnect_user_dbh = Cpanel::Finally->new(
        sub {
            try {
                # case 106345:
                # libmariadb has been patched to send
                # and receive with MSG_NOSIGNAL
                # thus avoiding the need to trap SIGPIPE
                # which can not be reliably done in
                # perl because perl will overwrite
                # a signal handler that was done outside
                # of perl and fail to restore a localized
                # one.
                $dbh->disconnect();
            };
        }
    );

    # case CPANEL-17067: Transfer Tool database dumps fail restore with MariaDB 10.2.2 due to strictness
    $output_obj->out( locale()->maketext( "Disabling InnoDB strict mode for database restore for “[_1]” …", $new_dbname ) );
    try {
        $dbh->do('set innodb_strict_mode = OFF;');
    };

    $output_obj->out( locale()->maketext( "Restoring database data for “[_1]” …", $new_dbname ) );

    Cpanel::Rlimit::set_rlimit(_MAX_MYSQL_MEMORY_ALLOWED);

    my $alarm = Cpanel::Alarm->new(_MYSQL_COMMAND_TIME_LIMIT);

    my $cur_delimiter = ';';
    my $cur_statement;
    my ( $dbi_ok, $dbi_err );

    $self->{'is_cpcloud'} = $self->_is_cpcloud();

    my $process_statement = sub {
        $alarm->set(_MYSQL_COMMAND_TIME_LIMIT);

        $cur_statement =~ s{$cur_delimiter\n$}{};

        ( $dbi_ok, $dbi_err ) = $self->_handle_one_delimited_mysql_statement( \$cur_statement, $dbh );

        return if !$dbi_ok;

        $cur_statement = '';

        return 1;
    };

    local $!;

    Cpanel::FHUtils::Blocking::set_blocking($sql_fh);

    my $alerted_to_start;

    while ( readline $sql_fh ) {
        if ( !$alerted_to_start ) {
            $alerted_to_start = 1;
            $output_obj->out( locale()->maketext('Processing SQL statements …') );
        }

        if ( my ($new_delimiter) = m{\ADELIMITER (\S+)\s*\z}i ) {
            if ( length $cur_statement && $cur_statement =~ m{$cur_delimiter} ) {
                my $die_msg = locale()->maketext( '“[_1]”’s [asis,MySQL] backup contains an error: The backup contains a statement ([_2]) that defines a new delimiter ([_3]). That delimiter occurs in the phrase before its designation as delimiter, though.', $old_dbname, $cur_statement, $new_delimiter );
                die $die_msg;
            }
            $cur_delimiter = $new_delimiter;
        }
        elsif ( m{^--} || m{^\s+$} ) {

            # ignore comments
        }
        else {
            $cur_statement .= $_;

            # Process the statements one at a time.
            if ( $cur_statement =~ m{$cur_delimiter\n$} ) {
                if ( !$process_statement->() ) {
                    die $dbi_err;
                }
            }
        }
    }
    if ($!) {
        my $die_msg = _locale()->maketext( 'The system failed to read “[_1]”’s [asis,MySQL] backup because of an error: [_2]', $old_dbname, $! );
        die $die_msg;
    }

    if ( length $cur_statement ) {
        if ( !$process_statement->() ) {
            die $dbi_err;
        }
    }

    #The hashref return is to send back specific data to the parent process.
    return { utf8mb4_downgrade => $self->{'_utf8mb4_downgrade'}{$new_dbname} };
}

#----------------------------------------------------------------------

sub _create_dbh ( $self, @args_kv ) {
    my $config_obj = $self->{'_config'};

    my $mysql_host = $config_obj->get('mysql_host');

    my %extra_args = (
        max_allowed_packet => Cpanel::Mysql::Constants::MAX_ALLOWED_PACKET,
    );

    if ( $mysql_host =~ tr</><> ) {
        $extra_args{'mysql_socket'} = $mysql_host;
    }

    return Cpanel::MysqlUtils::Connect::get_dbi_handle(
        dbuser     => $config_obj->get('admin_mysql_username'),
        dbpass     => $config_obj->get('admin_mysql_password'),
        dbserver   => ( $mysql_host =~ tr</><> ) ? 'localhost' : $mysql_host,
        extra_args => \%extra_args,
        @args_kv,
    );
}

sub _new ( $class, %opts ) {
    my @missing = grep { !length $opts{$_} } _CONFIG_PROPERTIES;
    die "Missing: @missing" if @missing;

    my $config = Cpanel::Mysql::Restore::Client::_METADATA->new()->set(%opts);

    return bless {
        _config     => $config,
        _has_innodb => scalar Cpanel::MysqlUtils::InnoDB::is_enabled(),
    }, $class;
}

sub _handle_one_delimited_mysql_statement ( $self, $sql_r, $user_dbh ) {    ## no critic qw(Subroutines::ProhibitExcessComplexity)

    my $new_dbname = $self->{'_config'}->get('new_dbname');

    if ( !$self->{'_has_innodb'} ) {
        $self->{'_has_innodb'} = ( $$sql_r =~ m{^ENGINE=(?:InnoDB|INNODB|innodb)}m );
        if ( $self->{'_has_innodb'} ) {
            Cpanel::MysqlUtils::InnoDB::enable();    # will also restart mysql
        }
    }

    my ( $stmt_obj, $err );

    if ( Cpanel::MysqlUtils::Statements::is_create_statement($$sql_r) ) {
        my %stripped_for_mysql_version;

        ( $self->{'_dbh_version'} ) ||= Cpanel::MysqlUtils::MyCnf::Basic::get_server_version($user_dbh);

        for my $parse_class ( keys %dump_parse_transform_attributes ) {

            my $use_mysql_version = $self->_get_mysql_version_for_parse_class($parse_class);

            $stripped_for_mysql_version{$use_mysql_version} ||= Cpanel::MysqlUtils::Statements::strip_comments_for_version( $use_mysql_version, $$sql_r );

            #ease of reading
            my $copy_r = \$stripped_for_mysql_version{$use_mysql_version};

            my $attrs_ar = $dump_parse_transform_attributes{$parse_class};

            if ( "Cpanel::MysqlDumpParse::$parse_class"->looks_like($$copy_r) ) {
                try {
                    $stmt_obj = "Cpanel::MysqlDumpParse::$parse_class"->new($$copy_r);
                }
                catch {
                    if ( !UNIVERSAL::isa( $_, 'Cpanel::Exception::InvalidParameter' ) ) {
                        $err = $_;
                    }
                };

                if ($stmt_obj) {

                    #Necessary at least for triggers because MySQL 5.0 did
                    #not allow unprivileged users to CREATE TRIGGER.
                    return 1 if !Cpanel::MysqlUtils::Version::is_at_least(
                        $self->{'_dbh_version'},
                        $minimum_version_for_restore_db_object{$parse_class},
                    );

                    for my $attr (@$attrs_ar) {
                        if ( 'CODE' eq ref $attr ) {
                            $attr->( $self, $stmt_obj );
                        }
                        else {

                            #The statement we've parsed may not give a database
                            #for this object, which means to use the currently
                            #selected database. Let's be safely explicit, and
                            #set that database if the statement doesn't already
                            #have it.
                            my $old_db = $stmt_obj->get($attr);

                            my $new_db_name =
                              defined($old_db)
                              ? $self->_new_dbname_name($old_db)
                              : $self->{'_config'}->get('new_dbname');

                            $stmt_obj->set(
                                $attr,
                                $new_db_name,
                            );
                        }
                    }
                }
            }

            last if $stmt_obj || $err;
        }

        if ( !$stmt_obj && $$sql_r =~ m<table>i ) {

            $$sql_r = $self->_handle_cpcloud($$sql_r) if $self->{'is_cpcloud'};

            if ( !Cpanel::MysqlUtils::Unicode::has_utf8mb4($user_dbh) ) {
                $self->_strip_utf8mb4_from_create_table_statement( $sql_r, $user_dbh );
            }

            if ( $self->{'_dbh_version'} !~ /^8/ ) {

                # MySQL 8+: Collation opt of 'utf8mb4_0900_ai_ci' needs downgrading
                # to 'utf8mb4_general_ci' to ensure graceful degradation
                # Only want this if the version IS NOT 8 basically.
                $$sql_r = Cpanel::MysqlUtils::Statements::replace_in_command_outside_quoted_strings(
                    qr<COLLATE\s*=\s*utf8mb4_0900_ai_ci>i,
                    'COLLATE=utf8mb4_general_ci',
                    $$sql_r,
                );
            }
        }
    }
    elsif ( my ( $key, $value ) = Cpanel::MysqlUtils::Statements::parse_set_statement($$sql_r) ) {
        if ( $key =~ m/GLOBAL\.GTID_PURGED/ || $key =~ m/SESSION\.SQL_LOG_BIN/ ) {

            # These SETs cannot be run without SUPER priv and will cause RDS backup restorations to fail
            return 1 unless $self->_admin_has_super_priv();
        }
        if ( ( $key =~ m<\Acharacter_set> || $key =~ m<\Acollation> ) && !Cpanel::MysqlUtils::Unicode::has_utf8mb4($user_dbh) ) {
            if ( $value =~ m<\Autf8mb[34]> ) {
                if ( $$sql_r =~ s<(utf8mb[34])><utf8> ) {
                    if ( $1 eq 'utf8mb4' ) {
                        $self->{'_utf8mb4_downgrade'}{$new_dbname}{'variable'}{$key} = undef;
                    }
                }
            }
        }
    }

    return ( 0, $err ) if $err;

    my $todo_sql_r;

    if ($stmt_obj) {
        $stmt_obj->set( 'definer_name', undef );
        $todo_sql_r = \$stmt_obj->to_string();
    }
    else {
        $todo_sql_r = $sql_r;
    }

    $user_dbh->do($$todo_sql_r) or do {
        return ( 0, _locale()->maketext( 'The [asis,MySQL] server reported an error ([_1]) in response to this request: [_2]', $user_dbh->errstr(), $$todo_sql_r ) );
    };

    return 1;
}

sub _admin_has_super_priv ($self) {
    return $self->{'_has_super_priv'} //= do {
        my $root_dbh = $self->_create_dbh();

        my $statement = 'SHOW GRANTS;';
        my $sth       = $root_dbh->prepare($statement);
        $sth->execute();

        my $has_super;

        while ( my $data = $sth->fetchrow_arrayref() ) {
            my $statement = $data->[0];
            my $grant     = eval { Cpanel::MysqlUtils::Grants->new($statement) } or next;
            my %privs     = map { $_ => 1 } split( /, /, $grant->db_privs() );
            if ( exists $privs{'SUPER'} ) {
                $has_super = 1;
                last;
            }
        }

        $has_super || 0;
    };
}

sub _strip_utf8mb4_from_create_table_statement ( $self, $sql_r ) {

    my $use_mysql_version = $self->_get_mysql_version_for_parse_class("Table");

    my $comment_stripped_sql = Cpanel::MysqlUtils::Statements::strip_comments_for_version( $use_mysql_version, $$sql_r );

    my $table_obj;
    try {
        $table_obj = Cpanel::MysqlDumpParse::Table->new($comment_stripped_sql);
    }
    catch {
        die $_ if !$_->isa('Cpanel::Exception::InvalidParameter');
    };

    if ($table_obj) {
        my $orig_sql = $$sql_r;

        $$sql_r = Cpanel::MysqlUtils::Statements::replace_in_command_outside_quoted_strings(
            qr<(?:CHARACTER SET|CHARSET)\s+utf8mb[34] >i,
            'CHARSET utf8 ',
            $$sql_r,
        );

        #Not part of
        $$sql_r = Cpanel::MysqlUtils::Statements::replace_in_command_outside_quoted_strings(
            qr<(?:CHARACTER SET|CHARSET)\s*=\s*utf8mb[34]>i,
            'CHARSET=utf8 ',
            $$sql_r,
        );

        my ( $utf8mb4_occurrences_before, $utf8mb4_occurrences_after ) = ( 0, 0 );

        ++$utf8mb4_occurrences_before while $orig_sql =~ m<utf8mb4>g;
        ++$utf8mb4_occurrences_after  while $$sql_r   =~ m<utf8mb4>g;

        if ( $utf8mb4_occurrences_before != $utf8mb4_occurrences_after ) {
            my $new_dbname = $self->{'_config'}->get('new_dbname');

            $self->{'_utf8mb4_downgrade'}{$new_dbname}{'table'}{ $table_obj->get('table_name') } = undef;
        }

        #NOTE: We rely on the fact that mysqldump doesn't quote encoding names.
        #
        #As of 5.5.37:
        #   - The MySQL docs don't seem to indicate which quoting to use.
        #     (i.e., `utf8mb4` or 'utf8mb4')
        #   - The server accepts unquoted, string-quoted, or id-quoted.
        #   - mysqldump never appears to output quoted encoding names.
    }

    return;
}

sub _get_mysql_version_for_parse_class {
    my ( $self, $parse_class ) = @_;

    my $parser_mysql_version = "Cpanel::MysqlDumpParse::$parse_class"->mysql_version();

    return ( sort { Cpanel::MysqlUtils::Version::cmp_versions( $a, $b ) } ( $parser_mysql_version, $self->{'_dbh_version'} ) )[0];
}

sub _new_dbname_name ( $self, $old_dbname ) {
    my $changes_hr = $self->{'_config'}->get('dbname_changes');

    return $changes_hr->{$old_dbname} // $old_dbname;
}

sub _archive_dbnames ($self) {
    my $changes_hr = $self->{'_config'}->get('dbname_changes');

    return keys %$changes_hr;
}

# MySQL clustering requires the use of InnoDB as the storage engine.
sub _handle_cpcloud ( $self, $statement ) {
    return $statement if $statement =~ m/ENGINE=InnoDB/i;

    $statement = Cpanel::MysqlUtils::Statements::replace_in_command_outside_quoted_strings(
        qr{(?<=ENGINE\=)(?:Aria|MyISAM)}i,
        'InnoDB',
        $statement,
    );

    my @incompatible_table_options = qw{
      CHECKSUM
      DELAY_KEY_WRITE
      PAGE_CHECKSUM
      TABLE_CHECKSUM
      TRANSACTIONAL
      UNION
    };
    my $bad_option_re = join( '|', @incompatible_table_options );
    $statement = Cpanel::MysqlUtils::Statements::replace_in_command_outside_quoted_strings(
        qr{\s(?:$bad_option_re)=\S+(?=\s|$)}i,
        '',
        $statement,
    );

    return $statement;
}

#NOTE: This will only work if the user QUOTED their DB names in the event body;
#otherwise, it'll do nothing. The import will still succeed, but the command
#will fail when it actually executes.
sub _rename_dbs_in_event_body ( $self, $event_obj ) {

    for my $old_db ( $self->_archive_dbnames() ) {
        $event_obj->set(
            'body',
            Cpanel::MysqlUtils::Statements::rename_db_in_command(
                $old_db,
                $self->_new_dbname_name($old_db),
                $event_obj->get('body'),
            ),
        );
    }

    return;
}

# for tests
sub _ensure_all_db_connections_closed {
    return;
}

# for tests
sub _is_cpcloud ($self) {
    return Cpanel::MysqlUtils::RemoteMySQL::ProfileManager->new( { 'read_only' => 1 } )->is_active_profile_cpcloud();
}

#----------------------------------------------------------------------

package Cpanel::Mysql::Restore::Client::_METADATA;

use parent 'Cpanel::Hash::Strict';

use constant _PROPERTIES => Cpanel::Mysql::Restore::Client::_CONFIG_PROPERTIES;

1;
