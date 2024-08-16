package Whostmgr::API::1::DB;

# cpanel - Whostmgr/API/1/DB.pm                    Copyright 2022 cPanel, L.L.C.
#                                                           All rights reserved.
# copyright@cpanel.net                                         http://cpanel.net
# This code is subject to the cPanel license. Unauthorized copying is prohibited

use cPstrict;

use Try::Tiny;

use Cpanel::APICommon::Persona          ();
use Cpanel::DB::Map::Reader             ();
use Cpanel::DB::Prefix::Conf            ();
use Cpanel::Exception                   ();
use Cpanel::MysqlUtils::MyCnf::Optimize ();
use Cpanel::PasswdStrength::Check       ();
use Cpanel::Validate::DB::User          ();
use Whostmgr::API::1::Utils             ();
use Whostmgr::AcctInfo                  ();
use Whostmgr::DB                        ();
use Cpanel::LoadModule                  ();
use Whostmgr::ACLS                      ();

use constant NEEDS_ROLE => {
    list_database_users => { match => 'any', roles => [ 'MySQLClient', 'PostgresClient' ] },
    list_databases      => { match => 'any', roles => [ 'MySQLClient', 'PostgresClient' ] },

    list_mysql_databases_and_users => 'MySQLClient',
    rename_mysql_database          => 'MySQLClient',
    rename_mysql_user              => 'MySQLClient',
    set_mysql_password             => 'MySQLClient',
    get_database_optimizations     => 'MySQLClient',

    rename_postgresql_database => 'PostgresClient',
    rename_postgresql_user     => 'PostgresClient',
    set_postgresql_password    => 'PostgresClient',
};

my %ADMIN_CLASS = qw(
  mysql      Cpanel::Mysql
  postgresql Cpanel::PostgresAdmin
);

#Returns an arrayref of:  { cpuser => '..', name => '..' }
#
sub list_databases {
    my ( $formref, $metadata ) = @_;

    return _return_array( $metadata, Whostmgr::DB::list_databases() );
}

#Returns an arrayref of:  { cpuser => '..', name => '..' }
#
sub list_database_users {
    my ( $formref, $metadata ) = @_;

    return _return_array( $metadata, Whostmgr::DB::list_database_users() );
}

sub list_mysql_databases_and_users {
    my ( $args, $metadata ) = @_;

    _set_ok($metadata);
    my $output;
    try {
        my $cpanel_user = $args->{'user'};
        die Cpanel::Exception->create( 'The parameter “[_1]” is required.', ['user'] )
          if !$cpanel_user;

        Cpanel::LoadModule::load_perl_module('Cpanel::DB::Prefix');
        Cpanel::LoadModule::load_perl_module('Cpanel::MysqlUtils::Version');
        Cpanel::LoadModule::load_perl_module('Whostmgr::Authz');

        Whostmgr::Authz::verify_account_access($cpanel_user);

        $output->{'mysql_databases'} = Whostmgr::DB::list_mysql_databases_and_users($cpanel_user);
        $output->{'mysql_config'}    = {
            'use_db_prefix' => scalar Cpanel::DB::Prefix::Conf::use_prefix(),
            'prefix_length' => scalar Cpanel::DB::Prefix::get_prefix_length(),
            'mysql-version' => scalar Cpanel::MysqlUtils::Version::get_mysql_version_with_fallback_to_default(),
        };
    }
    catch {
        $metadata->{'result'} = 0;
        $metadata->{'reason'} = Cpanel::Exception::get_string( $_, 'no_id' );
    };
    return if !$metadata->{'result'};

    return $output;
}

#args:
#   oldname (required)
#   newname (required)
#   cpuser (optional; speeds up call)
sub rename_mysql_database {
    my ( $args, $metadata ) = @_;

    my $payload = _rename_database( $args, $metadata, 'mysql' );

    if ( @{ $payload->{'failures'} } ) {
        $metadata->{'warnings'} = $payload->{'failures_ar'};
    }

    return;
}

#args:
#   oldname (required)
#   newname (required)
#   cpuser (optional; speeds up call)
sub rename_postgresql_database {
    my ( $args, $metadata ) = @_;

    _rename_database( $args, $metadata, 'postgresql' );

    return;
}

#args:
#   oldname (required)
#   newname (required)
#   cpuser (optional; speeds up call)
sub rename_mysql_user {
    my ( $args, $metadata ) = @_;

    Cpanel::Validate::DB::User::verify_mysql_dbuser_name( $args->{newname} );

    my ($payload) = _rename_dbuser( $args, $metadata, 'mysql' );

    _set_ok($metadata);

    return;
}

#args:
#   oldname     (required)
#   newname     (required)
#   password    (required)
#   cpuser      (optional; speeds up call)
sub rename_postgresql_user {
    my ( $args, $metadata ) = @_;

    Cpanel::Validate::DB::User::verify_pgsql_dbuser_name( $args->{newname} );

    my $password = _get_required_arg( $args, 'password' );

    Cpanel::PasswdStrength::Check::verify_or_die( app => 'postgres', pw => $password );

    my ( undef, $admin_obj ) = _rename_dbuser( $args, $metadata, 'postgresql' );

    $admin_obj->set_password( $args->{'newname'}, $password );

    _set_ok($metadata);

    return;
}

#args:
#   user        (required) - the DB user
#   password    (required)
#   cpuser      (optional; speeds up call)
#
#The return is the "failures" array from Cpanel::Mysql::set_password.
#These represent any failures that came up while setting the password
#for the different user/host combinations.
#
#NOTE: The failures from this API call would be more sensibly reported as a
#special list called "failures" within the payload rather than as the actual
#return of the API call; however, limitations on WHM API v1 complicate that:
#specifically, we have two client libraries that will reduce:
#
#   { stuff => [..] }
#
#...to just the array.
#
#At one point a "payload_is_literal" flag was introduced to tell the client
#libraries not to do that reduction, but it was the general consensus among
#cPanel devs not to use the flag anymore in order to avoid (yet) another
#hacky-hack addition to an API that already has too much of it.
#
#The use case for a payload like { stuff => [..] } is rare enough that we can
#just deal with such cases as aberrations.
#
sub set_mysql_password ( $args, $metadata, $api_info_hr ) {

    my $user     = _get_required_arg( $args, 'user' );
    my $password = _get_required_arg( $args, 'password' );
    my $cpuser   = _get_cpuser_arg( $args, $metadata );

    my $err_obj = _get_child_account_error( $metadata, $api_info_hr, $cpuser );
    return $err_obj if $err_obj;

    my $ret = _set_password( $args, $metadata, 'mysql' );

    #NOTE: There is no usefulness to keeping the "failures" key since, by
    #definition, a WHM API v1 hashref that contains a single list gets
    #"reduced" to just the list on the client side.
    return { payload => $ret->{'failures'} };
}

#args:
#   user        (required) - the DB user
#   password    (required)
#   cpuser      (optional; speeds up call)
sub set_postgresql_password ( $args, $metadata, $api_info_hr ) {

    my $user     = _get_required_arg( $args, 'user' );
    my $password = _get_required_arg( $args, 'password' );
    my $cpuser   = _get_cpuser_arg( $args, $metadata );

    my $err_obj = _get_child_account_error( $metadata, $api_info_hr, $cpuser );
    return $err_obj if $err_obj;

    _set_password( $args, $metadata, 'postgresql' );

    return undef;
}

sub get_database_optimizations ( $args, $metadata, @ ) {
    my $settings = Cpanel::MysqlUtils::MyCnf::Optimize::get_optimizations();
    return _return_array( $metadata, $settings );
}

sub _get_child_account_error ( $metadata, $api_info_hr, $username ) {
    my $err_obj;

    ( my $str, $err_obj ) = Cpanel::APICommon::Persona::get_whm_expect_parent_error_pieces( $api_info_hr->{'persona'}, $username );

    if ($str) {
        $metadata->set_not_ok($str);
    }

    return $err_obj;
}

sub _return_array {
    my ( $metadata, $payload_ar ) = @_;

    _set_ok($metadata);

    return { payload => $payload_ar };
}

sub _get_owned_accounts {

    #TODO: Remove this when/if WHM extends DB listing to non-root.
    die "Only root resellers can do this!" if !Whostmgr::ACLS::hasroot();

    my $reseller = Whostmgr::ACLS::hasroot() ? undef : $ENV{'REMOTE_USER'};
    return Whostmgr::AcctInfo::get_accounts($reseller);
}

sub _get_item_owner {
    my ( $engine, $finder_func, $name, $cpuser ) = @_;

    my $owned_accts_hr = length($cpuser) ? { $cpuser => undef } : _get_owned_accounts();

    for my $cpuser ( keys %$owned_accts_hr ) {
        my $map = Cpanel::DB::Map::Reader->new( cpuser => $cpuser, engine => $engine );
        return $cpuser if $map->$finder_func($name);
    }

    return;
}

sub _get_rename_args {
    my ( $args, $metadata ) = @_;

    my $oldname = _get_required_arg( $args, 'oldname' );
    my $newname = _get_required_arg( $args, 'newname' );

    #"courtesy" validation. The admin backend will still bug out without this,
    #but the error message is "scarier".
    if ( $newname eq $oldname ) {
        die Cpanel::Exception::create( 'InvalidParameter', 'The “[_1]” and “[_2]” parameters cannot be the same value.', [qw(oldname newname)] );
    }

    my $cpuser = _get_cpuser_arg( $args, $metadata );

    return ( $oldname, $newname, $cpuser );
}

sub _get_cpuser_arg {
    my ($args) = @_;

    my $cpuser = $args->{'cpuser'};

    my $given_cpuser = $cpuser;
    if ( length $given_cpuser ) {
        if ( !Whostmgr::AcctInfo::hasauthority( $ENV{'REMOTE_USER'}, $cpuser ) ) {
            die Cpanel::Exception::create( 'UserNotFound', [ name => $cpuser ] );
        }
    }

    return $cpuser;
}

sub _set_password {
    my ( $args, $metadata, $engine ) = @_;

    my $user     = _get_required_arg( $args, 'user' );
    my $password = _get_required_arg( $args, 'password' );
    my $cpuser   = _get_cpuser_arg( $args, $metadata );

    Cpanel::LoadModule::load_perl_module("$ADMIN_CLASS{$engine}");
    my $admin_obj = $ADMIN_CLASS{$engine}->new( { cpuser => $cpuser } );
    my $ret       = $admin_obj->set_password( $user, $password );

    _set_ok($metadata);

    return $ret;
}

sub _rename_database {
    my ( $args, $metadata, $engine ) = @_;

    my ( $oldname, $newname, $cpuser_in ) = _get_rename_args( $args, $metadata );

    my $cpuser = _get_item_owner( $engine, 'database_exists', $oldname, $cpuser_in );

    if ( !length $cpuser ) {
        die Cpanel::Exception::create( 'Database::DatabaseNotFound', [ name => $oldname, cpuser => $cpuser_in, engine => $engine ] );
    }

    Cpanel::LoadModule::load_perl_module("$ADMIN_CLASS{$engine}");
    my $admin_class = $ADMIN_CLASS{$engine};
    my $admin_obj   = $admin_class->new( { cpuser => $cpuser } );

    my $payload = $admin_obj->rename_database( $oldname => $newname );

    _set_ok($metadata);

    return $payload;
}

sub _rename_dbuser {
    my ( $args, $metadata, $engine ) = @_;

    my ( $oldname, $newname, $cpuser_in ) = _get_rename_args( $args, $metadata );

    my $cpuser = _get_item_owner( $engine, 'dbuser_exists', $oldname, $cpuser_in );

    if ( !length $cpuser ) {
        die Cpanel::Exception::create( 'Database::UserNotFound', [ name => $oldname, cpuser => $cpuser_in, engine => $engine ] );
    }

    Cpanel::LoadModule::load_perl_module("$ADMIN_CLASS{$engine}");
    my $admin_class = $ADMIN_CLASS{$engine};
    my $admin_obj   = $admin_class->new( { cpuser => $cpuser } );

    my $payload = $admin_obj->rename_dbuser( $oldname => $newname );

    #Don't _set_ok here since PostgreSQL still needs to set a password.

    return ( $payload, $admin_obj );
}

*_set_ok = \&Whostmgr::API::1::Utils::set_metadata_ok;

*_get_required_arg = \&Whostmgr::API::1::Utils::get_length_required_argument;

1;
