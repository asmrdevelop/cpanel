package Cpanel::DB::GrantsFile;

# cpanel - Cpanel/DB/GrantsFile.pm                 Copyright 2022 cPanel, L.L.C.
#                                                           All rights reserved.
# copyright@cpanel.net                                         http://cpanel.net
# This code is subject to the cPanel license. Unauthorized copying is prohibited

#----------------------------------------------------------------------
# This module encapsulates interaction with the DB grants files.
#
# TODO: Corral remaining interactions with these files in our code
# so that they all use this module.
#----------------------------------------------------------------------

use strict;
use warnings;

=encoding utf-8

=head1 NAME

Cpanel::DB::GrantsFile

=head1 SYNOPSIS

    delete_for_user( $username );

    dump_for_cpuser( $username );

    my $all_grants_hr = read_for_cpuser( $username );

    my $grants_obj = Cpanel::DB::GrantsFile->new( $username );

    $grants_obj->set_default_grants( $raw_password );

    $grants_obj->set_mysql_grants_as_objects( \@grant_objs );

    $grants_obj->set_mysql_grants( {
        $dbowner => \@sql_stmts,
        $dbusername => \@more_sql_stmts,
    } );

    $grants_obj->set_postgresql_grants( ... );  #same syntax as for MySQL

    $grants_obj->save();    #or abort()

=head1 DESCRIPTION

This module encompasses most likely interactions with the DB grants
files. These files cache the DB grants (including passwords) for dbowners
(i.e., cPanel users’ default DB users) and created DB users.

=cut

use Try::Tiny;

use Cpanel::Autodie                      ();
use Cpanel::Autodie::Unlink              ();
use Cpanel::CachedDataStore              ();
use Cpanel::ConfigFiles                  ();
use Cpanel::DB::Utils                    ();
use Cpanel::Validate::FilesystemNodeName ();

our $_ROOT;

my $DEFAULT_MYSQL_FORMAT = "GRANT USAGE ON *.* TO \%s\@\%s";
my $DEFAULT_PGSQL_FORMAT = 'CREATE USER %s WITH PASSWORD %s';

BEGIN {
    *_ROOT = \*Cpanel::ConfigFiles::DATABASES_INFO_DIR;
}

=head1 STATIC FUNCTIONS

=head2 $did_yn = delete_for_user( $USERNAME )

Deletes the DB grants file for a user whose name is given.

Returns the number of files deleted; will not die() unless
there is a file that exists that cannot be unlink()ed.

=cut

sub delete_for_cpuser {
    my ($username) = @_;

    Cpanel::Validate::FilesystemNodeName::validate_or_die($username);

    return Cpanel::Autodie::Unlink::unlink_if_exists_batch( map { "$_ROOT/grants_$username.$_" } qw( yaml cache ) );
}

#----------------------------------------------------------------------

=head2 read_for_cpuser( $CP_USERNAME )

Returns the parsed contents of the given cP user’s grants file.
Returns undef if the file doesn’t exist.  Throws a generic exception
on failure.

The return structure is a hash reference like:

=over

=item * C<MYSQL> - a reference to a hash. Each key is a database user or the
cpuser’s dbowner, and each value is a reference to an array of MySQL GRANT
statements, as strings.

=item * C<PGSQL> - Same structure as C<MYSQL> but for PostgreSQL.

=back

=cut

sub read_for_cpuser {
    my ($cpuser) = @_;

    _validate_cpuser($cpuser);

    my $db_file = _get_user_db_file($cpuser);

    # Ideally we’d just look for an ENOENT error from open() rather than
    # doing a stat(), but CachedDataStore doesn’t expose open() errors. :(
    return undef if !Cpanel::Autodie::exists($db_file);

    require Cpanel::CachedDataStore;
    if ( my $grants_db = Cpanel::CachedDataStore::load_ref( $db_file, 1 ) ) {
        for my $val ( values %$grants_db ) {
            $val = ( values %$val )[0];
        }

        return $grants_db;
    }

    die _load_grants_exception($db_file);
}

#----------------------------------------------------------------------

=head2 dump_for_cpuser( $USERNAME )

Sync the grants for the cP user and all owned DB users to the grants file.

=cut

sub dump_for_cpuser {
    my ($cpuser) = @_;

    _validate_cpuser($cpuser);

    require Cpanel::DB::Grants;
    require Cpanel::Services::Enabled;

    my ( $mysql_grants, $pgsql_grants );

    if ( Cpanel::Services::Enabled::is_provided('mysql') ) {
        $mysql_grants = Cpanel::DB::Grants::get_cpuser_mysql_grants($cpuser);
    }

    if ( Cpanel::Services::Enabled::is_provided('postgresql') ) {
        $pgsql_grants = Cpanel::DB::Grants::get_cpuser_postgresql_grants($cpuser);
    }

    if ( $mysql_grants || $pgsql_grants ) {
        my $grants_obj = __PACKAGE__->new($cpuser);

        $mysql_grants && $grants_obj->set_mysql_grants($mysql_grants);

        $pgsql_grants && $grants_obj->set_postgresql_grants($pgsql_grants);

        $grants_obj->save();
    }

    return;
}

#----------------------------------------------------------------------

=head1 CLASS INTERFACE

=head2 I<CLASS>->new( $USERNAME )

Opens a transaction for the given user’s grants file.

=cut

sub new {
    my ( $class, $cpuser ) = @_;

    _validate_cpuser($cpuser);

    $cpuser =~ tr{/}{}d;    # just in case /

    # Ensure database directory exists
    require Cpanel::DB::Map::Setup;
    Cpanel::DB::Map::Setup::initialize();

    my $db_file = _get_user_db_file($cpuser);

    # Grants file contains sensitive information and must not be world readable
    require Cpanel::SecureFile;
    Cpanel::SecureFile::set_permissions($db_file);

    Cpanel::Autodie::unlink_if_exists("$_ROOT/grants.db");

    my $grants_db = Cpanel::CachedDataStore::loaddatastore( $db_file, 1 ) or do {
        die _load_grants_exception($db_file);
    };

    my %self = (
        _cpuser  => $cpuser,
        _db      => $grants_db,
        _db_file => $db_file,
    );

    return bless \%self, $class;
}

#----------------------------------------------------------------------

=head2 I<OBJ>->get_mysql_grants()

Returns a hash reference in the same format as the C<MYSQL> return in
C<read_for_cpuser()>.

=cut

sub get_mysql_grants {
    my ($self) = @_;

    return $self->_get_loaded_grants('MYSQL');
}

#----------------------------------------------------------------------

=head2 I<OBJ>->set_postgresql_grants( $GRANTS_HR )

Like C<get_mysql_grants()> but for PostgreSQL.

=cut

sub get_postgresql_grants {
    my ($self) = @_;

    return $self->_get_loaded_grants('PGSQL');
}

#----------------------------------------------------------------------

=head2 I<OBJ>->set_mysql_grants( $GRANTS_HR )

Accepts a hash reference in the same format as the C<MYSQL> return in
C<read_for_cpuser()>.

Returns the I<OBJ>.

=cut

sub set_mysql_grants {
    my ( $self, $grants_hr ) = @_;

    return $self->_set_dbtype_grants( 'MYSQL', $grants_hr );
}

#----------------------------------------------------------------------

=head2 I<OBJ>->set_postgresql_grants( $GRANTS_HR )

Like C<set_mysql_grants()> but for PostgreSQL.

=cut

sub set_postgresql_grants {
    my ( $self, $grants_hr ) = @_;

    return $self->_set_dbtype_grants( 'PGSQL', $grants_hr );
}

#----------------------------------------------------------------------

=head2 I<OBJ>->save()

Saves the datastore. Each class instance must call this method or C<abort()>
once, or else a warning is given upon object destruction.

If this is called after C<abort()> or C<save()> on the same instance,
an error is thrown.

Returns the I<OBJ>.

=cut

sub save {
    my ($self) = @_;

    my $grants_db = $self->{'_db'} or die "Already saved or aborted?";

    $grants_db->save();
    $grants_db->unlockdatastore();

    delete $self->{'_db'};

    return $self;
}

#----------------------------------------------------------------------

=head2 I<OBJ>->abort()

Aborts the transaction. Each class instance must call this method or
C<save()> once, or else a warning is given upon object destruction.

If this is called after C<abort()> or C<save()> on the same instance,
a warning is given.

Returns the I<OBJ>.

=cut

sub abort {
    my ($self) = @_;

    my $obj = delete $self->{'_db'} or warn "Already saved or aborted?";

    $obj->abort();

    return $self;
}

#----------------------------------------------------------------------

=head2 I<OBJ>->set_mysql_grants_as_objects( $GRANTS_AR )

Takes a reference to an array of L<Cpanel::MysqlUtils::Grants> objects and
sets the cPanel user’s saved MySQL/MariaDB grants accordingly.

Returns the I<OBJ>.

=cut

sub set_mysql_grants_as_objects {
    my ( $self, $grants_ar ) = @_;

    if ( !$grants_ar ) {
        require Cpanel::Exception;
        die Cpanel::Exception::create( 'MissingParameter', 'You must specify the list of grants to store.' );
    }
    elsif ( ref $grants_ar ne 'ARRAY' ) {
        require Cpanel::Exception;
        die Cpanel::Exception::create( 'InvalidParameter', "The “[_1]” parameter must be an array reference.", ["grants"] );
    }
    else {
        for (@$grants_ar) {
            if ( !$_->isa('Cpanel::MysqlUtils::Grants') ) {
                require Cpanel::Exception;
                die Cpanel::Exception::create( 'InvalidParameter', "The “[_1]” parameter must be an array reference containing only “[_2]” objects.", [ "grants", "Cpanel::MysqlUtils::Grants" ] );
            }
        }
    }

    my %grants;

    foreach my $grant (@$grants_ar) {

        my $grant_str = $grant->to_string();

        # The grants file does not end the GRANT SQL with a semicolon,
        # but Cpanel::MysqlUtils::Grants::to_string does.
        chop($grant_str) if substr( $grant_str, -1 ) eq ';';

        push @{ $grants{ $grant->db_user() } ||= [] }, $grant_str;
    }

    return $self->set_mysql_grants( \%grants );
}

#----------------------------------------------------------------------

=head2 I<OBJ>->add_default_grants( $PASSWORD )

Save the given $PASSWORD with the appropriate grants in the grants file.
This is appropriate to call when creating a user or when reenabling
MySQL/MariaDB or PostgreSQL, i.e., so that any users created while the DB was
disabled will receive the necessary database grants to log in.

Returns the I<OBJ>.

=cut

sub set_default_grants {
    my ( $self, $password ) = @_;

    die 'need password' if !length $password;

    $self->set_postgresql_grants( $self->_get_default_postgresql_grants($password) );

    return $self->set_mysql_grants( $self->_get_default_mysql_grants($password) );
}

#----------------------------------------------------------------------

sub DESTROY {
    my ($self) = @_;

    if ( my $datastore = delete $self->{'_db'} ) {
        warn "$self ($self->{'_cpuser'}) was neither save()d nor abort()ed!";

        $datastore->abort();
    }

    return;
}

sub _get_loaded_grants {
    my ( $self, $dbtype ) = @_;

    return $self->{'_db'}{'data'}{$dbtype}{ $self->{'_cpuser'} } || {};
}

sub _set_dbtype_grants {
    my ( $self, $dbtype, $grants_hr ) = @_;

    $self->{'_db'}{'data'}{$dbtype}{ $self->{'_cpuser'} } = $grants_hr;

    return $self;
}

sub _load_grants_exception {
    my ($db_file) = @_;

    require Cpanel::Exception;
    return Cpanel::Exception->create_raw("Failed to load “$db_file”.");
}

sub _get_user_db_file {
    my ($username) = @_;
    return "$_ROOT/grants_${username}.yaml";
}

sub _validate_cpuser {
    my ($cpuser) = @_;

    if ( !$cpuser ) {
        require Cpanel::Exception;
        die Cpanel::Exception::create( 'MissingParameter', 'You must specify the username.' );
    }
    else {

        # sanity check
        Cpanel::Validate::FilesystemNodeName::validate_or_die($cpuser);

        require Cpanel::AcctUtils::Account;
        if ( !Cpanel::AcctUtils::Account::accountexists($cpuser) ) {
            require Cpanel::Exception;
            die Cpanel::Exception::create( 'UserNotFound', [ name => $cpuser ] );
        }
        elsif ( $cpuser eq 'root' ) {
            die Cpanel::Exception::create( 'InvalidParameter', 'This interface does not manage [asis,MySQL]/[asis,MariaDB] grants for “[_1]”.', ['root'] );
        }
    }

    return;
}

sub _get_default_mysql_grants {
    my ( $self, $password ) = @_;

    require Cpanel::DB::Utils;
    require Cpanel::Mysql::Hosts;
    require Cpanel::MysqlUtils::Quote;
    require Cpanel::MysqlUtils::Password;

    my $dbowner   = Cpanel::DB::Utils::username_to_dbowner( $self->{'_cpuser'} );
    my $dbowner_q = Cpanel::MysqlUtils::Quote::quote($dbowner);

    my @hosts = keys %{ Cpanel::Mysql::Hosts::get_hosts_lookup( $self->{'_cpuser'} ) };

    my $digest   = Cpanel::MysqlUtils::Password::native_password_hash($password);
    my $digest_q = Cpanel::MysqlUtils::Quote::quote($digest);

    my @grants = map {
        my $host_q = Cpanel::MysqlUtils::Quote::quote($_);
        sprintf( $DEFAULT_MYSQL_FORMAT, $dbowner_q, $host_q );
    } @hosts;

    return { $dbowner => \@grants };
}

sub _get_default_postgresql_grants {
    my ( $self, $password ) = @_;

    require Cpanel::DB::Utils;
    require Cpanel::PostgresUtils::Authn;
    require Cpanel::PostgresUtils::Quote;

    my $dbowner = Cpanel::DB::Utils::username_to_dbowner( $self->{'_cpuser'} );

    # NB: Leading “md5” is a magic string that PostgreSQL recognizes as
    # an indicator that this is a pre-hashed password that should be
    # stored directly. That’s what we want.
    #
    # (cf. https://www.postgresql.org/docs/10/static/sql-createrole.html)
    #
    my $pwhash = Cpanel::PostgresUtils::Authn::create_md5_user_password_hash( $dbowner, $password );

    my $sql = sprintf(
        $DEFAULT_PGSQL_FORMAT,
        Cpanel::PostgresUtils::Quote::quote_identifier($dbowner),
        Cpanel::PostgresUtils::Quote::quote($pwhash),
    );

    return { $dbowner => [$sql] };
}

1;
