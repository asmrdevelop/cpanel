package Cpanel::Admin::Modules::Cpanel::mysql;

# cpanel - Cpanel/Admin/Modules/Cpanel/mysql.pm    Copyright 2022 cPanel, L.L.C.
#                                                           All rights reserved.
# copyright@cpanel.net                                         http://cpanel.net
# This code is subject to the cPanel license. Unauthorized copying is prohibited

use strict;
use warnings;

=encoding utf-8

=head1 NAME

Cpanel::Admin::Modules::Cpanel::mysql - MySQL admin functions

=head1 DESCRIPTION

This module subclasses L<Cpanel::Admin::Base::DB>. Additional
functionality is described below:

=cut

use parent qw( Cpanel::Admin::Base::DB );

use Try::Tiny;

use Cpanel::Exception                               ();
use Cpanel::Mysql                                   ();
use Cpanel::MysqlUtils::Version                     ();
use Cpanel::Security::Authz                         ();
use Cpanel::Validate::DB::Name                      ();
use Cpanel::MysqlUtils::RemoteMySQL::ProfileManager ();

# This has to be open because Pkgacct calls it,
# and we distribute an uncompiled scripts/pkgacct.
use constant _allowed_parents => '*';

sub _init {
    my ($self) = @_;

    # case CPANEL-1989: GET_SERVER_INFORMATION always needs
    # to be callable even if they do not have the mysql
    # feature
    if ( $self->get_action() ne 'GET_SERVER_INFORMATION' ) {
        Cpanel::Security::Authz::verify_user_has_feature(
            $self->get_caller_username(),
            'mysql',
        );
    }

    $self->{'_engine'} = 'mysql';

    return;
}

sub _admin {
    my ($self) = @_;

    #TODO: Catch errors from this.
    return (
        $self->{'_admin'} ||= Cpanel::Mysql->new(
            {
                cpuser           => $self->get_caller_username(),
                ERRORS_TO_STDOUT => 0,
            }
        )
    );
}

sub _actions {
    my ($self) = @_;

    return (
        $self->SUPER::_actions(),
        'GET_SERVER_INFORMATION',
        'GRANTABLE_PRIVILEGES',
        'TEST_LOGIN_CREDENTIALS',
        'REASON_WHY_DB_NAME_IS_INVALID',
        'GET_USER_PRIVILEGES_ON_DATABASE',
        'SET_USER_PRIVILEGES_ON_DATABASE',
        'REVOKE_USER_ACCESS_TO_DATABASE',
        'CHECK_DATABASE',
        'REPAIR_DATABASE',
        'ADD_HOST_NOTE',
        'GET_HOST_NOTES',
        'DUMP_SCHEMA',
        'GET_DISK_USAGE',
        'LIST_ROUTINES',
        'STREAM_DUMP_DATA_UTF8MB4',
        'STREAM_DUMP_DATA_UTF8',
        'STREAM_DUMP_NODATA_UTF8MB4',
        'STREAM_DUMP_NODATA_UTF8',
        'DBEXISTS',
        'IS_ACTIVE_PROFILE_CPCLOUD',
    );
}

sub _demo_actions {
    my ($self) = @_;

    return (
        'GET_SERVER_INFORMATION',
        'LIST_ROUTINES',
        'DUMP_SCHEMA',
        'GET_DISK_USAGE',
        'GET_HOST_NOTES',
        'GET_USER_PRIVILEGES_ON_DATABASE',
        'REASON_WHY_DB_NAME_IS_INVALID',
        'IS_ACTIVE_PROFILE_CPCLOUD',
    );
}

=head1 FUNCTIONS

=head2 DBEXISTS( $DBNAME )

Runs C<SHOW DATABASES WHERE `Database` = ?> to see if the specified
database already exists, returns the number of rows found.

=cut

sub DBEXISTS {
    my ( $self, $database ) = @_;

    return $self->_admin()->db_exists($database);
}

=head2 CHECK_DATABASE( $DBNAME )

Runs C<CHECK TABLE> for all tables in the indicated database.
The return is a list of array references, each of which is:
[ table name, message type, message text ].

=cut

sub CHECK_DATABASE {
    my ( $self, $database ) = @_;

    return $self->_admin()->check_database($database);

}

=head2 REPAIR_DATABASE( $DBNAME )

Runs C<REPAIR TABLE> for all tables in the indicated database.
The return is the same format as for C<CHECK_DATABASE()>.

=cut

sub REPAIR_DATABASE {
    my ( $self, $database ) = @_;

    return $self->_admin()->repair_database($database);
}

=head2 GET_USER_PRIVILEGES_ON_DATABASE( $DBUSERNAME, $DBNAME )

Returns a list of the MySQL-reported privileges that the given DB user
has on the given database.

=cut

sub GET_USER_PRIVILEGES_ON_DATABASE {
    my ( $self, $user, $database ) = @_;

    if ( !length $database ) {
        die Cpanel::Exception::create( "InvalidParameter", 'The “[_1]” parameter is required, and you must pass a valid string value.', ['database'] );
    }

    if ( !length $user ) {
        die Cpanel::Exception::create( "InvalidParameter", 'The “[_1]” parameter is required, and you must pass a valid string value.', ['user'] );
    }

    my ( undef, $privs_str ) = $self->_admin()->listprivs( $user, 'localhost', $database );

    return length($privs_str) ? split m<\s*,+\s*>, $privs_str : ();
}

=head2 SET_USER_PRIVILEGES_ON_DATABASE( $DBUSERNAME, $DBNAME, \@PRIVS )

Sets the given DB user’s privileges on the given database.

=cut

sub SET_USER_PRIVILEGES_ON_DATABASE {
    my ( $self, $user, $database, $privs_ar ) = @_;

    if ( !length $database ) {
        die Cpanel::Exception::create( "InvalidParameter", 'The “[_1]” parameter is required, and you must pass a valid string value.', ['database'] );
    }

    if ( !length $user ) {
        die Cpanel::Exception::create( "InvalidParameter", 'The “[_1]” parameter is required, and you must pass a valid string value.', ['user'] );
    }

    $self->_admin()->addusertodb_literal_privs( $user, $database, $privs_ar );

    return 1;
}

=head2 REVOKE_USER_ACCESS_TO_DATABASE( $DBUSERNAME, $DBNAME )

Just as it sounds!

=cut

sub REVOKE_USER_ACCESS_TO_DATABASE {
    my ( $self, $user, $database ) = @_;

    if ( !length $database ) {
        die Cpanel::Exception::create( "InvalidParameter", 'The “[_1]” parameter is required, and you must pass a valid string value.', ['database'] );
    }

    if ( !length $user ) {
        die Cpanel::Exception::create( "InvalidParameter", 'The “[_1]” parameter is required, and you must pass a valid string value.', ['user'] );
    }

    $self->_admin()->deluserfromdb_fatal( $database, $user );

    return 1;
}

=head2 GRANTABLE_PRIVILEGES()

Returns a list of the privileges that can be given to a DB user
for the current MySQL server version.

=cut

#Returns a list.
sub GRANTABLE_PRIVILEGES {
    my ($self) = @_;

    return $self->_admin()->grantable_privileges();
}

sub _engine {
    return 'mysql';
}

sub _password_app {
    return 'mysql';
}

=head2 TEST_LOGIN_CREDENTIALS( $DBUSERNAME, $PASSWORD )

Returns 1 on success or 0 if the login fails.
This also validates that the cpuser owns a DB user with the given name.

B<NOTE:> This can easily be implemented in unprivileged code; please
don’t call this function.

=cut

sub TEST_LOGIN_CREDENTIALS {
    my ( $self, $username, $password ) = @_;

    return $self->_admin()->test_login_credentials( $username, $password );
}

=head2 GET_SERVER_INFORMATION()

Returns a hash reference with the following data:

=over

=item * C<host> - The MySQL server’s hostname, or C<localhost> if
MySQL runs locally.

=item * C<version> - The full MySQL server version, e.g., C<5.6.43-log>.

=back

=cut

sub GET_SERVER_INFORMATION {
    my $info = Cpanel::MysqlUtils::Version::current_mysql_version();

    return {
        host    => $info->{'host'},
        version => $info->{'full'},
    };
}

=head2 REASON_WHY_DB_NAME_IS_INVALID( $DBNAME )

Returns a string.

This can be done in unprivileged code now that MySQL 5.0 is unsupported;
please don’t add new calls to this function.

=cut

sub REASON_WHY_DB_NAME_IS_INVALID {
    my ( $self, $name ) = @_;

    my $err;
    try { Cpanel::Validate::DB::Name::verify_mysql_database_name($name) } catch { $err = $_->to_string() };

    return $err;
}

=head2 ADD_HOST_NOTE( $HOSTNAME, $NOTE )

Adds a note about a given MySQL remote-access host.
See L<Cpanel::Mysql::Remote::Notes> for more information.

=cut

sub ADD_HOST_NOTE {
    my ( $self, $host, $note ) = @_;

    require Cpanel::Mysql::Remote::Notes;
    my @remote_access_hosts = $self->_admin()->listhosts();

    if ( !grep { $_ eq $host } @remote_access_hosts ) {
        die 'That host is not authorized for remote access.';
    }
    my $notes_obj = Cpanel::Mysql::Remote::Notes->new(
        username => $self->get_caller_username(),
    );
    $notes_obj->set( $host => $note );

    return;
}

=head2 GET_HOST_NOTES()

Returns all of the user’s current notes about MySQL remote-access hosts.
See L<Cpanel::Mysql::Remote::Notes> for more information.

=cut

sub GET_HOST_NOTES {
    my $self = shift;

    require Cpanel::Mysql::Remote::Notes;
    my $notes_obj = Cpanel::Mysql::Remote::Notes->new(
        username => $self->get_caller_username(),
    );

    return { $notes_obj->get_all() };
}

=head2 DUMP_SCHEMA( $DBNAME )

Return the MySQL commands to recreate $DBNAME’s schema in a text blob.

=cut

sub DUMP_SCHEMA {
    my ( $self, $dbname ) = @_;

    $self->_verify_owns_db($dbname);

    require Cpanel::MysqlUtils::Dump;

    return Cpanel::MysqlUtils::Dump::dump_database_schema($dbname);
}

=head2 GET_DISK_USAGE()

Return the amount of disk used by a user's databases.
See L<Cpanel::Mysql::_diskusage> for more information.

=cut

sub GET_DISK_USAGE {
    my ($self) = @_;

    return $self->_admin()->diskusage();

}

=head2 LIST_ROUTINES( $database_user )

Return routines defined by $database_user.
See L<Cpanel::Mysql> list_routines method for more information.

=cut

sub LIST_ROUTINES {
    my ( $self, $database_user ) = @_;

    my @routines = $self->_admin()->list_routines($database_user);
    return \@routines;
}

#----------------------------------------------------------------------

=head2 STREAM_DUMP_DATA_UTF8MB4( $DBNAME )

Attempt a one-time dump of the database whose name is $DBNAME
with MySQL’s C<utf8mb4> as the default encoding.

=cut

sub STREAM_DUMP_DATA_UTF8MB4 {
    my ( $self, $dbname ) = @_;

    return $self->_stream_dump_data( $dbname, 'stream_database_data_utf8mb4' );
}

#----------------------------------------------------------------------

=head2 STREAM_DUMP_DATA_UTF8( $DBNAME )

Like C<STREAM_DUMP_DATA_UTF8MB4()> but uses
MySQL’s C<utf8> instead of C<utf8mb4>.

=cut

sub STREAM_DUMP_DATA_UTF8 {
    my ( $self, $dbname ) = @_;

    return $self->_stream_dump_data( $dbname, 'stream_database_data_utf8' );
}

#----------------------------------------------------------------------

=head2 STREAM_DUMP_NODATA_UTF8MB4( $DBNAME )

Like C<STREAM_DUMP_DATA_UTF8MB4()> but omits the
database data.

=cut

sub STREAM_DUMP_NODATA_UTF8MB4 {
    my ( $self, $dbname ) = @_;

    return $self->_stream_dump_data( $dbname, 'stream_database_nodata_utf8mb4' );
}

#----------------------------------------------------------------------

=head2 STREAM_DUMP_NODATA_UTF8( $DBNAME )

Like C<STREAM_DUMP_DATA_UTF8()> but omits the database data.

=cut

sub STREAM_DUMP_NODATA_UTF8 {
    my ( $self, $dbname ) = @_;

    return $self->_stream_dump_data( $dbname, 'stream_database_nodata_utf8' );
}

#----------------------------------------------------------------------

=head2 IS_ACTIVE_PROFILE_CPCLOUD

Checks if the current active profile is a cPanel Cloud deployment.

=cut

sub IS_ACTIVE_PROFILE_CPCLOUD {
    my ($self) = @_;

    my $pm = Cpanel::MysqlUtils::RemoteMySQL::ProfileManager->new( { 'read_only' => 1 } );
    return $pm->is_active_profile_cpcloud();
}

#----------------------------------------------------------------------

sub _stream_dump_data {
    my ( $self, $dbname, $fn ) = @_;

    my $out_fh = $self->get_passed_fh() or do {
        die Cpanel::Exception::create_raw( AdminError => "Need filehandle!" );
    };

    $self->_verify_owns_db($dbname);

    $self->whitelist_exception('Cpanel::Exception::Database::MysqlIllegalCollations');

    require Cpanel::MysqlUtils::Dump;
    Cpanel::MysqlUtils::Dump->can($fn)->( $out_fh, $dbname );

    return;
}

#----------------------------------------------------------------------

1;

=head1 SEE ALSO

F<bin/admin/Cpanel/cpmysql.pl> contains the early MySQL
admin logic. It would be nice to move that functionality to be callable
from this module.

=cut
