package Cpanel::Mysql::Basic;

# cpanel - Cpanel/Mysql/Basic.pm                   Copyright 2022 cPanel, L.L.C.
#                                                           All rights reserved.
# copyright@cpanel.net                                         http://cpanel.net
# This code is subject to the cPanel license. Unauthorized copying is prohibited

use strict;
use warnings;

=encoding utf-8

=head1 NAME

Cpanel::Mysql::Basic - A subset of Cpanel::Mysql functionality intended for use with pkgacct

=head1 SYNOPSIS

    use Cpanel::Mysql::Basic ();

    my $ob = Cpanel::Mysql::Basic->new( { 'cpconf' => $cpconf, 'cpuser' => $user, 'ERRORS_TO_STDOUT' => 1 } );

=cut

##
##
## Please try to avoid loading Cpanel::MysqlUtils in this module as it
## will increase the memory footprint and startup time of xml-api.
##
##

use parent qw(
  Cpanel::DBAdmin
);

use Try::Tiny;
use Cpanel::Config::LoadCpConf        ();
use Cpanel::Exception                 ();
use Cpanel::LoadFile                  ();
use Cpanel::Session::Constants        ();
use Cpanel::LocaleString              ();
use Cpanel::MysqlUtils::Grants::Users ();
use Cpanel::MysqlUtils::MyCnf::Basic  ();
use Cpanel::MysqlUtils::Quote         ();

#XXX: We should avoid hitting the `mysql` DB directly whenever possible;
#instead, use more "public" APIs like SHOW GRANTS.
use constant {
    DB_MYSQL    => 'mysql',
    _map_dbtype => 'MYSQL',
    DB_ENGINE   => 'mysql',
};

#This can accept a hashref of named args:
#   cpuser - The cPanel username
#
#   user - i.e., for the DB connection (default 'root')
#   pass - for the above ^^
#   host - for the above ^^
#
sub new {
    my ( $class, $args ) = @_;

    $args ||= {};

    my $self = { %{$args} };
    bless $self, $class;

    my ( $dbserver, $dbuser, $dbpass, $dbport ) = $self->_dbserver_user_pass();
    require Cpanel::Logger;

    $self->{'logger'}        = Cpanel::Logger->new();
    $self->{'sendmysql_err'} = '';

    if ( !exists $self->{'cpconf'} || !scalar keys %{ $self->{'cpconf'} } ) {
        $self->{'cpconf'} = Cpanel::Config::LoadCpConf::loadcpconf_not_copy();
    }

    $self->{'dbh'} = $self->_get_dbh( $dbserver, $dbuser, $dbpass, $dbport );

    $self->{'cpuser'} ||= $Cpanel::user;
    $self->{'pwstring'}      = $self->{'cpconf'}{'usemysqloldpass'} ? 'old_password' : 'password';
    $self->{'host'}          = $dbserver;
    $self->{'time_zone_set'} = 0;

    if ( !$self->{'dbh'} ) {
        require Cpanel::Carp;
        die Cpanel::Carp::safe_longmess( "Creating MySQL connection failed: " . ( $self->{'dbh'} && ref $self->{'dbh'} ) ? try { $self->{'dbh'}->errstr() } : $DBI::errstr );
    }

    $self->{'hasmysqlso'} = 0;
    try {
        if ( $self->{'dbh'}->isa('DBI::db') ) { $self->{'hasmysqlso'} = 1; }
    };
    $self->_set_pid();

    return $self;
}

sub dumpsql {
    my ($self) = @_;
    my $all_grants_ref = $self->fetch_grants();

    if (@$all_grants_ref) {
        print join( '', @$all_grants_ref );
    }

    return 1;
}

sub fetch_grants {
    my $self = shift;

    my @USERS_AND_HOSTS = $self->listusersandhosts();
    my @all_grants;
    foreach my $array_ref (@USERS_AND_HOSTS) {
        my ( $user, $host ) = @{$array_ref};

        return if !$self->{'dbh'};
        my $dbh = $self->{'dbh'};
        my @grants;
        eval { @grants = $dbh->show_grants( $user, $host ); };
        if ( !$@ && scalar @grants ) {
            push @all_grants, map { "$_;\n" } @grants;
        }
        else {
            $self->{'logger'}->warn("SHOW GRANTS FAILED: show grants for '$user'\@'$host'; $@");
        }
    }

    return \@all_grants;
}

# Returns a hash ref of user@host with auth plugin and password hash
sub get_authentication_plugin_type {
    my ($self) = @_;

    my %user_host_auth_info;
    my @USERS_AND_HOSTS = $self->listusersandhosts();
    foreach my $array_ref (@USERS_AND_HOSTS) {
        my ( $user, $host ) = @{$array_ref};

        return if !$self->{'dbh'};
        my $dbh = $self->{'dbh'};

        eval {
            # 5.6 and lower use "password" column, 5,7 -> 8 use "authentication_string" for the password hash. While 5.6 has an authentication_string column, it seems to be unused
            # regardless of the auth plugin
            # To determine which to use, we need to check and see which columns are available (5.6 has password and authentication_string, newer only have authentication_string)
            my $password_column_query = $dbh->prepare('SELECT COUNT(*) FROM INFORMATION_SCHEMA.COLUMNS WHERE TABLE_SCHEMA="mysql" and TABLE_NAME="user" and COLUMN_NAME="password"');
            $password_column_query->execute();

            my ($password_column_exists) = @{ $password_column_query->fetchrow_arrayref() };

            my $useful_info_query;
            if ( $password_column_exists > 0 ) {
                $useful_info_query = $dbh->prepare('SELECT plugin,HEX(authentication_string),HEX(password) FROM user WHERE User=? AND Host=?');
            }
            else {
                $useful_info_query = $dbh->prepare('SELECT plugin,HEX(authentication_string) FROM user WHERE User=? AND Host=?');
            }
            $useful_info_query->execute( $user, $host ) or die $dbh->errstr;

            my ( $plugin, $pass_hash, $old_pass_hash ) = @{ $useful_info_query->fetchrow_arrayref() };

            # Cover 5.6 and older
            if ( !$pass_hash && $old_pass_hash ) {
                $pass_hash = $old_pass_hash;
            }
            $user_host_auth_info{$user}{$host}{'auth_plugin'} = $plugin;
            $user_host_auth_info{$user}{$host}{'pass_hash'}   = $pass_hash;
        };
        if ($@) {
            $self->{'logger'}->warn("Failed to get MySQL plugin type and hash for '$user'\@'$host'; $@");
        }
    }
    return ( \%user_host_auth_info );
}

sub listusersandhosts {
    my ($self) = @_;
    return @{ $self->_listusersandhosts() };
}

sub last_update_time {
    my ( $self, $db ) = @_;
    require HTTP::Date;
    my $time = 0;

    my $safe_db = Cpanel::MysqlUtils::Quote::quote_identifier($db);

    my $dbh = $self->{'dbh'};
    $self->sendmysql(" SET time_zone = '-0:00'; ") && ( $self->{'time_zone_set'} = 1 )
      if !$self->{'time_zone_set'};

    #If the DB has any views set up, those can mess up the logic below.
    #The ISNULL() check here should weed those out.
    my $sth = $dbh->prepare("SHOW TABLE STATUS IN $safe_db WHERE !ISNULL(Create_time);");

    my $err;
    try {
        $sth->execute();
    }
    catch {
        $err = $_;
    };

    if ( !$err && $sth ) {
        my $table_time;
        my $has_null_time = 0;    # db does not support Update_time (e.g. InnoDB)
        while ( my $data = $sth->fetchrow_hashref() ) {

            if ( !$data->{'Update_time'} || $data->{'Update_time'} eq 'NULL' ) {

                # If an update time comes back NULL, it means we are unable to
                # determine the update time, so best to just bail out and assume
                # the database is updated in the future.  This will allow
                # backups to detect that the database should be backed up rather
                # than mistakenly skipping backup when they actually may need it.
                $time          = 0;
                $has_null_time = 1;
                last;
            }
            $table_time = HTTP::Date::str2time( $data->{'Update_time'}, 'GMT' );
            if ( $time < $table_time ) { $time = $table_time; }
        }
        $time ||= 1 if !$has_null_time;
    }
    else {
        $self->_log_error_and_output( Cpanel::LocaleString->new( "The system failed to fetch the status of the database “[_1]” because of an error: [_2]", $db, Cpanel::Exception::get_string($err) ) );
    }

    $time ||= ( time() + ( 86400 * 365.25 ) );    #if we fail return a time in the future

    return $time;
}

sub sendmysql {
    my ( $self, $sql, $attrs, @bind ) = @_;

    $self->{'sendmysql_err'} = '';

    my ( $err, $ret );
    try {
        $ret = $self->_sendmysql_untrapped( $sql, $attrs, @bind );
    }
    catch {
        $err = $_;
    };

    return $self->_has_error_handler($err) ? undef : $ret;
}

sub listusers {
    my $self = shift;

    my $map   = $self->_get_map();
    my $owner = $map->{'owner'}->name();
    my $name;
    my @mapped_users = map {
        $name = $_->name();
        ( $name eq $owner || $name =~ m{^\Q$Cpanel::Session::Constants::TEMP_USER_PREFIX\E} ) ? () : $name
    } $map->{'owner'}->dbusers();
    push @mapped_users, _get_additional_mysql_users( $self->{'cpuser'} );
    return @mapped_users;
}

sub destroy {
    my ($self) = @_;

    $self->clear_map();    ## ensure we do not error on global destruct

    return if !$self->{'dbh'};

    return if $self->{'dbh'}->{'AutoInactiveDestroy'} && !$self->{'dbh'}->{'Active'};

    # case 106345:
    # libmariadb has been patched to send
    # and receive with MSG_NOSIGNAL
    # thus avoiding the need to trap SIGPIPE
    # on disconnect which can not be reliably
    # done in perl because perl will overwrite
    # a signal handler that was done outside
    # of perl and fail to restore a localized
    # one.

    #Important not to write to $@ here!!
    try {
        $self->{'dbh'}->disconnect();
    };

    $self->{'dbh'} = undef;

    return;
}

#For testing.
sub _dbserver_user_pass {
    my ($self) = @_;

    my $dbuser   = $self->{'user'} || Cpanel::MysqlUtils::MyCnf::Basic::getmydbuser('root') || 'root';
    my $dbpass   = $self->{'pass'} || Cpanel::MysqlUtils::MyCnf::Basic::getmydbpass('root') || '';
    my $dbport   = $self->{'port'} || Cpanel::MysqlUtils::MyCnf::Basic::getmydbport('root') || 3306;
    my $dbserver = $self->_get_dbserver();

    return ( "$dbserver", $dbuser, $dbpass, $dbport );
}

sub _rename_dbowner {
    my ( $self, $old_dbowner, $new_dbowner ) = @_;

    require Cpanel::MysqlUtils::Rename;
    Cpanel::MysqlUtils::Rename::rename_user( $self->{'dbh'}, $old_dbowner, $new_dbowner );

    return 1;
}

sub _get_dbserver {
    my ($self) = @_;

    return $self->{'host'} || Cpanel::MysqlUtils::MyCnf::Basic::getmydbhost('root') || 'localhost';
}

sub _get_additional_mysql_users {
    my $user = shift;
    if ( -e '/var/cpanel/mysql/usermap/' . $user ) {
        return grep { !/^[\r\n\s]+$/ } split(
            /\n/,
            Cpanel::LoadFile::loadfile( '/var/cpanel/mysql/usermap/' . $user )
        );
    }
    return;
}

sub _sendmysql_untrapped {
    my ( $self, $sql, $attrs, @bind ) = @_;

    # case 106345:
    # libmariadb has been patched to send
    # and receive with MSG_NOSIGNAL
    # thus avoiding the need to trap SIGPIPE
    # which can not be reliably
    # done in perl because perl will overwrite
    # a signal handler that was done outside
    # of perl and fail to restore a localized
    # one.

    return $self->{'dbh'}->do( $sql, $attrs, @bind );
}

sub _has_error_handler {
    my ( $self, $err ) = @_;

    my $err_str = $err || $self->{'dbh'}->err() && $self->{'dbh'}->errstr();

    if ($err_str) {
        my $err_out = Cpanel::Exception::get_string($err_str);

        if ( $self->{'ERRORS_TO_STDOUT'} ) {
            local $| = 1;
            print "Error from MySQL query: $err_out\n";
        }
        $self->{'logger'}->warn("Error from MySQL query: $err_out");

        $self->{'sendmysql_err'} = $err_out;

        return 1;
    }

    return 0;
}

sub _listusersandhosts {
    my ($self) = @_;
    return $self->_convert_user_hosts_map_to_user_and_hosts_ar( $self->_get_all_hosts_for_users_owner );
}

sub _convert_user_hosts_map_to_user_and_hosts_ar {
    my ( $self, $user_hosts_map ) = @_;

    my @USERS_AND_HOSTS;
    foreach my $user ( sort keys %{$user_hosts_map} ) {
        foreach my $host ( sort @{ $user_hosts_map->{$user} } ) {
            push( @USERS_AND_HOSTS, [ $user, $host ] );
        }
    }

    return \@USERS_AND_HOSTS;
}

sub _get_all_hosts_for_users_owner {
    my ($self) = @_;

    my $owner     = $self->_get_map()->{'owner'}->name();
    my %user_list = map { $_ => 1 } ( $owner, $self->listusers() );

    return Cpanel::MysqlUtils::Grants::Users::get_all_hosts_for_users( $self->{'dbh'}, [ keys %user_list ] );
}

sub _get_dbh {
    my ( $self, $dbserver, $dbuser, $dbpass, $dbport ) = @_;

    require Cpanel::MysqlUtils::Connect;

    # case 106345:
    # libmariadb has been patched to send
    # and receive with MSG_NOSIGNAL
    # thus avoiding the need to trap SIGPIPE
    # which can not be reliably
    # done in perl because perl will overwrite
    # a signal handler that was done outside
    # of perl and fail to restore a localized
    # one.
    my ( $dbh, $err );
    try {
        $dbh = Cpanel::MysqlUtils::Connect::get_dbi_handle(
            'database'   => 'mysql',
            'dbuser'     => $dbuser || 'root',
            'dbpass'     => $dbpass,
            'dbserver'   => $dbserver,
            'dbport'     => $dbport || 3306,
            'extra_args' => {
                'mysql_local_infile' => 0,

                # Disable ANSI_QUOTES if it is enabled
                'mysql_init_command' => "set sql_mode='' /* DISABLE ANSI_QUOTES and normalize */;",
                'debug'              => 0,
            }
        );
    }
    catch {
        $err = $_;
    };

    if ($err) {
        $dbh = undef;
        die $self->_log_error_and_output_return( Cpanel::LocaleString->new( "Error while connecting to MySQL: [_1]", Cpanel::Exception::get_string($err) ) );
    }
    elsif ($DBI::errstr) {
        die $self->_log_error_and_output_return( Cpanel::LocaleString->new( "Error while connecting to MySQL: [_1]", $DBI::errstr ) );
    }
    elsif ( !$dbh ) {
        die $self->_log_error_and_output_return( Cpanel::LocaleString->new("Error while connecting to MySQL: unknown failure.") );
    }

    # Perlcc has a problem with this in the connect line
    $dbh->{'AutoInactiveDestroy'} = 1;

    return $dbh;
}

1;
