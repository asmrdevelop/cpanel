package Cpanel::Postgres;

# cpanel - Cpanel/Postgres.pm                      Copyright 2022 cPanel, L.L.C.
#                                                           All rights reserved.
# copyright@cpanel.net                                         http://cpanel.net
# This code is subject to the cPanel license. Unauthorized copying is prohibited

use strict;
use warnings;

=head1 MODULE

C<Cpanel::Postgres>

=head1 DESCRIPTION

C<Cpanel::Postgres> provides APIs related to managing Postgres databases in
the product.

=head1 SYNOPSIS

  use Cpanel::Postgres ();

  my $databases = eval{ Cpanel::Postgres::list_databases() };
  if (my $exception = $@) {
    # failed
  } else {
    # proceed with your list of databases for the current user.
  }


=head1 FUNCTIONS

=cut

use Try::Tiny;

use Cpanel                                     ();
use Cpanel::AdminBin                           ();
use Cpanel::AdminBin::Call                     ();
use Cpanel::CachedCommand::Utils               ();
use Cpanel::Config::LoadCpConf                 ();
use Cpanel::DB::Map::Reader                    ();
use Cpanel::DB::Prefix                         ();
use Cpanel::DB::Prefix::Conf                   ();
use Cpanel::Encoder::URI                       ();
use Cpanel::Encoder::Tiny                      ();
use Cpanel::Exception                          ();
use Cpanel::LoadFile                           ();
use Cpanel::Logger                             ();
use Cpanel::PasswdStrength::Check              ();
use Cpanel::Postgres::DB                       ();
use Cpanel::Security::Authz                    ();
use Cpanel::Server::Type::Role::PostgresClient ();

use Capture::Tiny;

our $VERSION = '1.6';

my $logger = Cpanel::Logger->new();

$Cpanel::NEEDSREMOTEPASS{'Postgres'} = 1;

sub _verify_feature {
    Cpanel::Security::Authz::verify_user_has_feature( $Cpanel::user, 'postgres' );

    return;
}

sub _verify_role {
    Cpanel::Server::Type::Role::PostgresClient->verify_enabled();

    return;
}

sub _countdbs { goto &Cpanel::Postgres::DB::countdbs; }
sub _listdbs  { goto &Cpanel::Postgres::DB::listdbs; }

sub Postgres_init {
    $Cpanel::NEEDSREMOTEPASS{'Postgres'} = 1;
    return $Cpanel::NEEDSREMOTEPASS{'Postgres'};
}

sub _set_api1_error {
    my ($error) = @_;
    $Cpanel::CPERROR{'postgres'} = $error;
    print STDERR "$error\n";
    print Cpanel::Encoder::Tiny::safe_html_encode_str($error), "\n";
    return;
}

sub _check_api1_error {
    if ( $Cpanel::CPERROR{'postgres'} ) {
        _set_api1_error( $Cpanel::CPERROR{'postgres'} );
        return;
    }
    return 1;
}

sub _api1_check_server {
    if ( !server_up() ) {
        _set_api1_error('The PostgreSQL server is currently offline.');
        return;
    }

    return 1;
}

#This will add the DB prefix UNLESS the given name already has it.
sub Postgres_adduser {
    my ( $user, $pass ) = @_;
    _verify_role();
    _verify_feature();
    return _demomessage() if _democheck();

    my $app = 'postgres';
    if ( !Cpanel::PasswdStrength::Check::check_password_strength( 'pw' => $pass, 'app' => $app ) ) {
        my $required_strength = Cpanel::PasswdStrength::Check::get_required_strength($app);
        _set_api1_error("Sorry, the password you selected cannot be used because it is too weak and would be too easy to guess.  Please select a password with strength rating of $required_strength or higher.");
        return;
    }

    _api1_check_server() or return;

    if ( Cpanel::DB::Prefix::Conf::use_prefix() ) {
        $user = Cpanel::DB::Prefix::add_prefix_if_name_needs( $Cpanel::user, $user );
    }

    require Cpanel::Validate::DB::User;
    local $@;
    if ( !eval { Cpanel::Validate::DB::User::verify_pgsql_dbuser_name($user) } ) {
        my $err = $@;
        _set_api1_error( $err->to_string() );
        return;
    }

    try {
        Cpanel::AdminBin::Call::call( 'Cpanel', 'postgresql', 'CREATE_USER', $user, $pass );
    }
    catch {
        _set_api1_error( Cpanel::Exception::get_string($_) || 'Unknown error' );
    };

    return;
}

sub Postgres_adddb {
    my ($database_name) = @_;
    _verify_role();
    _verify_feature();
    return _demomessage() if _democheck();

    _api1_check_server() or return;

    if ( Cpanel::DB::Prefix::Conf::use_prefix() ) {
        $database_name = Cpanel::DB::Prefix::add_prefix_if_name_needs( $Cpanel::user, $database_name );
    }

    require Cpanel::Validate::DB::Name;
    Cpanel::Validate::DB::Name::verify_pgsql_database_name($database_name);

    Cpanel::CachedCommand::Utils::destroy( 'name' => 'postgres-db-count' );

    Cpanel::AdminBin::Call::call( 'Cpanel', 'postgresql', 'CREATE_DATABASE', $database_name );

    return;
}

sub Postgres_deluser {
    my @args = @_;

    _verify_role();
    _verify_feature();
    return _demomessage() if _democheck();

    _api1_check_server() or return;

    print Cpanel::AdminBin::adminrun( 'postgres', "DELUSER", @args );

    return _check_api1_error();
}

sub Postgres_deldb {
    my ($database_name) = @_;

    _verify_role();
    _verify_feature();
    return _demomessage() if _democheck();

    _api1_check_server() or return;

    Cpanel::CachedCommand::Utils::destroy( 'name' => 'postgres-db-count' );

    try {
        Cpanel::AdminBin::Call::call( 'Cpanel', 'postgresql', 'DELETE_DATABASE', $database_name );
    }
    catch {
        _set_api1_error( Cpanel::Exception::get_string($_) || 'Unknown error' );
    };

    return;
}

sub Postgres_updateprivs {
    _verify_role();

    print Cpanel::Encoder::Tiny::safe_html_encode_str( Cpanel::AdminBin::adminrun( 'postgres', "UPDATEPRIVS" ) );

    return _check_api1_error();
}

sub _listusers {
    my @USERS;
    if (   exists $Cpanel::CPCACHE{'postgres'}{'cached'}
        && $Cpanel::CPCACHE{'postgres'}{'cached'}
        && exists $Cpanel::CPCACHE{'postgres'}{'USER'} ) {
        foreach my $user ( keys %{ $Cpanel::CPCACHE{'postgres'}{'USER'} } ) {
            push @USERS, $user;
        }
    }
    else {
        @USERS = _get_map_reader()->get_dbusers();
    }

    return @USERS;
}

# sets the CPVAR{'postgres_number_of_dbs'} variable and prints the result
sub Postgres_number_of_dbs {
    my @args = @_;

    _verify_role();

    my @DBS = _listdbs(@args);
    $Cpanel::CPVAR{'postgres_number_of_dbs'} = scalar(@DBS);
    print scalar(@DBS);

    return;
}

# sets the CPVAR{'postgres_number_of_users'} variable and prints the result
sub Postgres_number_of_users {
    my @args = @_;

    _verify_role();

    my @USERS = _listusers(@args);
    $Cpanel::CPVAR{'postgres_number_of_users'} = scalar(@USERS);
    print scalar(@USERS);

    return;
}

sub Postgres_listusers {
    my @args = @_;

    _verify_role();

    my @USERS = _listusers(@args);

    foreach my $user ( sort @USERS ) {
        print "$user <a href=\"deluser.html?user=$user\"><img src=\"/frontend/$Cpanel::CPDATA{'RS'}/images/delete.jpg\" border=\"0\" alt=\"\" /></a><br />";
    }

    return;
}

sub Postgres_listusersopt {
    my @args = @_;

    _verify_role();

    my @USERS = _listusers(@args);
    foreach my $user ( sort @USERS ) {
        $user = Cpanel::Encoder::Tiny::safe_html_encode_str($user);
        print '<option ' . ( $args[0] eq $user ? 'selected="selected"' : '' ) . '  value="' . $user . '">' . $user . "</option>\n";
    }

    return;
}

sub Postgres_listdbsopt {
    my (@args) = @_;

    _verify_role();

    my @DBS = _listdbs(@args);
    foreach my $db ( sort @DBS ) {
        $db = Cpanel::Encoder::Tiny::safe_html_encode_str($db);
        print "<option " . ( $args[0] eq $db ? 'selected="selected"' : '' ) . "  value=\"$db\">$db</option>\n";
    }

    return;
}

sub _cacheddiskusage {
    require Cpanel::UserDatastore;

    my $usage = Cpanel::LoadFile::loadfile( Cpanel::UserDatastore::get_path($Cpanel::user) . '/postgres-disk-usage' ) || 0;
    return int $usage;
}

sub _diskusage {
    my %DBSPACE = _listdbswithspace();
    my $total   = 0;
    foreach my $db ( keys %DBSPACE ) {
        $total += $DBSPACE{$db};
    }
    return $total;
}

sub _listdbswithspace {
    my %DBSPACE;
    if (
        $Cpanel::CPCACHE{'postgres'}{'DBSpacecached'}
        || ( exists $Cpanel::CPCACHE{'postgres'}{'cached'}
            && $Cpanel::CPCACHE{'postgres'}{'cached'} )
    ) {
        %DBSPACE = map { $_ => ( keys %{ $Cpanel::CPCACHE{'postgres'}{'DBDISKUSED'}{$_} } )[0] } keys %{ $Cpanel::CPCACHE{'postgres'}{'DBDISKUSED'} };
    }
    else {
        return if !_countdbs();
        my $db_list = Cpanel::AdminBin::adminrun( 'postgres', 'LISTDBSWITHSPACE' );
        return if $Cpanel::CPERROR{'postgres'};
        $Cpanel::CPCACHE{'postgres'}{'DBSpacecached'} = 1;
        $Cpanel::CPCACHE{'postgres'}{'DBcached'}      = 1;
        foreach my $uitem ( split( /\n/, $db_list ) ) {
            my ( $db, $spaceused ) = split( /\t/, $uitem );
            next if !length $db;
            $Cpanel::CPCACHE{'postgres'}{'DB'}{$db}         = 1;
            $Cpanel::CPCACHE{'postgres'}{'DBDISKUSED'}{$db} = { $spaceused => 1 };
            $DBSPACE{$db}                                   = $spaceused;
        }
    }

    return %DBSPACE;
}

sub Postgres_listdbs {
    my @args = @_;

    _verify_role();

    my @DBS = _listdbs(@args);

    foreach my $db ( sort @DBS ) {
        my $htmlsafe_db = Cpanel::Encoder::Tiny::safe_html_encode_str($db);
        my $urisafe_db  = Cpanel::Encoder::URI::uri_encode_str($db);
        print "<b>$htmlsafe_db</b>";
        print "<a href=\"deldb.html?db=$urisafe_db\"><img src=\"/frontend/$Cpanel::CPDATA{'RS'}/images/delete.jpg\" border=\"0\" alt=\"\" /></a></blockquote>";
        print "<blockquote><u>Users in $htmlsafe_db</u><br />";
        my (@USERS) = _listusersindb($db);
        foreach my $user ( sort @USERS ) {
            print "$user <a href=\"deluserfromdb.html?db=${urisafe_db}&amp;user=$user\"><img src=\"/frontend/$Cpanel::CPDATA{'RS'}/images/delete.jpg\" border=\"0\" alt=\"\" /></a><br />";
        }
        print "</blockquote>\n";
    }

    return;
}

sub _listusersindb {
    my $db = shift;

    my @USERS;
    if ( exists $Cpanel::CPCACHE{'postgres'}{'cached'} && $Cpanel::CPCACHE{'postgres'}{'cached'} ) {
        foreach my $dbuser ( keys %{ $Cpanel::CPCACHE{'postgres'}{'DBUSER'}{$db} } ) {
            push @USERS, $dbuser;
        }
    }
    else {
        @USERS = _get_map_reader()->get_dbusers_for_database($db);
    }

    return @USERS;
}

sub _get_map_reader {
    return Cpanel::DB::Map::Reader->new(
        engine => 'postgresql',
        cpuser => $Cpanel::user,
    );
}

sub Postgres_countdbs {
    _verify_role();

    print _countdbs();

    return;
}

sub _check_user_db_args {
    my ( $db, $user ) = @_;
    if ( grep { !length } $user, $db ) {
        return _invalid_arg_message( __FILE__, __LINE__, "_check_user_db_args" );
    }
    return { 'user' => $user, 'db' => $db };
}

sub Postgres_adduserdb {
    my @args = @_;

    _verify_role();

    _verify_feature();
    return _demomessage() if _democheck();

    my $args = _check_user_db_args(@args);
    return if !$args;

    Cpanel::AdminBin::Call::call(
        'Cpanel',
        'postgresql',
        'GRANT_ALL_PRIVILEGES_ON_DATABASE_TO_USER',
        $args->{'db'},
        $args->{'user'},
    );

    return;
}

sub Postgres_deluserdb {
    my @args = @_;

    _verify_role();

    _verify_feature();
    return _demomessage() if _democheck();
    my $args = _check_user_db_args(@args);
    return if !$args;

    Cpanel::AdminBin::Call::call(
        'Cpanel',
        'postgresql',
        'REVOKE_ALL_PRIVILEGES_ON_DATABASE_FROM_USER',
        $args->{'db'},
        $args->{'user'},
    );

    return;
}

sub Postgres_initcache {
    _verify_role();    # dies if role isn't available

    return 1 if $Cpanel::CPCACHE{'postgres'}{'cached'};

    my $result_hr;
    Capture::Tiny::capture { $result_hr = Cpanel::AdminBin::run_adminbin_with_status( 'postgres', 'DBCACHE' ); };
    die Cpanel::Exception->create_raw( $result_hr->{'error'} || $result_hr->{'statusmsg'} ) unless $result_hr->{'status'};
    my $ret = $result_hr->{'data'};

    $Cpanel::CPCACHE{'postgres'}{'cached'} = 1;
    foreach ( split( /\n/, $ret ) ) {
        s/\n//g;
        my ( $ttype, $item, $val, $ptv ) = split( /\t/, $_ );
        $ptv ||= 1;
        if ( !defined $val )  { $val  = 'undef'; }
        if ( !defined $item ) { $item = 'undef'; }
        $Cpanel::CPCACHE{'postgres'}{$ttype}{$item}{$val} = $ptv;
    }
    return 1;
}

sub api2_listdbs {
    my %OPTS = @_;

    my $cpanel_conf  = Cpanel::Config::LoadCpConf::loadcpconf();
    my $NEEDDISKUSED = exists $cpanel_conf->{'disk_usage_include_sqldbs'} ? $cpanel_conf->{'disk_usage_include_sqldbs'} : 1;

    my $result = try {
        Postgres_initcache();
    }
    catch {
        $Cpanel::CPERROR{'postgres'} = Cpanel::Exception::get_string($_);
        die $_;
    };
    return unless $result;

    my %DBS = ();
    if ($NEEDDISKUSED) {
        my @DBS = _listdbs();
        %DBS = _listdbswithspace();

        foreach my $db (@DBS) {
            if ( !exists $DBS{$db} ) {
                $DBS{$db} = 0;
            }
        }
    }
    else {
        my @DBS = _listdbs();
        %DBS = map { $_ => 0 } @DBS;
    }

    my $regex = $OPTS{'regex'};

    my @DBLIST;
    foreach my $db ( sort keys %DBS ) {
        next if !length $db;
        next if ( $regex && $db !~ m/$regex/i );

        my @USERS     = _listusersindb($db);
        my $usercount = ( $#USERS + 1 );
        my @userlist;
        foreach my $user (@USERS) {
            push( @userlist, { 'user' => $user, 'db' => $db } );
        }
        push @DBLIST,
          {
            'db'        => $db,
            'usercount' => $usercount,
            'size'      => $DBS{$db},
            'sizemeg'   => sprintf( '%.2f', $DBS{$db} / ( 1024 * 1024 ) ),
            'userlist'  => \@userlist,
          };
    }
    return \@DBLIST;
}

=head2 list_databases

Provides a list of all databases available to the current cPanel user.

=head3 ARGUMENTS

=over 1

=item $options - a hashref supporting the following options:

=over 1

=item usage - boolean 0 or 1 - if 1, include disk usage in result. Default is undef.

=item users - boolean 0 or 1 - if 1, include user list in result. Default is undef.

=back

=back

=head3 RETURNS

On success, the method returns an arrayref of hashrefs, one per database.

The hash for each database has the following format based on the options argument:

=over

=item database - string

The database name

=item users - string[]

Arrayref of databases user names that have some kind of access to the database.

=item disk_usage - integer

Disk usage in bytes

=back

=head3 EXCEPTIONS

=over

=item When you cannot connect to the Postgresql server.

=item When the cpanel account is out of disk space.

=item Possibly others.

=back

=cut

sub list_databases {

    my ($options) = @_;

    $options = {} if ref $options ne 'HASH';
    my %databases;
    my @result;

    if ( $options->{'usage'} ) {
        %databases = _listdbswithspace();
    }
    else {
        %databases = map { $_ => undef } _listdbs();
    }

    for my $name ( sort keys %databases ) {

        my $item = { 'database' => $name };
        $item->{'disk_usage'} = $databases{$name} * 1 if defined( $databases{$name} );

        if ( $options->{'users'} ) {
            my @users = _listusersindb($name);
            $item->{'users'} = [ sort @users ];
        }

        push @result, $item;
    }

    return \@result;
}

sub api2_listusersindb {
    my %CFG = @_;

    my $result = try {
        Postgres_initcache();
    }
    catch {
        $Cpanel::CPERROR{'postgres'} = Cpanel::Exception::get_string($_);
        die $_;
    };
    return unless $result;

    my @USERS = _listusersindb( $CFG{db} );
    my @RSD;
    foreach my $user (@USERS) {
        push( @RSD, { 'user' => $user, 'db' => $CFG{db} } );
    }

    return \@RSD;
}

sub api2_listusers {

    my $result = try {
        Postgres_initcache();
    }
    catch {
        $Cpanel::CPERROR{'postgres'} = Cpanel::Exception::get_string($_);
        die $_;
    };
    return unless $result;

    my @USERS = _listusers();
    my @DBS   = _listdbs();
    my %DBUSERS;
    foreach my $db (@DBS) {
        my (@USERS) = _listusersindb($db);
        foreach my $user (@USERS) {
            push( @{ $DBUSERS{$user} }, $db );
        }
    }
    my (@UL);
    foreach my $user ( sort @USERS ) {
        my @dblist;
        if ( ref( $DBUSERS{$user} ) eq 'ARRAY' ) {
            foreach my $db ( @{ $DBUSERS{$user} } ) {
                push( @dblist, { 'user' => $user, 'db' => $db } );
            }
        }
        push( @UL, { 'user' => $user, 'dblist' => \@dblist } );

    }
    return \@UL;
}

sub api2_userexists {
    my %OPTS = @_;

    my $user = $OPTS{'user'};

    my @RSD;
    my $result = Cpanel::AdminBin::adminrun( 'postgres', 'USEREXISTS', $user );
    return if $Cpanel::CPERROR{'postgres'};    # do not overwrite
    chomp($result);

    push @RSD, { userexists => $result };
    return @RSD;
}

my $postgres_client_role_allow_demo = {
    needs_role => 'PostgresClient',
    allow_demo => 1,
};

our %API = (
    listdbs        => $postgres_client_role_allow_demo,
    listusersindbs => $postgres_client_role_allow_demo,
    listusers      => $postgres_client_role_allow_demo,
    userexists     => {
        needs_role    => 'PostgresClient',
        needs_feature => 'postgres',
        allow_demo    => 1,
    },
);

sub api2 {
    my ($func) = @_;
    return { %{ $API{$func} } } if $API{$func};
    return;
}

sub _democheck {
    if ( exists $Cpanel::CPDATA{'DEMO'} && $Cpanel::CPDATA{'DEMO'} ) {
        return 1;
    }
    return;
}

sub _demomessage {
    $Cpanel::CPERROR{$Cpanel::context} = 'Sorry, this feature is disabled in demo mode.';
    return;
}

sub _invalid_arg_message {
    my $file = shift;
    my $line = shift;
    my $func = shift;
    $logger->warn("$file: $func: $line: Invalid argument");
    return;
}

sub server_up {
    return Cpanel::AdminBin::adminrun( 'postgres', "PING" );
}

1;
