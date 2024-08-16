package Cpanel::PostgresAdmin::Basic;

# cpanel - Cpanel/PostgresAdmin/Basic.pm           Copyright 2022 cPanel, L.L.C.
#                                                           All rights reserved.
# copyright@cpanel.net                                         http://cpanel.net
# This code is subject to the cPanel license. Unauthorized copying is prohibited

use strict;
use warnings;

=encoding utf-8

=head1 NAME

Cpanel::PostgresAdmin::Basic - A subset of Cpanel::PostgresAdmin functionality intended for use with pkgacct

=head1 SYNOPSIS

    use Cpanel::PostgresAdmin::Basic ();

    my $ob = Cpanel::PostgresAdmin::Basic->new( { 'cpconf' => $cpconf, 'cpuser' => $user, 'ERRORS_TO_STDOUT' => 1 } );

=cut

use parent qw(
  Cpanel::DBAdmin
);

use Try::Tiny;
use Cpanel::DB::Utils                                 ();
use Cpanel::Exception                                 ();
use Cpanel::LoadModule                                ();
use Cpanel::LocaleString                              ();
use Cpanel::PostgresUtils::Quote                      ();
use Cpanel::PostgresUtils::PgPass                     ();
use Cpanel::Session::Constants                        ();
use Whostmgr::Accounts::Suspension::Postgresql::Utils ();

our $VERSION = 1.1;

#START CONSTANTS
our $NO_UPDATE_PRIVS  = 1;
our $SKIP_OWNER_CHECK = 1;

our $HASHED_PASSWORD_PREFIX = 'md5';

#END CONSTANTS

my $REMOTE_PGSQL = 0;    # PAM NOW USED INSTEAD, HOWEVER IF WE SUPPORT REMOTE PGSQL IN THE FUTURE...

#Docs recommend using the "postgres" as a "default" login DB.
my $DEFAULT_LOGIN_DATABASE = 'postgres';

sub DB_ENGINE { return 'postgresql' }

sub _map_dbtype {
    return 'PGSQL';
}

sub new {
    my ( $class, $ref ) = @_;
    my $self = {};

    if ($ref) {
        $self->{'ERRORS_TO_STDOUT'}   = $ref->{'ERRORS_TO_STDOUT'} || 0;
        $self->{'cpuser'}             = $ref->{'cpuser'};
        $self->{'_quiet_get_dbh'}     = $ref->{'quiet_get_dbh'};
        $self->{'allow_create_dbmap'} = $ref->{'allow_create_dbmap'};
    }
    $self->{'cpuser'} ||= $Cpanel::user;

    require Cpanel::Logger;
    $self->{'logger'} ||= Cpanel::Logger->new();

    my $pgpass = Cpanel::PostgresUtils::PgPass::pgpass();
    bless( $self, $class );

    if ( $pgpass && ref $pgpass ) {
        my ($pguser) = $self->{'user'} = Cpanel::PostgresUtils::PgPass::getpostgresuser();
        if ( $self->{'user'} ) {
            $self->{'dbpass'}   = $pgpass->{$pguser}{'password'};
            $self->{'dbserver'} = $self->{'host'} || 'localhost';

            $self->_set_super_dbh(
                $self->{'dbserver'},
                $DEFAULT_LOGIN_DATABASE,
                $self->{'user'},
                $self->{'dbpass'},
            );

            if ( $self->{'dbh'} && ref $self->{'dbh'} ) {
                $self->{'haspostgresso'} = 1;
            }
            else {
                return;
            }

        }
    }

    $self->_set_pid();

    return ($self);
}

#"yin" to Cpanel::PostgresAdmin::Restore's "yang".
sub fetchsql_users {
    my ($self) = @_;

    my %USERS = $self->listuserspasswds();

    #Ensure that we back up accounts UNSUSPENDED.
    $_ && s<\Q$Whostmgr::Accounts::Suspension::Postgresql::Utils::SUSPEND_SUFFIX\E\z><> for values %USERS;

    my @STATEMENTS;
    foreach my $user ( sort keys %USERS ) {
        push @STATEMENTS, qq{CREATE USER } . $self->escape_pg_identifier($user) . qq{ WITH PASSWORD } . $self->quote( $USERS{$user} ) . qq{;\n};
    }

    return \@STATEMENTS;
}

sub dumpsql_users {
    my ($self) = @_;
    print join( '', @{ $self->fetchsql_users() } );
    return;
}

#"yin" to Cpanel::PostgresAdmin::Restore's "yang".
sub fetchsql_grants {
    my ($self)  = @_;
    my @DBS     = $self->listdbs();
    my %DBUSERS = $self->listusersindb();

    my @STATEMENTS;
    foreach my $db (@DBS) {
        my @dbusers = $DBUSERS{$db} ? sort @{ $DBUSERS{$db} } : ();

        foreach my $user (
            Cpanel::DB::Utils::username_to_dbowner( $self->{'cpuser'} ),
            @dbusers
        ) {
            push @STATEMENTS, qq{GRANT } . $self->escape_pg_identifier($db) . qq{ TO } . $self->escape_pg_identifier($user) . qq{;\n};
        }
    }

    return \@STATEMENTS;
}

sub dumpsql_grants {
    my ($self) = @_;
    print join( '', @{ $self->fetchsql_grants() } );
    return;

}

sub escape_pg_identifier {
    my ( $self, $unsafe_str ) = @_;

    return Cpanel::PostgresUtils::Quote::quote_identifier($unsafe_str);
}

sub listuserspasswds {
    my ($self) = @_;

    my $map = $self->_get_map();

    my %uniq_users     = map { $_ => undef } ( $map->{'owner'}->name(), $self->listusers() );
    my $safe_user_list = join( ',', map { $self->quote($_) } keys %uniq_users );

    my %USERSPASSWDS;
    my $q = $self->{'dbh'}->prepare("SELECT usename, passwd FROM pg_shadow WHERE usename IN ($safe_user_list);");

    $q->execute();
    while ( my $data = $q->fetchrow_hashref() ) {
        if ( $data->{'usename'} !~ m{^\Q$Cpanel::Session::Constants::TEMP_USER_PREFIX\E} ) {
            $USERSPASSWDS{ $data->{'usename'} } = $data->{'passwd'};
        }
    }
    $q->finish();

    return %USERSPASSWDS;
}

sub listusers {
    my ($self) = @_;
    my $map = $self->_get_map();

    # do not list postgres user in frontend
    return grep { $_ !~ m{^\Q$Cpanel::Session::Constants::TEMP_USER_PREFIX\E} && $map->{'owner'}->name() ne $_ && lc($_) ne 'postgres' } map { $_->name() } $map->{'owner'}->dbusers();
}

sub quote {
    my ( $self, $unsafe_str ) = @_;

    return Cpanel::PostgresUtils::Quote::quote($unsafe_str);
}

sub listusersindb {
    my $self = shift;
    my %DBUSERS;

    my $map = $self->_get_map();
    foreach my $db ( $map->{'owner'}->dbs() ) {
        foreach my $user ( $db->users() ) {
            next if $user->name() =~ m{^\Q$Cpanel::Session::Constants::TEMP_USER_PREFIX\E};
            next if $user->name() eq $map->{'owner'}->name();
            push @{ $DBUSERS{ $db->name() } }, $user->name();
        }
    }

    return %DBUSERS;
}

sub destroy {
    my ($self) = @_;

    $self->clear_map();    # ensure we do not error on global destruct

    # If postgres has disconnected this will cause global
    # destruction so we must ignore SIGPIPE here.
    local $SIG{'PIPE'} = 'IGNORE';

    my @dbhs = (
        $self->{'dbh'},
        ( $self->{'_super_dbhs'} ? values %{ $self->{'_super_dbhs'} } : () ),
        ( $self->{'_user_dbhs'}  ? values %{ $self->{'_user_dbhs'} }  : () ),
    );

    for my $dbh (@dbhs) {
        try { $dbh->disconnect() };
    }

    @{$self}{qw(dbh _super_dbhs _user_dbhs)} = ();

    return;
}

sub _set_super_dbh {
    my ( $self, $dbserver, $dbname, $dbuser, $dbpass ) = @_;

    my $dbh = $self->_get_super_dbh( $dbserver, $dbname, $dbuser, $dbpass );

    $self->{'_super_dbhs'}{$dbname} = $dbh;

    return $self->{'dbh'} = $dbh;
}

#NOTE: Used in testing.
sub _get_super_dbh {
    my ( $self, $dbserver, $dbname, $dbuser, $dbpass ) = @_;

    Cpanel::LoadModule::load_perl_module('Cpanel::Postgres::Connect');
    my $dbh;

    # During DBI->connect with DBD/PgPP.pm with invalid credentials, sometimes postgres closes the pipe before
    # the connect method is finished writing all of its data. This triggers a SIG PIPE and kills the process
    # before valid error messages are printed to STDOUT. Since error messages will be printed anyway, we are
    # ignoring the pipe.
    #
    # Given we no longer use DBD::PgPP, it's possible this code should be removed.

    local $SIG{'PIPE'} = 'IGNORE';

    my $err;
    try {
        local $SIG{'__DIE__'};
        local $SIG{'__WARN__'};

        $dbh = Cpanel::Postgres::Connect::get_dbi_handle(
            db       => $dbname,
            Username => $dbuser,
            Password => $dbpass,
        );

        $self->{'driver'} = $dbh->driver();
    }
    catch {
        $err = $_;
    };

    if ($err) {
        if ( !$self->{'_quiet_get_dbh'} ) {
            die $self->_log_error_and_output_return( Cpanel::LocaleString->new( "The system failed to connect to the PostgreSQL server “[_1]” because of an error: [_2]", $dbserver, Cpanel::Exception::get_string($err) ) );
        }
    }

    return $dbh;
}

#This always produces a new DB handle.
#In production code this is cached whenever it's called.
#NOTE: This is also called from test code.
sub _get_dbh {
    my ( $self, $dbname, $dbuser, $dbpass ) = @_;

    my $dbh = $self->{'dbh'};
    $dbh &&= $dbh->clone( { database => $dbname } );
    $dbh ||= $self->_set_super_dbh( $self->{'dbserver'}, $dbname, $dbuser, $dbpass );

    #NOTE: This doesn't prevent privilege re-escalation via SET SESSION
    #AUTHORIZATION, but we can (and should) set the current user anyway.
    if ($dbh) {
        $dbh->do( 'SET ROLE ' . $dbh->quote_identifier($dbname) );
        $dbh->do( 'SET SESSION AUTHORIZATION ' . $dbh->quote_identifier($dbname) );
    }

    return $dbh;
}
1;
