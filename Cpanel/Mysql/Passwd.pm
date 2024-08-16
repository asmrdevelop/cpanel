package Cpanel::Mysql::Passwd;

# cpanel - Cpanel/Mysql/Passwd.pm                  Copyright 2022 cPanel, L.L.C.
#                                                           All rights reserved.
# copyright@cpanel.net                                         http://cpanel.net
# This code is subject to the cPanel license. Unauthorized copying is prohibited

use cPstrict;

=encoding utf-8

=head1 NAME

Cpanel::Mysql::Passwd

=head1 DESCRIPTION

A subset of Cpanel::Mysql functionality needed by
scripts/suspendmysqlusers and scripts/unsuspendmysqlusers

=head1 SYNOPSIS

    use Cpanel::Mysql::Passwd ();

    my $ob = Cpanel::Mysql::Passwd->new( { 'cpconf' => $cpconf, 'cpuser' => $user, 'ERRORS_TO_STDOUT' => 1 } );

=head1 FUNCTIONS

=cut

use parent qw(
  Cpanel::Mysql::Basic
);

use Cpanel::Context                   ();
use Cpanel::Mysql::Hosts              ();
use Cpanel::LocaleString              ();
use Cpanel::MysqlUtils::Grants        ();
use Cpanel::MysqlUtils::Grants::Users ();
use Cpanel::MysqlUtils::MyCnf::Basic  ();
use Cpanel::NAT                       ();
use Cpanel::Validate::DB::User        ();

use Try::Tiny;

=head2 passwduser_hash()

Sets a database user password

=head3 Arguments

=over

=item * DB user name (should have prefix if needed)

=item * password

=item * whether this is a change of password (1) or a DB user creation (0)

=back

=head3 Returns

Returns 1 for success or 0 plus an error message

=cut

sub passwduser_hash {
    my ( $self, $dbuser, $dbpass, $changepasswd ) = @_;

    local $self->{pwstring} = q<>;

    return $self->passwduser( $dbuser, $dbpass, $changepasswd );
}

=head2 passwduser()

CREATEs or ALTERs a MySQL database user and sets a password to IDENTIFY it BY.
Subsequently sets GRANTs for the relevant user@host combinations.

NOTE: DO NOT consider using Cpanel::MySQL::set_password for setting passwords
in new code, as that method uses a deprecated method to set the user's
passwords.

NOTE: This does NOT apply a database prefix! (Should it??)

=head3 Arguments

=over

=item * DB user name (should have prefix if needed)

=item * password

=item * whether this is a change of password (1) or a DB user creation (0)

=back

=head3 Returns

Returns 1 for success or 0 plus an error message

=cut

sub passwduser {
    my ( $self, $dbuser, $dbpass, $changepasswd ) = @_;

    local $@;
    if ( !eval { Cpanel::Validate::DB::User::verify_mysql_dbuser_name($dbuser) } ) {
        my $err = $@;
        return ( 0, $err->to_string() );
    }

    $changepasswd ||= 0;

    my $map = $self->_get_map();
    if ($changepasswd) {
        if ( $self->{'cpuser'} ne 'root' && !$map->{'map'}->user_owns_dbuser( $self->{'cpuser'}, $dbuser ) ) {
            return ( 0, $self->_log_error_and_output_return( Cpanel::LocaleString->new( "The user “[_1]” may not change the password because you do not own “[_2]”.", $self->{'cpuser'}, $dbuser ) ) );
        }
        else {
            $self->{'logger'}->info( "Changing password for MySQL virtual user $dbuser as system user " . $self->{'cpuser'} . "..." );
        }
    }
    elsif ( $map->{'map'}->dbuser_exists($dbuser) ) {
        return ( 0, $self->_log_error_and_output_return( Cpanel::LocaleString->new( "The user “[_1]” may not create a database user named “[_2]” because a user with that name already exists.", $self->{'cpuser'}, $dbuser ) ) );
    }

    $self->{'logger'}->info( "Creating MySQL virtual user $dbuser for user " . $self->{'cpuser'} );

    my @HOSTS = $self->_get_host_list();

    #Just create one object and change its properties to get each GRANT statement.
    my $grant_obj = Cpanel::MysqlUtils::Grants->new();
    $grant_obj->quoted_db_obj('*');    #"quoted" so we don't work on the `*` table.
    $grant_obj->quoted_db_name('*');
    $grant_obj->db_privs('USAGE');

    # 1) Retrieve the authentication info file if available,
    # 2) If available, get hash plugin from it, otherwise default to mysql_native_password, OR try to devine it from the hash itself
    # 3) Look at current mysql server version and generate CREATE USER followed by GRANT for mysql 8+, use old behavior for previous versions

    my $power_word = $changepasswd ? 'ALTER' : 'CREATE';

    # Add auth_plugin to @users
    my @users           = map { { user => $dbuser, host => $_, ( $self->{'pwstring'} ? 'password' : 'hashed_password' ) => $dbpass }, } @HOSTS;
    my $usage_grant_req = $grant_obj->to_string_for_users_manage( $power_word, @users );
    $usage_grant_req .= $grant_obj->to_string_for_users(@users);
    local $@;

    # Case 110573:Trying to catch if there is an error creating the user.
    # This code works hard to suppress the error, the only way I can catch this
    # is to see if the returned value is an undef.

    my $xret = 0;

    # Case HB-5525: since these calls are made from multiple places during restorepkg, attempt each grant one at a time,
    # so failures due to existing user@hosts don't tank the rest of them
    my @grant_lines = split( /\n/, $usage_grant_req );
    foreach my $grant_line (@grant_lines) {
        $xret = $self->sendmysql( $grant_line . " /* passwduser */ " ) or do {
            $self->{'logger'}->warn("GRANT statement “$grant_line” failed: $@");
        };
    }

    if ( defined $xret ) {

        #i.e., if any of the user@hosts aren't already in the map, add them.
        if ( !$changepasswd ) {
            $map->{'owner'}->add_dbuser( { dbuser => $dbuser, server => Cpanel::MysqlUtils::MyCnf::Basic::get_server() } );
            $self->_save_map_hash($map);
        }

        $self->queue_dbstoregrants();
    }
    else {
        $self->{'logger'}->info( "ERROR in Mysql query :" . $self->{'sendmysql_err'} . ":" );
        return ( 0, "Error from MySQL query :" . $self->{'sendmysql_err'} . ":" );
    }

    return 1;
}

#For parity with PostgresAdmin.pm
*raw_passwduser = \&passwduser;

#XXX: Needs better error reporting
my $_host_that_mysql_sees;

=head2 _get_host_list_without_user_added_hosts()

This include all the hosts that a mysql user needs access
from.  It will NOT include the remote mysql hosts added in cpanel.

=head3 Arguments

None.

=head3 Returns

Returns a list of hosts.

=cut

sub _get_host_list_without_user_added_hosts {
    my ($self) = @_;

    Cpanel::Context::must_be_list();

    my $hosts_hr = Cpanel::Mysql::Hosts::get_hosts_lookup();

    if ( $self->is_remote_mysql() ) {

        #Account for cases where the MySQL box is behind NAT.
        $_host_that_mysql_sees ||= $self->_query_single_value(q<SELECT SUBSTRING_INDEX( CURRENT_USER(), '@', -1 )>);
        $hosts_hr->{$_host_that_mysql_sees} = undef;
    }

    return keys %$hosts_hr;
}

=head2 _get_user_added_hosts()

This is a list remote mysql hosts
added in cpanel. It will also include hosts
that have previously been added.

=head3 Arguments

None.

=head3 Returns

Returns an array or array reference of hosts

=cut

sub _get_user_added_hosts {
    my ($self) = @_;

    # Now add the user added hosts
    my %HOSTLIST = map { $_ => 1 } ( $self->listhosts() );
    $self->_add_public_ips_to_hr( \%HOSTLIST );

    return wantarray ? keys %HOSTLIST : [ keys %HOSTLIST ];
}

=head2 _get_host_list()

This include all the hosts that a mysql user needs access
from.  It will include the remote mysql hosts added in cpanel.

=head3 Arguments

None.

=head3 Returns

Returns an array or array reference of hosts

=cut

sub _get_host_list {
    my ($self) = @_;

    my %HOSTLIST = map { $_ => 1 } ( $self->_get_host_list_without_user_added_hosts(), $self->_get_user_added_hosts() );

    return wantarray ? keys %HOSTLIST : [ keys %HOSTLIST ];
}

=head2 getmysqlalthost()

Get the configured MySQL host name or localhost if none.

=head3 Arguments

None.

=head3 Returns

Returns a hostname

=cut

sub getmysqlalthost {
    my $althost = Cpanel::MysqlUtils::MyCnf::Basic::getmydbhost('root') || 'localhost';
    return $althost;
}

sub _add_public_ips_to_hr {
    my ( $self, $hr ) = @_;
    return if !Cpanel::NAT::is_nat();

    # If we are in NAT mode we should always include
    # the mainip, and the public ip for it.
    foreach my $entry ( keys %$hr ) {
        my $public_ip = Cpanel::NAT::get_public_ip($entry) or next;
        $hr->{$public_ip} = 1;
    }
    return;
}

our $_is_remote_mysql;

=head2 is_remote_mysql()

Tests if is remote MySQL

=head3 Arguments

None.

=head3 Returns

Returns true if remote MySQL, false if not

=cut

sub is_remote_mysql {
    my ($self) = @_;
    return $_is_remote_mysql if defined $_is_remote_mysql;

    # We are forcing everything to think we are running a local MySQL instance when running cpcloud mode since
    # we connect through the localhost socket.
    try {
        require Cpanel::MysqlUtils::RemoteMySQL::ProfileManager;
        if ( Cpanel::MysqlUtils::RemoteMySQL::ProfileManager->new( { 'read_only' => 1 } )->is_active_profile_cpcloud() ) {
            $_is_remote_mysql = 0;
        }
    }
    catch {
        require Cpanel::Debug;
        Cpanel::Debug::log_info("Could not query the active MySQL profile: $_");

    };

    return $_is_remote_mysql if defined $_is_remote_mysql;
    return ( $_is_remote_mysql = Cpanel::MysqlUtils::MyCnf::Basic::is_remote_mysql( $self->{'dbh'}->attributes()->{'host'} ) ? 1 : 0 );
}

sub listhosts {
    my $self = shift;

    return @{ $self->_convert_user_hosts_map_to_hosts_ar( $self->_get_all_hosts_for_users() ) };
}

sub _convert_user_hosts_map_to_hosts_ar {
    my ( $self, $user_hosts_map ) = @_;

    my %HOSTS;
    foreach my $user ( keys %{$user_hosts_map} ) {
        @HOSTS{ @{ $user_hosts_map->{$user} } } = ();
    }
    $HOSTS{'localhost'} = undef;
    return [ sort keys %HOSTS ];
}

=head2 _get_all_hosts_for_users()

Get a list of all hosts for the users

=head3 Arguments

None.

=head3 Returns

Returns a list of hosts

=cut

sub _get_all_hosts_for_users {
    my ($self) = @_;

    my %user_list = map { $_ => 1 } ( $self->{'cpuser'}, $self->listusers() );

    return Cpanel::MysqlUtils::Grants::Users::get_all_hosts_for_users( $self->{'dbh'}, [ keys %user_list ] );
}

=head2 _query_single_value

Query a single value from the DB.

=head3 Arguments

=over

=item * SQL query string

=back

=head3 Returns

A single result of the query.

=cut

sub _query_single_value ( $self, $query ) {
    my ($val) = $self->{'dbh'}->selectrow_array($query);

    return $val;
}

1;
