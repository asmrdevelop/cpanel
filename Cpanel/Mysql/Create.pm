package Cpanel::Mysql::Create;

# cpanel - Cpanel/Mysql/Create.pm                  Copyright 2022 cPanel, L.L.C.
#                                                           All rights reserved.
# copyright@cpanel.net                                         http://cpanel.net
# This code is subject to the cPanel license. Unauthorized copying is prohibited

use cPstrict;

##
##
## Please try to avoid loading Cpanel::MysqlUtils in this module as it
## will increase the memory footprint and startup time of xml-api.
##
##

use parent qw(
  Cpanel::Mysql::Passwd
);

use Try::Tiny;

# Note: Cpanel::MysqlUtils was avoided
# due to memory concerns
use Cpanel::MysqlUtils::Grants        ();
use Cpanel::MysqlUtils::Grants::Users ();
use Cpanel::MysqlUtils::MyCnf::Basic  ();
use Cpanel::MysqlUtils::Compat        ();
use Cpanel::MysqlUtils::Quote         ();
use Cpanel::MysqlUtils::Command       ();
use Cpanel::Mysql::Error              ();    # PPI USE OK - needed for error reporting below
use Cpanel::LocaleString              ();
use Cpanel::DB::Utils                 ();
use Cpanel::Exception                 ();
use Cpanel::Reseller::Override        ();
use Cpanel::Session::Constants        ();
use Cpanel::Validate::IP              ();
use Cpanel::Database                  ();

our $PASSWORD_PLAINTEXT = 0;
our $PASSWORD_HASHED    = 1;

sub remove_dbowner_from_all ( $self, $user = undef ) {
    return $self->_dbowner_to_all_with_ownership_checks(
        'method' => 'REVOKE',
        'users'  => { $user => undef },
    );
}

sub remove_dbowner_from_all_without_ownership_checks ( $self, $user = undef ) {
    return $self->_dbowner_to_all_without_ownership_checks(
        'method' => 'REVOKE',
        'users'  => { $user => undef },
    );
}

sub add_dbowner_to_all ( $self, $user, $pass, $pass_is_hashed = undef, $database = undef, $force_update = undef ) {    ## no critic qw(Subroutines::ProhibitManyArgs)
    return $self->_dbowner_to_all_with_ownership_checks(
        'method'   => 'GRANT',
        'users'    => { $user => { 'pass' => $pass, 'pass_is_hashed' => $pass_is_hashed, 'force' => $force_update } },
        'database' => ( $database || '' )
    );
}

sub add_dbowner_to_all_without_ownership_checks ( $self, $user, $pass, $pass_is_hashed = undef, $database = undef ) {    ## no critic qw(Subroutines::ProhibitManyArgs)
    return $self->_dbowner_to_all_without_ownership_checks(
        'method'   => 'GRANT',
        'users'    => { $user => { 'pass' => $pass, 'pass_is_hashed' => $pass_is_hashed } },
        'database' => ( $database || '' )
    );
}

sub _dbowner_to_all_with_ownership_checks ( $self, %OPTS ) {
    my ( $method, $users, $database ) = @OPTS{ 'method', 'users', 'database' };

    my $map     = $self->_get_map();
    my $dbowner = $map->{'owner'}->name();

    my %allowed_users;
    foreach my $user ( sort keys %{$users} ) {
        if ( $method eq 'REVOKE' ) {
            if ( $self->{'cpuser'} ne 'root' && !$map->{'map'}->user_owns_dbuser( $self->{'cpuser'}, $user ) ) {
                $self->_log_error_and_output( Cpanel::LocaleString->new( "The user “[_1]” is not authorized to access “[_2]” for revoking permissions from all.", $self->{'cpuser'}, $user ) );
            }
            else {
                $allowed_users{$user} = 1;
            }
        }
        elsif ( $method eq 'GRANT' ) {
            if (   $self->{'cpuser'} ne 'root'
                && Cpanel::DB::Utils::username_to_dbowner($user) ne $dbowner
                && $map->{'map'}->dbuser_exists($user)
                && !$map->{'map'}->user_owns_dbuser( $self->{'cpuser'}, $user ) ) {
                $self->_log_error_and_output( Cpanel::LocaleString->new( "The user “[_1]” is not authorized to access “[_2]” for granting permissions to all.", $self->{'cpuser'}, $user ) );
            }
            else {
                $allowed_users{$user} = 1;
            }
        }
    }

    if ( !scalar keys %allowed_users ) {
        return ( 0, $self->_log_error_and_output_return( Cpanel::LocaleString->new( "The cPanel user “[_1]” is not allowed to grant access to any of the requested database users.", $self->{'cpuser'} ) ) );
    }

    delete @{$users}{ grep { !$allowed_users{$_} } keys %{$users} };

    return $self->_dbowner_to_all_without_ownership_checks( 'method' => $method, 'users' => $users, 'database' => $database );
}

sub _dbowner_to_all_without_ownership_checks ( $self, %OPTS ) {    ## no critic(Subroutines::ProhibitExcessComplexity)  -- Refactoring this function is a project, not a bug fix
    my ( $method, $users, $database ) = @OPTS{ 'method', 'users', 'database' };
    if ( $method ne 'GRANT' && $method ne 'REVOKE' ) {
        die Cpanel::Exception::create( 'InvalidParameter', '“[_1]” is not a valid “[_2]” parameter for “[_3]”.', [ $method, 'method', '_dbowner_to_all_without_ownership_checks' ] );
    }
    my @queries;
    my $dbuser = Cpanel::DB::Utils::username_to_dbowner( $self->{'cpuser'} );

    if ( $method eq 'REVOKE' ) {
        my $revoke_recipients_sql = $self->_create_revoke_recipients_sql_for_users( $method, $users );

        if ( length $revoke_recipients_sql ) {
            push @queries, "DROP USER $revoke_recipients_sql;";
        }

        foreach my $user ( sort keys %{$users} ) {
            if ( $user ne $dbuser ) {
                require Cpanel::MysqlUtils::Rename;
                Cpanel::MysqlUtils::Rename::change_definer_of_database_objects( $self->{'dbh'}, $user, $dbuser );
            }
        }
    }
    else {
        # set up to exclude existing GRANTs based on $user/$db/$host
        my $exclude_hosts_ref   = {};
        my $exclude_hosts_by_db = {};

        # collect hosts for deduplicating existing GRANTs that will be otherwise reissued
        foreach my $user ( grep { !$users->{$_}{'force'} } keys %{$users} ) {
            my $grants_ar = Cpanel::MysqlUtils::Grants::show_grants_for_user( $self->{'dbh'}, $user );
          EXCLUDE_HOST:
            foreach my $grant (@$grants_ar) {
                my $host = $grant->db_host();
                next EXCLUDE_HOST if $host eq q{localhost} xor $self->is_remote_mysql();

                # capture all hosts seen
                $exclude_hosts_ref->{$host} = 1;

                # capture all hosts seen for each database
                $exclude_hosts_by_db->{ $grant->db_name() }->{$host} = 1;
            }

        }

        if ( Cpanel::MysqlUtils::Compat::needs_password_plugin_disabled() ) {

            # Required for changing passwords on systems that have updated from older versions of MySQL.
            for my $user ( keys %{$users} ) {
                my $quoted_user = Cpanel::MysqlUtils::Quote::quote($user);
                for my $host ( $self->_memorized_get_host_list() ) {
                    my $quoted_host = Cpanel::MysqlUtils::Quote::quote($host);
                    push @queries, qq{
                  UPDATE
                      mysql.user
                  SET plugin = ""
                  WHERE user = $quoted_user AND host = $quoted_host AND ( plugin = "mysql_native_password" OR plugin = "mysql_old_password" )
              };
                }
            }
        }

        # MySQL 8 + no longer allows creation of users via GRANT statements.
        # As such, you need to create the dbowner first or run ALTER USER
        # to change their password.
        # To be fair, creating the user *first* is the documented way to
        # do this since mysql 5.x first came out, so we probably should have
        # been doing this anyways for a long time.
        my $grant_recipients_sql = $self->_create_grant_recipients_sql_for_users( $method, $users, $exclude_hosts_ref );
        push @queries, $grant_recipients_sql if $grant_recipients_sql;

        # add dereferencing support so $database can be an ARRAY reference
        my @DBs = ();
        if    ( ref $database eq 'ARRAY' ) { @DBs = @$database; }
        elsif ( !$database )               { @DBs = $self->listdbs(); }
        else                               { push @DBs, $database; }

        foreach my $db (@DBs) {
            $grant_recipients_sql = join( " ", $self->_get_grant_recipients_with_optional_callback( $users, $exclude_hosts_by_db->{$db}, \&_grant_only_management_cb, 'method' => $method, 'db' => $db ) );
            if ($grant_recipients_sql) {
                push @queries, $grant_recipients_sql;
            }
        }

        # MySQL procedures will not be editable if the definer if not the current user.
        foreach my $user ( sort keys %{$users} ) {
            if ( $user ne $dbuser ) {
                require Cpanel::MysqlUtils::Rename;
                Cpanel::MysqlUtils::Rename::change_definer_of_database_objects( $self->{'dbh'}, $dbuser, $user, ('PROCEDURE') );
            }
        }
    }

    # return successfully if no new GRANTs are needed
    return ( 1, 'ok' ) if not @queries;

    my $oneshot_query = join(
        ";\n",
        map {    ## no critic qw(ProhibitMutatingListFunctions)
            s/;\s*$//g;
            $_;
        } @queries
    ) . " /* _dbowner_to_all_without_ownership_checks */";

    # Lets try a oneshot with all the queries at once to avoid
    # the overhead of multiple back and forth
    my $err;
    try {
        $self->_sendmysql_untrapped($oneshot_query);
    }
    catch {
        $err = $_;
    };

    # If the oneshot fails, we fallback to doing each query one at a time
    my @query_errors = ();
    if ($err) {
        foreach my $query (@queries) {
            my $err;
            try {
                $self->_sendmysql_untrapped( $query . " /* _dbowner_to_all_without_ownership_checks */" );
            }
            catch {
                $err = $_;
            };

            if ( $err || $self->{'dbh'}->err() ) {
                if ( $method eq 'REVOKE' && $self->{'dbh'}->err() == Cpanel::Mysql::Error::ER_CANNOT_USER ) {

                    # DROP may fail for non-existent users
                    # and thats OK
                }
                else {
                    local $self->{'sendmysql_err'};
                    $self->_has_error_handler( $err . "\nQUERY: $query" );
                    if ( $self->{'sendmysql_err'} ) {
                        push @query_errors, $self->{'sendmysql_err'};
                    }
                }
            }
        }
    }
    my $map = $self->_get_map();

    foreach my $user ( keys %{$users} ) {
        if ( $map->{'owner'}->name() ne $user && $map->{'owner'}->cpuser() ne $user ) {
            if ( $method eq 'REVOKE' ) {
                $map->{'owner'}->remove_dbuser($user);
            }
            elsif ( $method eq 'GRANT' ) {
                $map->{'owner'}->add_dbuser( { dbuser => $user, server => Cpanel::MysqlUtils::MyCnf::Basic::get_server() } );
            }
        }
    }

    $self->_save_map_hash($map);

    # TODO: Make this throw an exception instead
    if (@query_errors) {
        my @users = sort keys %$users;

        if ($database) {
            $database = ( ref $database eq 'ARRAY' ) ? q{multiple dbs attempted} : $database;
            return ( 0, $self->_log_error_and_output_return( Cpanel::LocaleString->new( "The system could not perform “[_1]” statements on the database “[_2]” for the [numerate,_3,user,users] [list_and_quoted,_4] due to [numerate,_5,an error,errors]: [join,~, ,_6]", $method, $database, scalar(@users), \@users, scalar(@query_errors), \@query_errors ) ) );
        }
        else {
            return ( 0, $self->_log_error_and_output_return( Cpanel::LocaleString->new( "The system could not perform “[_1]” statements for the [numerate,_2,user,users] [list_and_quoted,_3] due to [numerate,_4,an error,errors]: [join,~, ,_5]", $method, scalar(@users), \@users, scalar(@query_errors), \@query_errors ) ) );
        }
    }

    return ( 1, 'ok' );
}

#NOTE: $adminuser can be either a cpuser or a dbowner;
#either will be (re-)normalized to a dbowner internally.
#
sub create_dbowner ( $self, $adminuser, $force_update = undef ) {

    my $map = $self->_get_map();
    if ( length $adminuser && $self->{'cpuser'} ne 'root' && !$map->{'map'}->user_owns_dbuser( $self->{'cpuser'}, $adminuser ) ) {
        return $self->_log_error_and_output( Cpanel::LocaleString->new( "The user “[_1]” is not authorized to create database owner “[_2]”.", $self->{'cpuser'}, $adminuser ) );
    }

    # $adminuser is validated inside add_dbowner_to_all
    if ( my $envpass = $self->_get_env_pass_if_available($force_update) ) {

        my $user = Cpanel::DB::Utils::username_to_dbowner($adminuser);

        # The magic number 0 means we are passing a plain text password
        # add_dbowner_to_all will make these sql sanitized
        $self->add_dbowner_to_all( Cpanel::DB::Utils::username_to_dbowner($adminuser), $envpass, $PASSWORD_PLAINTEXT, undef, $force_update );
    }
    else {
        $self->{'logger'}->warn("The system was unable to create the database owner “$adminuser” because the “REMOTE_PASSWORD” environment variable was not available.");
    }
    return;
}

sub _usergrants ( $self, $user, $hosts_ar ) {
    my $dbh = $self->{'dbh'};

    # Needed to purge MySQL's inner cache and not return grants
    # that no longer exist
    $dbh->do("FLUSH PRIVILEGES;");

    my %PRIVS;
    foreach my $host ( @{$hosts_ar} ) {
        try {
            for my $gtxt ( $dbh->show_grants( $user, $host ) ) {
                my $gobj  = Cpanel::MysqlUtils::Grants::parse($gtxt) or next;
                my $privs = $gobj->db_privs();
                $privs =~ s/^\s*|\s*$//g;
                $PRIVS{ $gobj->db_name() } = [ split m<\s*,\s*>, $privs ];
            }
        }
        catch {
            if ( !try { $_->failure_is('ER_NONEXISTING_GRANT') } ) {
                local $@ = $_;
                die;
            }
        };
    }
    return %PRIVS;
}

sub is_skip_name_resolve ($self) {
    my $dbh = $self->{'dbh'};
    my $q   = $dbh->prepare("show variables like 'skip_name_resolve';");
    $q->execute();
    my $var               = $q->fetchrow_arrayref();
    my $skip_name_resolve = $var->[1] || q<>;
    $q->finish();
    return ( $skip_name_resolve eq 'ON' ) ? 1 : 0;
}

sub user_exists ( $self, $user ) {
    return Cpanel::MysqlUtils::Command::user_exists( $user, $self->{'dbh'} );
}

#For parity with PostgresAdmin.pm
*role_exists = \&user_exists;

sub clear_memorized_hosts_lists ($self) {
    delete @{$self}{qw(_memorized_get_host_list _memorized_get_host_list_without_user_added_hosts _memorized_get_user_added_hosts)};
    return;
}

sub _memorized_get_host_list ($self) {
    $self->{'_memorized_get_host_list'} ||= scalar $self->_get_host_list();

    return wantarray ? @{ $self->{'_memorized_get_host_list'} } : $self->{'_memorized_get_host_list'};
}

sub _memorized_get_host_list_without_user_added_hosts ($self) {
    $self->{'_memorized_get_host_list_without_user_added_hosts'} ||= [ $self->_get_host_list_without_user_added_hosts() ];

    return @{ $self->{'_memorized_get_host_list_without_user_added_hosts'} };
}

sub _memorized_get_user_added_hosts ($self) {
    $self->{'_memorized_get_user_added_hosts'} ||= scalar $self->_get_user_added_hosts();

    return wantarray ? @{ $self->{'_memorized_get_user_added_hosts'} } : $self->{'_memorized_get_user_added_hosts'};
}

# Since we need to do this with differing degrees of SQL decoration,
# just let the user supply a callback if they want more than just:
# 'some_user'@'some_host'.
sub _get_grant_recipients_with_optional_callback ( $self, $users_hr, $exclude_hosts_hr, $per_host_callback = undef, %extra_args ) {    ## no critic qw(Subroutines::ProhibitManyArgs)
    my ( $hosts_for_full_users_ar, $hosts_for_temp_users_ar ) = $self->_get_hosts_to_grant_for_full_and_temp_users($exclude_hosts_hr);

    return map {
        my $user   = $_;
        my $user_q = Cpanel::MysqlUtils::Quote::quote($user);
        map {
            my $host   = $_;
            my $host_q = Cpanel::MysqlUtils::Quote::quote($host);
            if ( ref $per_host_callback eq 'CODE' ) {
                $per_host_callback->(
                    'user'        => $user,
                    'user_quoted' => $user_q,
                    'host'        => $host,
                    'host_quoted' => $host_q,
                    'users_hr'    => $users_hr,
                    %extra_args,
                );
            }
            else {
                "${user_q}\@${host_q}";
            }
        } ( index( $user, $Cpanel::Session::Constants::TEMP_USER_PREFIX ) == 0 ) ? @$hosts_for_temp_users_ar : @$hosts_for_full_users_ar;
    } sort keys %{$users_hr};
}

sub _user_and_grant_management_cb (%opts) {

    my %args;
    $args{hashed} = $opts{'users_hr'}->{ $opts{'user'} }{'pass_is_hashed'};
    my $password    = $args{hashed} ? Cpanel::MysqlUtils::Grants::unhex_hash( $opts{'users_hr'}->{ $opts{'user'} }{'pass'} ) : $opts{'users_hr'}->{ $opts{'user'} }{'pass'};
    my $auth_plugin = $opts{'users_hr'}->{ $opts{'user'} }{'auth_plugin'} || Cpanel::MysqlUtils::Grants::identify_hash_plugin( $password, 1 ) || 'mysql_native_password';
    $args{pass}   = Cpanel::MysqlUtils::Quote::quote($password);
    $args{plugin} = Cpanel::MysqlUtils::Quote::quote($auth_plugin);

    # Users do not support wildcards so we do not need to quote patterns
    # We allow patterns in hosts so we do not want to quote patterns here either.
    $args{name} = "$opts{'user_quoted'}\@$opts{'host_quoted'}";

    ( $args{exists} ) = _check_if_db_user_exists(%opts);
    $args{method} = $opts{method};

    my $db_obj = Cpanel::Database->new();
    return $db_obj->get_set_password_sql(%args);
}

sub _check_if_db_user_exists (%opts) {
    my $dbh               = $opts{'self'}->{'dbh'};
    my $user_exists_query = $dbh->prepare( 'SELECT EXISTS ( SELECT DISTINCT user FROM mysql.user WHERE user=' . $opts{'user_quoted'} . ' AND host=' . $opts{'host_quoted'} . ')' );
    $user_exists_query->execute();
    return @{ $user_exists_query->fetchrow_arrayref() };
}

sub _grant_only_management_cb (%opts) {
    my $thing2create = "$opts{'user_quoted'}\@$opts{'host_quoted'}";
    my $sql          = "$opts{'method'} ALL ON " . Cpanel::MysqlUtils::Quote::quote_pattern_identifier( $opts{'db'} ) . ".* TO $thing2create;";
    $sql .= " $opts{'method'} USAGE ON *.* TO $thing2create;";
    return $sql;
}

sub _create_grant_recipients_sql_for_users ( $self, $method, $users_hr, $exclude_hosts_hr ) {    ## no critic qw(Subroutines::ProhibitManyArgs)
    my @queries = $self->_get_grant_recipients_with_optional_callback( $users_hr, $exclude_hosts_hr, \&_user_and_grant_management_cb, 'method' => $method, 'self' => $self );

    return join( " ", @queries );
}

sub _get_hosts_to_grant_for_full_and_temp_users ( $self, $exclude_hosts_hr = undef ) {

    #XXX: Doesn’t throw
    my %HOSTS_FOR_TEMP_USERS = map { $_ => 1 } $self->_memorized_get_host_list_without_user_added_hosts();

    #XXX: Doesn’t throw
    my %USER_ADDED_HOSTS = map { $_ => 1 } grep { !$HOSTS_FOR_TEMP_USERS{$_} } $self->_memorized_get_user_added_hosts();

    #If we’re connected remotely and skip-name-resolve is ON,
    #then there’s no point in manipulating grants for hosts that aren’t
    #IP addresses. This was addressed in FB 82517; however, the logic
    #from that commit seems to have been backwards re the is_valid_ip() check.
    if ( $self->is_remote_mysql() && $self->is_skip_name_resolve() ) {
        delete @HOSTS_FOR_TEMP_USERS{ grep { !Cpanel::Validate::IP::is_valid_ip($_) } keys %HOSTS_FOR_TEMP_USERS };
        delete @USER_ADDED_HOSTS{ grep { !Cpanel::Validate::IP::is_valid_ip($_) } keys %USER_ADDED_HOSTS };
    }

    # Now remove any excluded hosts
    if ( $exclude_hosts_hr and ref $exclude_hosts_hr eq 'HASH' ) {
        delete @HOSTS_FOR_TEMP_USERS{ keys %$exclude_hosts_hr };
        delete @USER_ADDED_HOSTS{ keys %$exclude_hosts_hr };
    }

    my %HOSTS_FOR_NON_TEMP_USERS = ( %HOSTS_FOR_TEMP_USERS, %USER_ADDED_HOSTS );

    return ( [ keys %HOSTS_FOR_NON_TEMP_USERS ], [ keys %HOSTS_FOR_TEMP_USERS ] );
}

sub _create_revoke_recipients_sql_for_users ( $self, $method, $users_hr ) {

    # Note: $method is unused. In order to preserve compatiblity
    # with _create_grant_recipients_sql_for_users is is still
    # passed
    #
    my @user_host_arr;
    my $user_hosts_map = Cpanel::MysqlUtils::Grants::Users::get_all_hosts_for_users( $self->{'dbh'}, [ keys %$users_hr ] );
    foreach my $user ( keys %{$users_hr} ) {
        my $user_q = Cpanel::MysqlUtils::Quote::quote($user);
        foreach my $host ( @{ $user_hosts_map->{$user} } ) {
            push @user_host_arr, $user_q . '@' . Cpanel::MysqlUtils::Quote::quote($host);
        }
    }

    return join( ' , ', @user_host_arr );
}

#
# This function returns $ENV{'REMOTE_PASSWORD'} if the account
# is logged in with username and password auth and its is
# not using reseller overriding or temp sessions (single sign on)
#
sub _get_env_pass_if_available ( $self, $force_update = undef ) {

    # Do not update privileges when logged in with reseller pass and password is not defined in my.cnf
    my $envpass = ( ( ( !Cpanel::Reseller::Override::is_overriding() && !$ENV{'WHM50'} ) || $force_update ) && $ENV{'REMOTE_PASSWORD'} ) ? $ENV{'REMOTE_PASSWORD'} : '';    #TEMP_SESSION_SAFE
    $envpass = '' if $envpass eq '__HIDDEN__';
    return $envpass;
}

1;
