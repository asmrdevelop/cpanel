package Cpanel::User::Cache;

# cpanel - Cpanel/User/Cache.pm                    Copyright 2023 cPanel, L.L.C.
#                                                           All rights reserved.
# copyright@cpanel.net                                         http://cpanel.net
# This code is subject to the cPanel license. Unauthorized copying is prohibited

use cPstrict;

use parent qw{ Cpanel::SQLite::UserData };

use constant FILENAME => q[cache.sqlite];

=encoding utf8

=head1 NAME

Cpanel::User::Cache

=head1 SYNOPSIS

    use Cpanel::User::Cache ();

    my $cache = Cpanel::User::Cache->new();          # use ~/.cpanel/cache.sqlite file

    # alternatively you can set your own file location
    $cache = Cpanel::User::Cache->new( filename => q[store/here.sqlite] ); # use ~/.cpanel/store/here.sqlite

    $cache->store( mykey => q[value] );

    my $expires_at = time() + 3_600;
    $cache->store( mykey => q[value], $expires_at );

    my $value = $cache->retrieve( q[mykey] );

    $cache->remove( q[mykey] );

=head1 DESCRIPTION

This is used to store some key / value entries in one SQLite database located in the user home directory.

=head1 FUNCTIONS

=head2 $self->retrieve( $name )

Retrieve a value stored in the SQLite table identified  by the key '$name'.
Returns 'undef' when the entry does not exist.

=cut

sub retrieve ( $self, $name ) {

    my $data;
    eval {
        my $h = $self->db->select( 'caches', [qw{ data cached_at expires_at}], { name => $name, expires_at => { '>', time() } } )->hash;

        $data = $self->from_json( $h->{data} ) if ref $h && defined $h->{data};
        if ( ref $data eq 'HASH' ) {
            $data->{_cache_expires_at} = int $h->{expires_at};
            $data->{_cache_cached_at}  = int $h->{cached_at};
        }

    };

    return $data;
}

=head2 $self->store( $name, $value, $expires_at = 0 )

Store a { key / value } pair in the SQLite table.
When expires_at is unset, it's automatically set to a random value
betwen 600 and 720 seconds after the current time.

=cut

sub store ( $self, $name, $data, $expires_at = 0 ) {

    my $now       = time();
    my $cached_at = $now;
    $expires_at ||= $now + 600 + int( rand(120) );

    $data = $self->to_json($data);

    my $results = eval {
        my @where = ( data => $data, cached_at => $cached_at, expires_at => $expires_at );
        $self->db->insert(
            'caches',
            { name        => $name, @where },
            { on_conflict => [ 'name' => {@where} ] },
        );
    };

    $self->_autopurge_cache();

    return !!$results;
}

=head2 $self->remove( $name )

Delete from the 'caches' table the value for the 'key' $name.

=cut

sub remove ( $self, $name ) {
    return eval { $self->db->delete( 'caches', { name => $name }, { limit => 1 } )->rows };
}

sub _autopurge_cache ( $self, $expires_at = undef ) {

    $expires_at //= time();

    my $ok = eval { $self->db->delete( 'caches', { expires_at => { '<=', $expires_at } } ) };

    return !!$ok;
}

1;

__DATA__

@@ migrations

-- 1 up

create table caches (
    id          INTEGER PRIMARY KEY,
    name        TEXT NOT NULL UNIQUE,
    data        BLOB NOT NULL,
    cached_at   INTEGER,
    expires_at  INTEGER
);

-- 1 down

drop table caches;
