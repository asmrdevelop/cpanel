package Cpanel::DB::Map::Collection::Index;

# cpanel - Cpanel/DB/Map/Collection/Index.pm       Copyright 2022 cPanel, L.L.C.
#                                                           All rights reserved.
# copyright@cpanel.net                                         http://cpanel.net
# This code is subject to the cPanel license. Unauthorized copying is prohibited

#----------------------------------------------------------------------
# This abstracts a DB => dbowner hash cache.
#
# bin/dbowner is what writes the cache file to the disk. If the disk cache
# isn't available or is invalid, this will rebuild the index, but WITHOUT
# saving it!
#----------------------------------------------------------------------

use strict;

use Cpanel::Transaction::File::JSONReader ();    # PPI USE OK -- used by _CACHE_FILE_LOADER_CLASS
use Cpanel::ConfigFiles                   ();
use Cpanel::LoadModule                    ();
use Cpanel::Logger                        ();

my $WARN_ON_DBINDEX_CACHE_AGE = 60 * 60 * 4;     #4 hours

sub _cache_file_path {
    return "$Cpanel::ConfigFiles::DATABASES_INFO_DIR/dbindex.db.json";
}

#$args_hr is:
#
#   db          - string, the DB engine, as passed to Cpanel::DB::Map
#   warn_age    - boolean, whether to warn when the dbindex file is out of date
#   origin      - string, the general name of the binary or area of the product making
#                 the call to this package for use with the warn_age notification. Currently,
#                 only used if a true value for warn_age is passed.
#
sub new {
    my ( $class, $args_hr ) = @_;

    my $self = $class->_init($args_hr);

    $self->_load_dbindex();
    return $self;
}

my @allowable_engines = qw(
  MYSQL
  PGSQL
);

sub _init {
    my ( $class, $args ) = @_;

    if ( !grep { $_ eq ( $args->{'db'} || q<> ) } @allowable_engines ) {
        die "“db” must be one of: @allowable_engines";
    }

    my $self = {
        'dbindex'  => {},
        'db'       => $args->{'db'},
        'warn_age' => $args->{'warn_age'},
        'origin'   => $args->{'origin'} || __PACKAGE__,
    };

    return bless $self, $class;
}

#for tests
our $_CACHE_FILE_LOADER_CLASS = 'Cpanel::Transaction::File::JSONReader';

my $logger;

sub _load_dbindex {
    my ($self) = @_;

    my $cache_file_path = _cache_file_path();

    my $dbindex;

    if ( -e $cache_file_path ) {
        if ( $self->{'warn_age'} && ( stat $cache_file_path )[9] + ($WARN_ON_DBINDEX_CACHE_AGE) < time() ) {
            $self->_logger()->warn("dbindex is out of date: $cache_file_path is more than four hours old. Run “/usr/local/cpanel/bin/dbindex” to update the index and fix the cron job, then run “/usr/local/cpanel/scripts/update_db_cache” to rebuild the DB cache.");
            Cpanel::LoadModule::load_perl_module('Cpanel::Notify');
            Cpanel::Notify::notification_class(
                'application'      => __PACKAGE__,
                'class'            => 'dbindex::Warn',
                'status'           => 'dbindex is out of date',
                'interval'         => 86400,                      # One day
                'constructor_args' => [
                    'cache_file_path' => $cache_file_path,
                    'origin'          => $self->{'origin'},
                ]
            );
        }

        my $data = $_CACHE_FILE_LOADER_CLASS->new(
            path => _cache_file_path(),
        );
        $dbindex = $data->get_data();
    }

    if ( 'HASH' eq ref $dbindex ) {
        $self->{'dbindex'} = $dbindex->{ $self->{'db'} };
    }
    else {
        Cpanel::LoadModule::load_perl_module('Cpanel::DB::Map::Collection');
        my $collection = Cpanel::DB::Map::Collection->new( { 'db' => $self->{'db'} } );
        $self->{'dbindex'} = $collection->{'dbindex'};
    }

    return;
}

#This actually returns the DB's cpuser-owner.
sub get_dbuser_by_db {
    my ( $self, $db ) = @_;

    die "Need db!" if !length $db;

    return $self->{'dbindex'}{$db};
}

#What you actually pass in here is a cpuser-owner, not a DB user.
sub find_dbs_by_dbuser {
    my ( $self, $dbuser ) = @_;

    die "Need dbuser!" if !length $dbuser;

    $self->_build_db_cache() if ( !exists $self->{'db_cache'} );

    return [ $self->{'db_cache'}{$dbuser} ? @{ $self->{'db_cache'}{$dbuser} } : () ];
}

sub _build_db_cache {
    my $self = shift;

    my %cache;

    foreach my $db ( keys %{ $self->{'dbindex'} } ) {
        push @{ $cache{ $self->{'dbindex'}{$db} } }, $db;
    }

    $self->{'db_cache'} = \%cache;

    return;
}

sub _logger {
    return $logger ||= Cpanel::Logger->new();
}

1;
