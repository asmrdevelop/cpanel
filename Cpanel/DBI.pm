package Cpanel::DBI;

# cpanel - Cpanel/DBI.pm                           Copyright 2022 cPanel, L.L.C.
#                                                           All rights reserved.
# copyright@cpanel.net                                         http://cpanel.net
# This code is subject to the cPanel license. Unauthorized copying is prohibited

=head1 NAME

Cpanel::DBI

=cut

#----------------------------------------------------------------------
# XXX STOP! XXX
#
#   You probably *don’t* want to use this class directly.
#
#   Consider instead:
#
#       Cpanel::DBI::Mysql
#       Cpanel::DBI::SQLite
#       Cpanel::DBI::Postgresql
#
# A wrapper class around DBI that preserves connection information.
# This simplifies intermingling command-line and DBI interactions
# with the same database server/object, e.g., when mocking the database
# for testing.
#
# This is also where we do general "good-to-haves" like defaulting
# AutoInactiveDestroy to on and making DBI throw Cpanel::Exception instances
# instead of scalars.
#----------------------------------------------------------------------

use strict;

use Try::Tiny;

my %DRIVERS_WITH_DBNAME_AS_PATH = ( 'SQLite' => 1 );

use DBI  ();
use Carp ();

# Defer calling init_install_method until we call connect
# so we do not have to pay for it for every operation
BEGIN {
    require DBI;
    my $dbi_connect      = \&DBI::connect;
    my $dbi_init_install = \&DBI::init_install_method;
    no warnings 'redefine';
    *DBI::init_install_method = sub { };
    *DBI::connect             = sub {
        if ( defined $dbi_init_install ) {

            # only call init once and avoid the CV call when not needed
            $dbi_init_install->();
            undef $dbi_init_install;
        }
        *DBI::connect = $dbi_connect;
        goto \&DBI::connect;
    };
}

use parent qw( DBI );

use Cpanel::Exception ();

#Same args as DBI::connect.
sub connect {
    my @args = @_;

    if ($Cpanel::DBI::cache::_allow_dbh_caching) {
        my $args_comparable = Cpanel::DBI::cache::_make_comparable( \@args );    # i.e. serialize in some fashion
        if ( $Cpanel::DBI::cache::_dbh_cache{$args_comparable} ) {
            return $Cpanel::DBI::cache::_dbh_cache{$args_comparable};
        }
    }

    my ( $class, $data_source, $username, $password, $attr_hr ) = @args;

    my %attrs = (
        HandleError => \&_error_handler,

        $attr_hr ? %$attr_hr : ()
    );

    my ( undef, $driver ) = $class->parse_dsn($data_source);

    #For instantiation, we need to set RaiseError to 0 so that we don't
    #trip DBI's error-throwing logic (which doesn't pay attention to
    #HandleError until there's an actual connection object).
    #
    my $dbh;
    try {
        $dbh = $class->SUPER::connect( $data_source, $username, $password, \%attrs ) or die;
    }
    catch {
        my $dbname = $attrs{'database'} // $attrs{'db'} // $attrs{'dbname'};
        if ( !defined($dbname) && $DRIVERS_WITH_DBNAME_AS_PATH{$driver} ) {
            ($dbname) = $data_source =~ m{dbname=([^:]+)};
        }

        die Cpanel::Exception::create(
            'Database::ConnectError',
            [
                error_code   => $DBI::err,
                error_string => $DBI::errstr,
                state        => $DBI::state,
                message      => $DBI::errstr,
                return_value => undef,
                dbi_driver   => $driver,
                database     => $dbname,
            ],
        );
    };

    $dbh->{'AutoInactiveDestroy'} = 1;    # perlcc requires this to be set AFTER the dbh is created
                                          # This was lost in refactoring into Cpanel::DBI
                                          # Prevents a child process from disconnect()ing the parent's session.

    if ( !length $data_source ) {
        $data_source = $ENV{'DBI_DSN'};
    }

    $dbh->_set( '_orig_pid', $$ );
    $dbh->_set( '_dsn',      $data_source );
    $dbh->_set( '_attr_hr',  \%attrs );
    $dbh->_set( '_username', $username );
    $dbh->_set( '_password', $password );

    $dbh->_set( '_driver', $driver );

    if ($Cpanel::DBI::cache::_allow_dbh_caching) {
        my $args_comparable = Cpanel::DBI::cache::_make_comparable( \@args );
        $Cpanel::DBI::cache::_dbh_cache{$args_comparable} = $dbh;
    }
    return $dbh;
}

=head2 STATIC - allow_dbh_caching(STATE)

Given a boolean value STATE, enables or disables db handle caching based on that value.

This configures the behavior of Cpanel::DBI at the package level within the current process.

This is not an instance method.

Example:

  Cpanel::DBI->allow_dbh_caching(1);

=cut

sub allow_dbh_caching {
    my @args = @_;
    if ( 2 != @args ) {
        Carp::confess('Developer error: allow_dbh_caching() called with wrong number of arguments');
    }

    ( undef, $Cpanel::DBI::cache::_allow_dbh_caching ) = @args;
    clear_dbh_cache() if !$Cpanel::DBI::cache::_allow_dbh_caching;

    return;
}

=head2 STATIC - clear_dbh_cache()

Clears the db handle cache. This is only needed if you have also enabled dbh caching, which
is disabled by default.

This is not an instance method.

Example:

  Cpanel::DBI->clear_dbh_cache();

=cut

sub clear_dbh_cache {
    %Cpanel::DBI::cache::_dbh_cache = ();
    return;
}

sub _error_handler {
    my ( $str, $dbh, $retval ) = @_;

    if ( $dbh->{'RaiseError'} ) {
        die $dbh->_create_exception( $str, $retval );
    }

    return;
}

sub _create_exception {
    my ( $self, $str, $retval ) = @_;

    #Both DB handles and statement handles can end up here.
    my $dbh = $self->isa('DBI::db') ? $self : $self->{'Database'};

    return Cpanel::Exception::create(
        'Database::Error',
        [
            error_code   => scalar $self->err(),
            error_string => scalar $self->errstr(),
            state        => scalar $self->state(),
            database     => $dbh->database(),
            message      => $str,
            return_value => $retval,
            dbi_driver   => $dbh->_get('_driver'),
        ],
    );
}

package Cpanel::DBI::db;

use DBI ();    # for perlcc
use DBI ();    # for perlcc

use parent -norequire, qw( DBI::db );

my $PACKAGE = __PACKAGE__;

*_create_exception = *Cpanel::DBI::_create_exception;

sub _set {
    my ( $self, $key, $value ) = @_;

    #cf. DBI docs for storing private information in DBI handles.
    return $self->{"private_$PACKAGE"}{$key} = $value;
}

sub _get {
    my ( $self, $key ) = @_;

    return $self->{"private_$PACKAGE"}{$key};
}

sub dsn {
    my ($self) = @_;

    return $self->_get('_dsn');
}

sub driver {
    my ($self) = @_;

    return $self->_get('_driver');
}

sub original_pid {
    my ($self) = @_;

    return $self->_get('_orig_pid');
}

sub username {
    my ($self) = @_;

    return $self->_get('_username');
}

sub password {
    my ($self) = @_;

    return $self->_get('_password');
}

#This returns the original database. It’s possible for a DB handle
#(e.g., MySQL) to switch databases within the same connection. For
#an up-to-date value, use $dbh->{'Name'}. Of course, not all DBD modules
#support this attribute … DBD::mysql, for instance. :-<
sub database {
    my ($self) = @_;

    my $attr_hr = $self->attributes();

    for my $key (qw(database  db  dbname)) {
        return $attr_hr->{$key} if defined $attr_hr->{$key};
    }

    return undef;
}

sub attributes {
    my ($self) = @_;

    return { %{ $self->_get('_attr_hr') } };
}

#Per the DBI docs, using clone() without a hashref is deprecated.
#That's kind of silly, though.
#
#We also need to copy this subclass's attributes to the cloned object.
#
#As a convenience, we also die() if the handle to be cloned is already
#disconnected. It's probably (?) always an error.
sub clone {
    my ( $self, $attrs_hr ) = @_;

    #The possibility that this would ever be useful seems miniscule compared
    #to the benefits of catching this problem.
    if ( !$self->ping() ) {
        die "clone($self) on disconnected handle (" . $self->errstr() . ")";
    }

    my $clone = $self->SUPER::clone( $attrs_hr || {} );

    #So that set()ting on the clone doesn't affect the original
    #or vice-versa.
    if ( $self->{"private_$PACKAGE"} ) {
        $clone->{"private_$PACKAGE"} = { %{ $self->{"private_$PACKAGE"} } };
    }

    $clone->{'AutoInactiveDestroy'} = 1;    # perlcc requires this to be set AFTER the dbh is created
                                            # This was lost in refactoring into Cpanel::DBI
                                            # Prevents a child process from disconnect()ing the parent's session.

    return $clone;
}

package Cpanel::DBI::st;

use DBI ();    # for perlcc

use parent -norequire, qw( DBI::st );

*_create_exception = *Cpanel::DBI::_create_exception;

package Cpanel::DBI::cache;

use Cpanel::JSON ();

our $_allow_dbh_caching;
our %_dbh_cache;
END { undef %_dbh_cache }

sub _make_comparable {
    return Cpanel::JSON::Dump(shift);
}

1;
