package Cpanel::MysqlFE;

# cpanel - Cpanel/MysqlFE.pm                       Copyright 2022 cPanel, L.L.C.
#                                                           All rights reserved.
# copyright@cpanel.net                                         http://cpanel.net
# This code is subject to the cPanel license. Unauthorized copying is prohibited

use strict;
use warnings;

use Cpanel::AdminBin                 ();
use Cpanel                           ();
use Cpanel::AdminBin::Call           ();
use Cpanel::API                      ();
use Cpanel::Security::Authz          ();
use Cpanel::DB                       ();
use Cpanel::DB::Map::Reader          ();
use Cpanel::DB::Utils                ();
use Cpanel::Hostname                 ();
use Cpanel::LoadFile                 ();
use Cpanel::MysqlFE::DB              ();
use Cpanel::MysqlUtils::MyCnf::Basic ();

our $VERSION = 1.7;

*_countdbs         = \&Cpanel::MysqlFE::DB::countdbs;
*_listdbswithspace = \&Cpanel::MysqlFE::DB::listdbswithspace;
*_mysql_is_remote  = \&Cpanel::MysqlFE::DB::_mysql_is_remote;

sub _verify_feature {
    Cpanel::Security::Authz::verify_user_has_feature( $Cpanel::user, 'mysql' );
}

sub MysqlFE_init {
    $Cpanel::NEEDSREMOTEPASS{'MysqlFE'} = 1;
    return 1;
}

sub _listusersindb {
    my $db = shift;
    my @USERS;
    if ( $Cpanel::CPCACHE{'mysql'}{'cached'} ) {
        if ( $Cpanel::CPCACHE{'mysql'}{'DBUSER'}{$db} ) {
            foreach my $user ( sort keys %{ $Cpanel::CPCACHE{'mysql'}{'DBUSER'}{$db} } ) {
                push @USERS, $user;
            }
        }
    }
    else {
        my $map = Cpanel::DB::Map::Reader->new( cpuser => $Cpanel::user, engine => 'mysql' );
        push @USERS, $map->get_dbusers_for_database($db);

        %{ $Cpanel::CPCACHE{'mysql'}{'DBUSER'}{$db} } = map { $_ => 1 } @USERS;
    }
    return @USERS;
}

sub _listusersinalldbs {
    my (%DBUSERS);
    if ( $Cpanel::CPCACHE{'mysql'}{'cached'} ) {
        foreach my $db ( keys %{ $Cpanel::CPCACHE{'mysql'}{'DBUSER'} } ) {
            if ( $Cpanel::CPCACHE{'mysql'}{'DBUSER'}{$db} ) {
                foreach my $user ( sort keys %{ $Cpanel::CPCACHE{'mysql'}{'DBUSER'}{$db} } ) {
                    push @{ $DBUSERS{$db} }, $user;
                }
            }
        }
    }
    else {
        my $map = Cpanel::DB::Map::Reader->new( cpuser => $Cpanel::user, engine => 'mysql' );
        %DBUSERS = %{ $map->get_dbusers_for_all_databases() };

        foreach my $db ( keys %DBUSERS ) {
            %{ $Cpanel::CPCACHE{'mysql'}{'DBUSER'}{$db} } = map { $_ => 1 } @{ $DBUSERS{$db} };
        }
    }
    return %DBUSERS;
}

sub _listhosts {
    my $hostname = Cpanel::Hostname::gethostname();
    my (@HOSTS);
    if ( $Cpanel::CPCACHE{'mysql'}{'cached'} ) {
        if ( $Cpanel::CPCACHE{'mysql'}{'HOST'} ) {
            foreach my $host ( sort keys %{ $Cpanel::CPCACHE{'mysql'}{'HOST'} } ) {
                push @HOSTS, $host;
            }
        }
    }
    else {
        @HOSTS = split( /\n/, Cpanel::AdminBin::adminrun( 'cpmysql', 'LISTHOSTS' ) );
    }
    @HOSTS = grep( !/^(localhost|\Q${hostname}\E|\Q$Cpanel::CPDATA{'DNS'}\E)$/, @HOSTS );
    return @HOSTS;
}

#Older, less-preferred
sub api2_listhosts {

    require Cpanel::Encoder::URI;

    my @HOSTS = _listhosts();
    my @RSD;

    foreach my $host ( sort @HOSTS ) {
        my $uri_host = Cpanel::Encoder::URI::uri_encode_str($host);
        push @RSD, { 'host' => $host, 'uri_host' => $uri_host };
    }
    return @RSD;
}

#Newer, preferred
sub api2_gethosts {
    return [ sort( _listhosts() ) ];
}

sub _listusers {
    my @USERS;
    if ( $Cpanel::CPCACHE{'mysql'}{'cached'} ) {
        if ( $Cpanel::CPCACHE{'mysql'}{'USER'} ) {
            foreach my $user ( sort keys %{ $Cpanel::CPCACHE{'mysql'}{'USER'} } ) {
                push @USERS, $user;
            }
        }
    }
    else {
        my $map = Cpanel::DB::Map::Reader->new( cpuser => $Cpanel::user, engine => 'mysql' );
        @USERS = $map->get_dbusers();

        # never display the root user in the frontend
        %{ $Cpanel::CPCACHE{'mysql'}{'USER'} } = map { $_ => 1 } grep { $_ ne 'root' } @USERS;
    }

    return @USERS;
}

sub _listdbs {
    my %DBS = Cpanel::MysqlFE::DB::listdbs();
    return keys %DBS;
}

sub _cacheddiskusage {
    require Cpanel::UserDatastore;

    my $usage = Cpanel::LoadFile::loadfile( Cpanel::UserDatastore::get_path($Cpanel::user) . '/mysql-disk-usage' ) || 0;
    return int $usage;
}

sub _diskusage {
    my %DBSPACE = _listdbswithspace();
    my $total   = 0;
    foreach my $db ( keys %DBSPACE ) {
        $total += ( $DBSPACE{$db} // 0 );
    }
    return $total;
}

sub api2_getalldbsinfo {

    my $remote;

    if ( exists $Cpanel::CPCACHE{'mysql'} && $Cpanel::CPCACHE{'mysql'}{'ISREMOTE'} ) {
        my @VALS = keys %{ $Cpanel::CPCACHE{'mysql'}{'ISREMOTE'} };
        $remote = shift @VALS;
    }
    if ( !defined $remote ) {
        $Cpanel::CPCACHE{'mysql'}{'ISREMOTE'}{ $remote = _mysql_is_remote() } = undef;
    }

    my $needdiskused = exists $Cpanel::CONF{'disk_usage_include_sqldbs'} ? $Cpanel::CONF{'disk_usage_include_sqldbs'} : 1;

    my %DBS;
    if ( !$needdiskused ) {
        my @DBS = _listdbs();
        %DBS = map { $_ => 0 } @DBS;
    }
    else {
        %DBS = _listdbswithspace();
    }

    my %USERDBS = _listusersinalldbs();

    my @dbs = map { { db => $_, size => $DBS{$_}, dbusers => $USERDBS{$_} || [], } } sort keys %DBS;

    return \@dbs;
}

sub api2_listdbs {
    my %OPTS = @_;

    unless ( exists $Cpanel::CPCACHE{'mysql'} ) {
        Cpanel::MysqlFE::DB::_initcache();
    }

    my $regex = $OPTS{'regex'};

    my $remote;

    if ( exists $Cpanel::CPCACHE{'mysql'} && $Cpanel::CPCACHE{'mysql'}{'ISREMOTE'} ) {
        my @VALS = keys %{ $Cpanel::CPCACHE{'mysql'}{'ISREMOTE'} };
        $remote = shift @VALS;
    }
    if ( !defined $remote ) {
        $Cpanel::CPCACHE{'mysql'}{'ISREMOTE'}{ $remote = _mysql_is_remote() } = undef;
    }

    my $needdiskused = exists $Cpanel::CONF{'disk_usage_include_sqldbs'} ? $Cpanel::CONF{'disk_usage_include_sqldbs'} : 1;

    my %DBS;
    if ( !$needdiskused ) {
        my @DBS = _listdbs();
        %DBS = map { $_ => 0 } @DBS;
    }
    else {
        %DBS = _listdbswithspace();
    }

    my %USERDBS = _listusersinalldbs();

    my @DBLIST;
    foreach my $db ( sort keys %DBS ) {
        if ( defined $regex && $regex ne '' && $db !~ m/$regex/i ) { next; }

        my $usercount = $#{ $USERDBS{$db} } + 1;
        my @userlist;
        foreach my $user ( @{ $USERDBS{$db} } ) {
            push( @userlist, { 'user' => $user, 'db' => $db } );
        }

        push(
            @DBLIST,
            {
                'db'        => $db,
                'usercount' => $usercount,
                'size'      => $DBS{$db},
                'sizemeg'   => sprintf( "%.2f", ( $DBS{$db} || 0 ) / ( 1024 * 1024 ) ),
                'userlist'  => \@userlist
            }
        );
    }
    return @DBLIST;
}

sub _fetchprivs {
    my ( $user, $db ) = @_;

    $user = Cpanel::DB::add_prefix_if_name_and_server_need($user);

    my @PRIVS = split( /\s*,\s*/, Cpanel::AdminBin::adminrun( 'cpmysql', 'LISTPRIVS', $user, 'localhost', $db ) );
    return @PRIVS;
}

sub api2_getmysqlprivileges {
    return Cpanel::AdminBin::Call::call( 'Cpanel', 'mysql', 'GRANTABLE_PRIVILEGES' );
}

sub api2_getmysqlserverprivileges {
    my %OPTS         = @_;
    my $admin_output = Cpanel::AdminBin::adminrun( 'cpmysql', 'LISTMYSQLSERVERPRIVS', $OPTS{'user'}, 'localhost', $OPTS{'include_admin'} ? 1 : 0 );
    my @privs;
    for my $line ( split m{\n+}, $admin_output ) {
        my %new_priv;
        @new_priv{ 'privilege', 'description' } = split( m{,}, $line, 2 );
        push @privs, \%new_priv;
    }
    return \@privs;
}

#Old, less-preferred call
sub api2_userdbprivs {
    my %CFG = @_;

    my @PRIVS = _fetchprivs( $CFG{'user'}, $CFG{'db'} );

    my %PRIVLIST = map { tr{ }{}d; $_ => 1 } @PRIVS;

    my @RSD;
    push @RSD, \%PRIVLIST;
    return @RSD;
}

#Newer, cleaner call
sub api2_getdbuserprivileges {
    my %CFG = @_;
    return [ sort( _fetchprivs( @CFG{ 'dbuser', 'db' } ) ) ];
}

#Old, less-preferred call
sub api2_listusersindb {
    my %CFG   = @_;
    my @USERS = _listusersindb( $CFG{'db'} );
    my @RSD;
    foreach my $user (@USERS) {
        push @RSD, { 'user' => $user, 'db' => $CFG{'db'} };
    }
    return @RSD;
}

#Newer, cleaner call
sub api2_getdbusers {
    my %CFG = @_;

    if ( defined $CFG{'db'} ) {
        return [ sort( _listusersindb( $CFG{'db'} ) ) ];
    }
    else {
        return [ sort( _listusers() ) ];
    }
}

#Old, less-preferred call
sub api2_listusers {

    my @USERS   = _listusers();
    my %USERDBS = _listusersinalldbs();
    my %DBUSERS;
    foreach my $db ( sort keys %USERDBS ) {
        foreach my $user ( @{ $USERDBS{$db} } ) {
            push( @{ $DBUSERS{$user} }, $db );
        }
    }
    my @UL;
    my $dbowner = Cpanel::DB::Utils::username_to_dbowner($Cpanel::user);
    foreach my $user ( sort @USERS ) {
        my @dblist;
        if ( ref( $DBUSERS{$user} ) eq 'ARRAY' ) {
            foreach my $db ( @{ $DBUSERS{$user} } ) {
                push( @dblist, { 'user' => $user, 'db' => $db } );
            }
        }
        my $shortuser = $user;
        $shortuser =~ s/^\Q$dbowner\E_//g;
        push @UL, { 'shortuser' => $shortuser, 'user' => $user, 'dblist' => \@dblist };

    }
    return @UL;
}

#Newer, cleaner call
sub api2_getalldbusersanddbs {

    my @USERS   = _listusers();
    my %USERDBS = _listusersinalldbs();
    my %DBUSERS;
    foreach my $db ( sort keys %USERDBS ) {
        foreach my $user ( @{ $USERDBS{$db} } ) {
            push( @{ $DBUSERS{$user} }, $db );
        }
    }
    my @UL = map { { dbuser => $_, dbs => $DBUSERS{$_} || [] } } sort @USERS;

    return \@UL;
}

sub api2_listdbsbackup {
    my @DBS = _listdbs();
    return [ map { { db => $_ } } sort @DBS ];
}

sub api2_dbuserexists {
    my %OPTS = @_;

    my $rdr = Cpanel::DB::Map::Reader->new(
        cpuser => $Cpanel::user,
        engine => 'mysql',
    );

    return $rdr->dbuser_exists( $OPTS{'dbuser'} ) ? 1 : 0;
}

#XXX: Unused in our own code. SDK recommends UAPI revoke_access_to_database.
#NOTE: This DOES add a DB prefix.
sub api2_revokedbuserprivileges {
    my %OPTS = @_;

    return _simple_api2_db_operation( \&Cpanel::MysqlFE::DB::deluserdb, @OPTS{ 'db', 'dbuser' } );
}

sub api2_deauthorizehost {
    my %OPTS   = @_;
    my $result = Cpanel::API::wrap_deprecated( 'Mysql', 'delete_host', { 'host' => $OPTS{'host'} } );
    if ( $result->status() ) {
        return 1;
    }
    else {
        # 'No such file or directory' preserves old behavior, no matter how strange.
        $Cpanel::CPERROR{ _context() } = 'No such file or directory';
        die $result->errors_as_string() . "\n";
    }
}

#NOTE: This does NOT add a DB prefix.
sub api2_deletedbuser {
    my %OPTS   = @_;
    my $result = Cpanel::API::wrap_deprecated( 'Mysql', 'delete_user', { 'name' => $OPTS{'dbuser'}, } );
    $Cpanel::CPERROR{ _context() } = $result->errors_as_string();
    die $Cpanel::CPERROR{ _context() } if $Cpanel::CPERROR{ _context() };
    return $result->status() ? 1 : ();
}

#NOTE: This does NOT add a DB prefix.
sub api2_deletedb {
    my %OPTS   = @_;
    my $result = Cpanel::API::wrap_deprecated( 'Mysql', 'delete_database', { 'name' => $OPTS{'db'}, } );
    $Cpanel::CPERROR{ _context() } = $result->errors_as_string();
    die $Cpanel::CPERROR{ _context() } if $Cpanel::CPERROR{ _context() };
    return $result->status() ? 1 : ();
}

my %_api1_privilege_mappings = (
    'ALL PRIVILEGES'          => 'all',
    'CREATE ROUTINE'          => 'routine',
    'CREATE TEMPORARY TABLES' => 'temporary',
    'CREATE VIEW'             => 'createview',
    'LOCK TABLES'             => 'lock',
    'SHOW VIEW'               => 'showview',
);

sub api2_setdbuserprivileges {
    my %OPTS = @_;

    my $privs = $OPTS{'privileges'};

    if ($privs) {
        my @separated_privs = split m{,}, $privs;
        my @legacy_privs    = map { $_api1_privilege_mappings{$_} || lc $_ } @separated_privs;
        $privs = join q{ }, @legacy_privs;
    }

    return _simple_api2_db_operation( \&Cpanel::MysqlFE::DB::adduserdb, @OPTS{ 'db', 'dbuser' }, $privs );
}

sub api2_createdbuser {
    my %OPTS   = @_;
    my $result = Cpanel::API::wrap_deprecated( 'Mysql', 'create_user', { 'name' => $OPTS{'dbuser'}, 'password' => $OPTS{'password'}, } );
    $Cpanel::CPERROR{ _context() } = $result->errors_as_string();
    die $Cpanel::CPERROR{ _context() } if $Cpanel::CPERROR{ _context() };
    return $result->status() ? 1 : ();
}

sub api2_authorizehost {
    my %OPTS   = @_;
    my $result = Cpanel::API::wrap_deprecated( 'Mysql', 'add_host', { 'host' => $OPTS{'host'} } );
    if ( $result->status() ) {
        return 1;
    }
    else {
        # 'No such file or directory' preserves old behavior, no matter how strange.
        $Cpanel::CPERROR{ _context() } = 'No such file or directory';
        die $result->errors_as_string() . "\n";
    }
}

sub api2_createdb {
    my %OPTS   = @_;
    my $result = Cpanel::API::wrap_deprecated( 'Mysql', 'create_database', { 'name' => $OPTS{'db'} } );
    $Cpanel::CPERROR{ _context() } = $result->errors_as_string();
    die $Cpanel::CPERROR{ _context() } if $Cpanel::CPERROR{ _context() };
    return $result->status() ? 1 : ();
}

sub api2_changedbuserpassword {
    my %OPTS = @_;

    return _simple_api2_db_operation( \&Cpanel::MysqlFE::DB::changeuserpasswd, @OPTS{ 'dbuser', 'password' } );
}

sub api2_has_mycnf_for_cpuser {
    my $mydbuser = Cpanel::MysqlUtils::MyCnf::Basic::getmydbuser();

    if ( $mydbuser && $mydbuser eq $Cpanel::user ) {
        $Cpanel::CPVAR{'has_mycnf_for_cpuser'} = 1;
        return [ { 'has_mycnf_for_cpuser' => 1 } ];
    }
    else {
        $Cpanel::CPVAR{'has_mycnf_for_cpuser'} = 0;
        return [ { 'has_mycnf_for_cpuser' => 0 } ];
    }
}

sub _simple_api2_db_operation {
    my ( $coderef, @args ) = @_;

    return _demomessage() if _democheck();

    my $reason = $coderef->(@args);
    chomp $reason if defined $reason;

    if ( $Cpanel::CPERROR{ _context() } || $Cpanel::CPERROR{'mysql'} ) {
        $Cpanel::CPERROR{ _context() } ||= $Cpanel::CPERROR{'mysql'} || 'Unknown error';
        return undef;
    }

    # case CPANEL-4218: For legacy compat a reason of '1' is considered success
    elsif ( length $reason && $reason ne '1' ) {
        $Cpanel::CPERROR{ _context() } = $reason;
        return undef;
    }

    return 1;
}

sub _democheck {
    if ( exists $Cpanel::CPDATA{'DEMO'} && $Cpanel::CPDATA{'DEMO'} ) {
        return 1;
    }
    return;
}

sub _demomessage {
    $Cpanel::CPERROR{ _context() } = 'Sorry, this feature is disabled in demo mode.';
    return;
}

my $mysql_feature_allow_demo              = { needs_feature => 'mysql', allow_demo => 1 };
my $mysql_feature_engine_array_allow_demo = { needs_feature => 'mysql', engine     => 'array', allow_demo => 1 };

my $allow_demo              = { allow_demo => 1 };
my $engine_array_allow_demo = { engine     => 'array', allow_demo => 1 };
my $engine_array_deny_demo  = { engine     => 'array' };

our %API = (
    'authorizehost'            => $engine_array_allow_demo,                 # Wrapped Cpanel::API::Mysql::add_host
    'changedbuserpassword'     => $engine_array_deny_demo,
    'createdb'                 => $engine_array_allow_demo,                 # Wrapped Cpanel::API::Mysql::create_database
    'createdbuser'             => $engine_array_allow_demo,                 # Wrapped Cpanel::API::Mysql::create_user
    'dbuserexists'             => $mysql_feature_engine_array_allow_demo,
    'deauthorizehost'          => $engine_array_allow_demo,                 # Wrapped Cpanel::API::Mysql::delete_host
    'deletedb'                 => $engine_array_allow_demo,                 # Wrapped Cpanel::API::Mysql::delete_database
    'deletedbuser'             => $engine_array_allow_demo,                 # Wrapped Cpanel::API::Mysql::delete_user
    'getalldbsinfo'            => $mysql_feature_allow_demo,
    'getalldbusersanddbs'      => $mysql_feature_allow_demo,
    'getdbuserprivileges'      => $mysql_feature_engine_array_allow_demo,
    'getdbusers'               => $mysql_feature_engine_array_allow_demo,
    'gethosts'                 => $mysql_feature_engine_array_allow_demo,
    'getmysqlprivileges'       => $engine_array_allow_demo,
    'getmysqlserverprivileges' => $allow_demo,
    'has_mycnf_for_cpuser'     => $allow_demo,
    'listdbs'                  => $mysql_feature_allow_demo,
    'listdbsbackup'            => $mysql_feature_allow_demo,
    'listhosts'                => $mysql_feature_allow_demo,
    'listusers'                => $mysql_feature_allow_demo,
    'listusersindb'            => $mysql_feature_allow_demo,
    'revokedbuserprivileges'   => $engine_array_deny_demo,
    'userdbprivs'              => $mysql_feature_allow_demo,
    'setdbuserprivileges'      => $engine_array_deny_demo,
);

$_->{'needs_role'} = 'MySQLClient' for values %API;

sub api2 {
    my ($func) = @_;

    $ENV{'REMOTE_PASSWORD'}   = $Cpanel::userpass;       #TEMP_SESSION_SAFE
    $ENV{'SESSION_TEMP_PASS'} = $Cpanel::tempuserpass;

    return { %{ $API{$func} } } if $API{$func};
    return;
}

sub _context {
    return $Cpanel::context || 'mysqlfe';
}

1;
