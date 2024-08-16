package Cpanel::DB::Map::Collection;

#                                      Copyright 2024 WebPros International, LLC
#                                                           All rights reserved.
# copyright@cpanel.net                                         http://cpanel.net
# This code is subject to the cPanel license. Unauthorized copying is prohibited.

use cPstrict;

use Cpanel::DB::Map::Reader ();
use Cpanel::Config::Users   ();

my %DB_ENGINE_CONVERSION = qw(
  MYSQL   mysql
  PGSQL   postgresql
);

#Named args:
#   db - passed to Cpanel::DB::Map constructor.
#
sub new {
    my ( $class, $args ) = @_;

    my $self = $class->init($args);
    bless $self, $class;

    $self->_load_maps();
    return $self;
}

sub init {
    my ( $class, $args ) = @_;

    my $self = {
        'db'   => $args->{'db'} || 'MYSQL',
        'maps' => {},

        #NOTE: At least one caller accesses this property directly.
        #(Cpanel::DB::Map::Collection::Index)
        'dbindex' => {},
    };
    return $self;
}

#overridden in tests
*_get_cpusers = \&Cpanel::Config::Users::getcpusers;

sub _load_maps {
    my ($self) = @_;

    $self->{'db'} = $DB_ENGINE_CONVERSION{ $self->{'db'} } || die "unknown “db”: “$self->{'db'}”";

    my @cpusers = grep { Cpanel::DB::Map::Reader::cpuser_exists($_) } $self->_get_cpusers();
    $self->{'maps'} = { map { $_ => ( $self->_make_map_for_cpuser($_) ) } @cpusers };
    foreach my $user (@cpusers) {
        my $db_map = $self->{'maps'}{$user};
        my $cpuser = $db_map->get_cpuser();

        foreach my $db ( $db_map->get_databases() ) {
            $self->{'dbindex'}{$db} = $cpuser;
        }
    }
    return;
}

sub set_db {
    my ( $self, $db ) = @_;
    return if !$db;

    $self->{'db'} = $db;
    $self->_load_maps();
    return;
}

sub _get_map_for_cpuser {
    my ( $self, $cpuser ) = @_;
    if ( exists $self->{'maps'}->{$cpuser} ) {
        return $self->{'maps'}->{$cpuser};
    }
    else {
        return $self->_make_map_for_cpuser($cpuser);
    }
}

sub _make_map_for_cpuser {
    my ( $self, $cpuser, ) = @_;

    my $map;
    my $limit = 3;

  RETRY:
    foreach my $attempt ( 1 .. $limit ) {
        eval { $map = Cpanel::DB::Map::Reader->new( 'cpuser' => $cpuser, 'engine' => $self->{'db'} ) };

        if ($@) {
            my $err = $@;
            if ( eval { $err->isa('Cpanel::Exception::Database::CpuserNotInMap') } && $attempt != $limit ) {
                sleep 1;
                next RETRY;
            }
            else {
                die $err;
            }
        }

        last RETRY;
    }
    return $map;
}

#
# Here we are called from find_by_dbuser to build a map of all the dbuser's
# owners (cpusers).   This will only be called once so subsequent calls to
# find_by_dbuser are faster.  This is a basiclly a simple memorize
#
sub _build_dbuser_map {
    my ($self) = @_;

    my $cpuser;

    # Optimized map map
    # With the map {} map {} we can avoid setting each data point and do them all at once
    # The original function is left in a comment below for testing / future development
    $self->{'dbusermaps_cache'} = {
        map {
            $cpuser = $_;
            map {
                $_ => $cpuser;    # This is what is actually going into the hashref
            } $self->{'maps'}{$_}->get_dbusers_plus_cpses()
        } keys %{ $self->{'maps'} }
    };

    # Original
    #foreach my $cpuser (keys %{$self->{'maps'}}) {
    #    foreach my $dbuser (keys %{$self->{'maps'}{$cpuser}->{'stash'}{$self->{'db'}}->{'dbusers'}}) {
    #        $self->{'dbusermaps_cache'}{$dbuser}=$cpuser;
    #    }
    #}
    return;
}

#This returns a DB map for the given username.
#Note that the username can be for a cpuser OR for a dbuser.
#
#NOTE: Consider using Cpanel::DB::Map::Utils::get_cpuser_for_engine_dbuser(),
#which will be much faster for most cases.
#
sub find_by_dbuser {
    my ( $self, $dbuser ) = @_;

    #This actually checks to see if there is a cPanel user with the
    #passed-in name.
    return $self->{'maps'}->{$dbuser} if exists $self->{'maps'}->{$dbuser};

    $self->_build_dbuser_map() if !exists $self->{'dbusermaps_cache'};

    return exists $self->{'dbusermaps_cache'}{$dbuser} ? $self->{'maps'}->{ $self->{'dbusermaps_cache'}{$dbuser} } : undef;
}

sub find_by_db {
    my ( $self, $db ) = @_;
    $db =~ s/\\//g;

    my $cpuser = $self->{'dbindex'}{$db};
    return $cpuser ? $self->_get_map_for_cpuser($cpuser) : undef;
}

1;

=pod

=head1 CONSTANTS

    For mysql: Cpanel::DB::MYSQL
    For Postgresql: Cpanel::DB::PGSQL

=head1 METHODS

=over

=item new(HASHREF)

=over 12

=item KEY: db

Instantiate new Collection object. Use database name constants for supported database values.

=back

=item find_by_dbuser($dbuser)

Return the Cpanel::DB::Map::Reader object for the given dbuser that is found in the map

=item find_by_db($db)

Return the Cpanel::DB::Map::Reader object of the given database that is found in the map

=back

=cut
