package Cpanel::Admin::Base::DB;

# cpanel - Cpanel/Admin/Base/DB.pm                 Copyright 2022 cPanel, L.L.C.
#                                                           All rights reserved.
# copyright@cpanel.net                                         http://cpanel.net
# This code is subject to the cPanel license. Unauthorized copying is prohibited

use cPstrict;

=encoding utf-8

=head1 NAME

Cpanel::Admin::Base::DB

=head1 DESCRIPTION

This module corrals logic that is common to MySQL and PostgreSQL
admin modules. Don’t instantiate it directly.

=cut

#----------------------------------------------------------------------

use parent qw( Cpanel::Admin::Base );

use Try::Tiny;

use Cpanel::DB                    ();
use Cpanel::Exception             ();
use Cpanel::PasswdStrength::Check ();
use Cpanel::PwCache               ();

sub _actions {
    return qw(
      CREATE_DATABASE
      CREATE_USER
      RENAME_DATABASE
      RENAME_USER
      DELETE_DATABASE
      SET_PASSWORD
      SETUP_DATABASE_AND_USER
      VERYIFY_DB_OWNER
      GET_VERSION
    );
}

#----------------------------------------------------------------------

=head1 FUNCTIONS

=head2 SET_PASSWORD( $DBUSERNAME, $PASSWORD )

Sets the DB user’s password.

This returns the output from the underlying admin object’s
C<set_password()> method. (As of 11.50, that’s different for
L<Cpanel::Mysql> and L<Cpanel::PostgresAdmin>.)

=cut

sub SET_PASSWORD {
    my ( $self, $user, $password ) = @_;

    $self->_verify_that_password_is_there($password);

    if ( !$self->_admin()->owns_dbuser($user) ) {
        $self->whitelist_exception('Cpanel::Exception::Database::UserNotFound');
        die Cpanel::Exception::create( 'Database::UserNotFound', [ name => $user, engine => $self->_engine(), 'cpuser' => $self->_admin()->{'cpuser'} ] );
    }

    return $self->_admin()->set_password( $user, $password );
}

=head2 CREATE_USER( $DBUSERNAME, $PASSWORD )

Returns nothing.

=cut

sub CREATE_USER {
    my ( $self, $dbuser, $password, $prefixsize ) = @_;

    $self->_verify_prefix( $dbuser, $prefixsize );
    $self->_check_dbuser_against_pw($dbuser);

    $self->_verify_that_password_is_there($password);

    $self->whitelist_exception('Cpanel::Exception::PasswordIsTooWeak');
    Cpanel::PasswdStrength::Check::verify_or_die( app => $self->_password_app(), pw => $password );

    if ( $self->_admin()->user_exists($dbuser) ) {
        $self->whitelist_exception('Cpanel::Exception::InvalidParameter');
        die Cpanel::Exception::create( 'InvalidParameter', 'The user “[_1]” cannot be created because it already exists.', [$dbuser] );
    }

    if ( $self->_admin()->role_exists($dbuser) ) {
        $self->whitelist_exception('Cpanel::Exception::InvalidParameter');
        die Cpanel::Exception::create( 'InvalidParameter', "The database “[_1]” already exists, and you, “[_2]”, are not allowed to create a user with the same name.", [ $dbuser, $self->_admin()->{'cpuser'} ] );
    }

    my ( $ok, $err ) = $self->_admin()->raw_passwduser( $dbuser, $password );
    die Cpanel::Exception->create_raw($err) if !$ok;

    return;
}

=head2 SETUP_DATABASE_AND_USER( $DBNAME )

Returns the database name, user name, password, host, and port.

=cut

sub SETUP_DATABASE_AND_USER ( $self, $prefix = "" ) {

    require Cpanel::Rand::Mysql;
    my $cpuser = $self->get_caller_username;
    my ( $db_name, $db_user, $password );

    my $error = '';

    foreach ( 1 .. 5 ) {    # We shouldn't ever hit 2 collisions let alone 5.
        try {
            $db_name = Cpanel::Rand::Mysql::get_random_db_name( $cpuser, $prefix );
            $self->CREATE_DATABASE( $db_name, 0 );
        }
        catch {
            $error   = Cpanel::Exception::get_string($_);
            $db_name = "";
            next;
        };

        last;
    }
    length $db_name or die Cpanel::Exception::create_raw( 'Database::DatabaseCreationFailed', "Unable to create a randomized database for $cpuser: $error" );

    foreach ( 1 .. 5 ) {    # We shouldn't ever hit 2 collisions let alone 5.
        try {
            $db_user  = Cpanel::Rand::Mysql::get_random_db_user( $cpuser, $prefix );
            $password = Cpanel::Rand::Mysql::get_random_db_password();
            $self->CREATE_USER( $db_user, $password, 0 );
        }
        catch {
            $error   = Cpanel::Exception::get_string($_);
            $db_user = "";
            next;
        };

        last;
    }
    if ( !length $db_user ) {
        eval { $self->_admin()->drop_db($db_name) };    # Ignore if this fails. We need to complain about the real error.
        die Cpanel::Exception::create_raw( 'Database::DatabaseCreationFailed', "Unable to create a randomized database for $cpuser: $error" );
    }

    $self->SET_USER_PRIVILEGES_ON_DATABASE( $db_user, $db_name, ['ALL PRIVILEGES'] );

    my ( $host, $port ) = Cpanel::Rand::Mysql::mysql_host_port();

    return ( $db_name, $db_user, $password, $host, $port );
}

=head2 CREATE_DATABASE( $DBNAME )

Returns nothing.

=cut

sub CREATE_DATABASE {
    my ( $self, $db, $prefixsize ) = @_;

    $self->_verify_prefix( $db, $prefixsize );

    my $maxdbs = $self->_get_caller_cpuser_data()->{'MAXSQL'};

    require Cpanel::Async::EasyLock;
    require Cpanel::PromiseUtils;

    # Each invocation of the same pair of (user, engine) needs to use the same lock name:
    my $LOCK_ID = $self->get_caller_username() . '_' . $self->_engine();
    Cpanel::PromiseUtils::wait_anyevent(
        Cpanel::Async::EasyLock::lock_exclusive_p($LOCK_ID)->then(
            sub {
                if ( length($maxdbs) && ( $maxdbs !~ m<unlimited>i ) ) {
                    $maxdbs = int $maxdbs;

                    my $dbs_count = $self->_admin()->countdbs();
                    if ( $maxdbs <= $dbs_count ) {
                        $self->whitelist_exception('Cpanel::Exception::Database::DatabaseCreationFailed');
                        die Cpanel::Exception::create( 'Database::DatabaseCreationFailed', 'You have reached your maximum allotment of databases ([numf,_1]).', [$dbs_count] );
                    }
                }

                my ( $status, $message ) = $self->_admin()->raw_create_db($db);
                if ( !$status ) {
                    $self->whitelist_exception('Cpanel::Exception::Database::DatabaseCreationFailed');
                    die Cpanel::Exception::create_raw( 'Database::DatabaseCreationFailed', $message );
                }
            }
        )
    );

    return;
}

=head2 DELETE_DATABASE( $DBNAME )

Returns 1 (for no particular reason).

=cut

sub DELETE_DATABASE {
    my ( $self, $name ) = @_;

    $self->_verify_owns_db($name);

    $self->_admin()->drop_db($name);

    return 1;
}

=head2 RENAME_DATABASE( $OLDNAME => $NEWNAME )

Returns the output from the admin object’s C<rename_database()> method.

=cut

sub RENAME_DATABASE {
    my ( $self, $oldname, $newname ) = @_;

    $self->_verify_owns_db($oldname);

    $self->_verify_prefix($newname);

    $self->whitelist_exception('Cpanel::Exception::NameConflict');
    return $self->_admin()->rename_database( $oldname, $newname );
}

=head2 RENAME_USER( $OLDNAME => $NEWNAME )

Returns the output from the admin object’s C<rename_dbuser()> method.

=cut

sub RENAME_USER {
    my ( $self, $oldname, $newname ) = @_;

    if ( !$self->_admin()->owns_dbuser($oldname) ) {
        $self->whitelist_exception('Cpanel::Exception::Database::UserNotFound');
        die Cpanel::Exception::create( 'Database::UserNotFound', [ name => $oldname, engine => $self->_engine(), 'cpuser' => $self->_admin()->{'cpuser'} ] );
    }

    $self->_verify_prefix($newname);

    $self->_check_dbuser_against_pw($newname);

    return $self->_admin()->rename_dbuser( $oldname, $newname );
}

sub VERYIFY_DB_OWNER {
    my ( $self, $dbname ) = @_;

    return $self->_verify_owns_db($dbname);
}

=head2 GET_VERSION()

Returns a hashref containing version information.

=cut

sub GET_VERSION {
    my ( $self, ) = @_;

    require Cpanel::MysqlUtils::Version;
    my $version = eval { Cpanel::MysqlUtils::Version::current_mysql_version() };

    my $err = $@;
    if ($err) {
        die Cpanel::Exception::create(
            'Database::Error',
            "Could not retrieve database version information due to an error: [_1].",
            [$err],
        );
    }

    return $version;
}

#----------------------------------------------------------------------

sub _verify_owns_db {
    my ( $self, $dbname ) = @_;

    if ( !$self->_admin()->owns_db($dbname) ) {
        $self->whitelist_exception('Cpanel::Exception::Database::DatabaseNotFound');
        die Cpanel::Exception::create( 'Database::DatabaseNotFound', [ name => $dbname, engine => $self->_engine(), 'cpuser' => $self->_admin()->{'cpuser'} ] );
    }

    return 1;
}

sub _verify_that_password_is_there {
    my ( $self, $password ) = @_;

    if ( !defined $password ) {
        $self->whitelist_exception('Cpanel::Exception::MissingParameter');
        die Cpanel::Exception::create( 'MissingParameter', 'Provide a password.' );
    }
    if ( !length $password ) {
        $self->whitelist_exception('Cpanel::Exception::Empty');
        die Cpanel::Exception::create( 'Empty', 'A password cannot be empty.' );
    }

    return 1;
}

sub _check_dbuser_against_pw {
    my ( $self, $name ) = @_;

    if ( ( Cpanel::PwCache::getpwnam($name) )[0] ) {
        $self->whitelist_exception('Cpanel::Exception::InvalidParameter');
        die Cpanel::Exception::create( 'InvalidParameter', 'There is a system user named “[_1]”. You cannot create a database user with that name.', [$name] );
    }

    return 1;
}

sub _verify_prefix {
    my ( $self, $name, $prefixsize ) = @_;

    local $Cpanel::user = $self->get_caller_username();

    my $prefixed_name = Cpanel::DB::add_prefix_if_name_and_server_need($name);
    my $short_prefix;

    if ( $prefixsize && $prefixsize eq '8' ) {
        require Cpanel::DB::Prefix;
        local $Cpanel::DB::Prefix::PREFIX_LENGTH = 8;

        $prefixed_name = Cpanel::DB::add_prefix_if_name_and_server_need($name);
        $short_prefix  = Cpanel::DB::get_prefix();

        require Cpanel::Config::DBOwners;
        my $dbowners_ref = Cpanel::Config::DBOwners::load_dbowner_to_user();

        # Check to see if any other database owners start with the same prefix.
        if ( my @dbowner_conflicts = grep { rindex( $_, $short_prefix, 0 ) == 0 } keys %{$dbowners_ref} ) {

            require Cpanel::DB::Utils;
            my $dbowner_name = Cpanel::DB::Utils::username_to_dbowner($Cpanel::user);

            # Check if the conflict is with a different user. If so, raise an exception.
            # If it is the same user, we can continue.
            if ( grep { $_ ne $dbowner_name } @dbowner_conflicts ) {
                $self->whitelist_exception('Cpanel::Exception::NameConflict');
                die Cpanel::Exception::create( 'NameConflict', 'The name of another account on this server has the same initial [quant,_1,character,characters] as the given username ([_2]). Each username’s first [quant,_1,character,characters] must be unique.', [ 8, $Cpanel::user ] );
            }
        }

    }

    if ( $name ne $prefixed_name ) {
        my $prefix = $short_prefix ? $short_prefix : Cpanel::DB::get_prefix();
        $prefix .= '_';

        $self->whitelist_exception('Cpanel::Exception::InvalidParameter');
        die Cpanel::Exception::create( 'InvalidParameter', 'The name “[_1]” does not begin with the required prefix “[_2]”.', [ $name, $prefix ] );
    }

    return 1;
}

1;
