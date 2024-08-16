package Cpanel::Crypt::GPG::VendorKeys::TimestampCache;

# cpanel - Cpanel/Crypt/GPG/VendorKeys/TimestampCache.pm
#                                                  Copyright 2022 cPanel, L.L.C.
#                                                           All rights reserved.
# copyright@cpanel.net                                         http://cpanel.net
# This code is subject to the cPanel license. Unauthorized copying is prohibited

use strict;
use warnings;

use Cpanel::CachedDataStore ();

sub _cache_file {
    return '/var/cpanel/gpg/timestamp.cache';
}

sub new {
    my ($obj) = @_;
    my $self = {};
    bless $self, $obj;

    $self->{'cache'} = _load_cache();

    return $self;
}

sub _load_cache {
    return Cpanel::CachedDataStore::fetch_ref( _cache_file() );
}

sub _save_cache {
    my ($cache_data) = @_;
    return Cpanel::CachedDataStore::savedatastore( _cache_file(), { mode => 0600, data => $cache_data } );
}

sub update_cache {
    my ( $self, %args ) = @_;

    return 0 if !$args{'mirror'} || !$args{'url'};

    $self->{'cache'}->{ $args{'mirror'} }{ $args{'url'} } = { date_downloaded => time, signature_date => $args{'create_time'} };

    return _save_cache( $self->{'cache'} );
}

sub check_cache_for_rollback {
    my ( $self, %args ) = @_;

    my $cached_time = $self->{'cache'}->{ $args{'mirror'} }{ $args{'url'} }{'signature_date'};
    my $new_time    = $args{'create_time'};
    if ( defined $cached_time && $cached_time > $new_time ) {

        # rollback detected
        return 1;
    }
    else {
        return 0;
    }
}

sub cleanup_signature_cache {
    my ( $self, %args ) = @_;

    # This is the time a signature entry for a file will be valid in epoch seconds, it defaults to 90 days.
    # To clear the cache completely set this to zero.
    my $valid_time_window = exists $args{'valid_time_window'} ? $args{'valid_time_window'} : 7776000;
    my $current_time      = time;

    my $cache = $self->{'cache'};
    foreach my $mirror ( keys %{ $self->{'cache'} } ) {
        foreach my $file ( keys %{ $self->{'cache'}{$mirror} } ) {

            # delete old file entries
            delete $cache->{$mirror}{$file} if $current_time - $self->{'cache'}{$mirror}{$file}{'date_downloaded'} >= $valid_time_window;

        }

        # delete the mirror if it is empty
        delete $cache->{$mirror} if !scalar keys %{ $cache->{$mirror} };
    }

    return _save_cache($cache);
}

1;
