package Cpanel::DB::Map::Reader;

# cpanel - Cpanel/DB/Map/Reader.pm                 Copyright 2022 cPanel, L.L.C.
#                                                           All rights reserved.
# copyright@cpanel.net                                         http://cpanel.net
# This code is subject to the cPanel license. Unauthorized copying is prohibited

#----------------------------------------------------------------------
# NOTE: This module provides read-only access to the DB map.
# It supports a limited subset of “queries” on the data.
# For read/write access, see Cpanel::DB::Map.
#
# Ideally, this would be a base class on top of which the read/write
# logic to access the DB map would sit; however, since that logic
# is used all over the code base in long-existing implementations, for now
# this is just an independent reader class.
#
# There are some semantic differences between this module and the read/write
# module; for example, Cpanel::DB::Map defaults to MySQL, whereas this module
# requires (by design) that the caller specify a DB engine. Also, the strings
# used to identify the DB engine are different; this module's strings are meant
# to correspond with newer API calls.
#----------------------------------------------------------------------

use strict;
use warnings;

use Cpanel::ArrayFunc::Uniq               ();
use Cpanel::Autodie                       ();
use Cpanel::ConfigFiles                   ();
use Cpanel::Context                       ();
use Cpanel::DB::Map::Path                 ();
use Cpanel::Exception                     ();
use Cpanel::LoadModule                    ();
use Cpanel::Session::Constants            ();
use Cpanel::Transaction::File::JSONReader ();
use Cpanel::DB::Map::Reader::Exists       ();
my %ENGINE_IN_DATASTORE = qw(
  mysql       MYSQL
  postgresql  PGSQL
);

my @REQUIRED_ENGINE_KEYS = qw(dbs dbusers);

*cpuser_exists = *Cpanel::DB::Map::Reader::Exists::cpuser_exists;

sub get_all_cpusers {
    Cpanel::Context::must_be_list();

    Cpanel::Autodie::opendir( my $dfh, $Cpanel::ConfigFiles::DATABASES_INFO_DIR );

    #It's a little "smudgey" to look for YAML files here instead of putting
    #that logic in Convert.pm; if we can find a cleaner, similarly performant
    #way of implementing this later, let's do it.
    return Cpanel::ArrayFunc::Uniq::uniq( map { m<\A(.+)\.(?:json|yaml)\z> ? $1 : () } readdir $dfh );
}

#STATIC
#NOTE: Called from tests.
*_data_file = \&Cpanel::DB::Map::Path::data_file_for_username;

#STATIC
sub _find_old_data {
    my ($cpuser) = @_;

    Cpanel::LoadModule::load_perl_module('Cpanel::DB::Map::Convert');

    return Cpanel::DB::Map::Convert::read_old_dbmap($cpuser);
}

#STATIC
sub _get_dsengine_for_engine {
    my ($engine) = @_;

    my $ds_engine = $ENGINE_IN_DATASTORE{$engine};

    if ( !$ds_engine ) {
        die "Invalid engine: “$engine”";
    }

    return $ds_engine;
}

#----------------------------------------------------------------------

#accepts key/value pairs:
#
#   cpuser - required
#
#   engine - either 'mysql' or 'postgresql'
#            Note that the set_engine() method can change this value
#            for an instantiated object.
#
sub new {
    my ( $class, %opts ) = @_;

    my $ds_engine = _get_dsengine_for_engine( $opts{'engine'} );

    my $data_file = _data_file( $opts{'cpuser'} );

    my $data;

    if ( -s $data_file ) {
        my $trans = Cpanel::Transaction::File::JSONReader->new(
            path => $data_file,
        );
        $data = $trans->get_data();
    }

    if ( 'HASH' ne ref $data ) {
        $data = _find_old_data( $opts{'cpuser'} );
    }

    if ( !$data ) {
        die Cpanel::Exception::create( 'Database::CpuserNotInMap', [ name => $opts{'cpuser'} ] );
    }

    my $self = {
        _engine => $ds_engine,
        _data   => $data,
        _cpuser => $opts{'cpuser'},
    };

    return bless $self, $class;
}

sub _get_engine_data {
    my $self = shift;

    foreach my $required (@REQUIRED_ENGINE_KEYS) {

        # Its possible postgres was not installed on the source
        # machine
        $self->{'_data'}{ $self->{'_engine'} }{$required} ||= {};
    }

    return $self->{'_data'}{ $self->{'_engine'} };
}

#Returns a list.
#
#This function's return will not include Cpanel::Session temp users.
#
sub get_dbusers_for_database {
    my ( $self, $db ) = @_;

    Cpanel::Context::must_be_list();

    my $dbusers_element = $self->_get_engine_data()->{'dbusers'};

    my @users;
    for my $user ( keys %$dbusers_element ) {
        next if $user =~ m{^\Q$Cpanel::Session::Constants::TEMP_USER_PREFIX\E};
        push @users, $user if exists $dbusers_element->{$user}->{'dbs'}->{$db};
    }

    return @users;
}

#Returns a list of databases that the dbuser is mapped to.
#
sub get_databases_for_dbuser {
    my ( $self, $dbuser ) = @_;

    Cpanel::Context::must_be_list();

    my $dbuser_element = $self->_get_engine_data()->{'dbusers'}->{$dbuser};
    return ( $dbuser_element ? keys %{ $dbuser_element->{'dbs'} } : () );
}

#Returns a hashref (hash REFERENCE, not a list) of: {
#   dbname => [ dbuser1, dbuser2, .. ],
#}
#
#This function's return will not include Cpanel::Session temp users.
#
sub get_dbusers_for_all_databases {
    my ($self) = @_;

    my $dbusers_element = $self->_get_engine_data()->{'dbusers'};

    my %dbusers;

    for my $dbuser ( keys %$dbusers_element ) {
        next if $dbuser =~ m{^\Q$Cpanel::Session::Constants::TEMP_USER_PREFIX\E};

        for my $db ( keys %{ $dbusers_element->{$dbuser}{'dbs'} } ) {
            push @{ $dbusers{$db} }, $dbuser;
        }
    }

    #Go through and create an array for every DB that has no assigned DBusers.
    for my $db ( keys %{ $self->_get_engine_data()->{'dbs'} } ) {
        $dbusers{$db} ||= [];
    }

    return \%dbusers;
}

sub database_exists {
    my ( $self, $dbname ) = @_;

    return $self->_get_engine_data()->{'dbs'}{$dbname} ? 1 : 0;
}

sub dbuser_exists {
    my ( $self, $dbuser ) = @_;

    return $self->_get_engine_data()->{'dbusers'}{$dbuser} ? 1 : 0;
}

#This function's return will not include Cpanel::Session temp users.
#
sub get_dbusers {
    my ($self) = @_;

    Cpanel::Context::must_be_list();

    return grep { !m<\A\Q$Cpanel::Session::Constants::TEMP_USER_PREFIX\E> } $self->get_dbusers_plus_cpses();
}

#This returns every single DB user in the DB map, including
#temporary Cpanel::Session users.
#
sub get_dbusers_plus_cpses {
    my ($self) = @_;

    Cpanel::Context::must_be_list();

    return if !$self->_get_engine_data();

    return keys %{ $self->_get_engine_data()->{'dbusers'} };
}

sub get_databases {
    my ($self) = @_;

    Cpanel::Context::must_be_list();

    return if !$self->_get_engine_data();

    return keys %{ $self->_get_engine_data()->{'dbs'} };
}

sub get_cpuser {
    my ($self) = @_;

    return $self->{'_cpuser'};
}

sub set_engine {
    my ( $self, $engine ) = @_;

    return $self->{'_engine'} = _get_dsengine_for_engine($engine);
}

1;
