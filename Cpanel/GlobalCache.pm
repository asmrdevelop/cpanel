package Cpanel::GlobalCache;

# cpanel - Cpanel/GlobalCache.pm                   Copyright 2022 cPanel, L.L.C.
#                                                           All rights reserved.
# copyright@cpanel.net                                         http://cpanel.net
# This code is subject to the cPanel license. Unauthorized copying is prohibited

use strict;

use Cpanel::JSON::FailOK ();

my $GCACHEref = {};
our $PRODUCT_CONF_DIR = '/var/cpanel';

sub get_cache_mtime {
    my ($cachename) = @_;
    if ( !exists $GCACHEref->{$cachename} ) { load_cache($cachename); }
    return $GCACHEref->{$cachename}{'mtime'};
}

sub load_cache {
    my ($cachename) = @_;
    if ( open( my $cache_fh, '<', "$PRODUCT_CONF_DIR/globalcache/$cachename.cache" ) ) {
        $GCACHEref->{$cachename} ||= {};
        my $cache_ref = $GCACHEref->{$cachename};

        require Cpanel::JSON;
        $cache_ref->{'data'} = Cpanel::JSON::FailOK::LoadFile($cache_fh);

        if ( ref $cache_ref->{'data'} eq 'HASH' ) {
            $cache_ref->{'mtime'} = ( stat($cache_fh) )[9];
        }
        else {
            $cache_ref->{'data'} = {};
        }
        close($cache_fh);
    }
    return;
}

sub cachedmcommand {    ## no critic(RequireArgUnpacking)
    my $cachename = shift;

    require Cpanel::CachedCommand;

    if ( !exists $GCACHEref->{$cachename} ) { load_cache($cachename); }
    my $cache_max_mtime = shift;
    my $key             = join( '_', @_ );
    return (
        ( exists $GCACHEref->{$cachename}{'data'}{'command'}{$key} && ( $cache_max_mtime + $GCACHEref->{$cachename}{'mtime'} ) > time() )
        ? $GCACHEref->{$cachename}{'data'}{'command'}{$key}
        : 'Cpanel::CachedCommand'->can('cachedmcommand')->( $cache_max_mtime, @_ )
    );
}

sub cachedcommand {    ## no critic(RequireArgUnpacking)
    my $cachename = shift;

    require Cpanel::CachedCommand;
    require Cpanel::StatCache;

    if ( !exists $GCACHEref->{$cachename} ) { load_cache($cachename); }
    my ( $file_mtime, $file_ctime ) = 'Cpanel::StatCache'->can('cachedmtime_ctime')->( $_[0] );
    my $key = join( '_', @_ );
    return (
        ( exists $GCACHEref->{$cachename}{'data'}{'command'}{$key} && $GCACHEref->{$cachename}{'mtime'} > $file_mtime && $GCACHEref->{$cachename}{'mtime'} > $file_ctime )
        ? $GCACHEref->{$cachename}{'data'}{'command'}{$key}
        : 'Cpanel::CachedCommand'->can('cachedcommand')->(@_)
    );
}

sub loadfile {
    my $cachename = shift;
    if ( !exists $GCACHEref->{$cachename} ) { load_cache($cachename); }
    my $file       = shift;
    my $file_mtime = shift;
    unless ( defined $file_mtime ) {
        $file_mtime = ( stat($file) )[9] || 0;
    }

    require Cpanel::LoadFile;
    return (
        ( exists $GCACHEref->{$cachename}{'data'}{'file'}{$file} && $GCACHEref->{$cachename}{'mtime'} > $file_mtime )
        ? $GCACHEref->{$cachename}{'data'}{'file'}{$file}
        : 'Cpanel::LoadFile'->can('loadfile')->($file)
    );
}

sub data {
    my $cachename = shift;
    if ( !exists $GCACHEref->{$cachename} ) { load_cache($cachename); }
    my $data       = shift;
    my $test_mtime = shift || 0;

    return ( ( exists $GCACHEref->{$cachename}{'data'}{'data'}{$data} && $GCACHEref->{$cachename}{'mtime'} > $test_mtime ) ? $GCACHEref->{$cachename}{'data'}{'data'}{$data} : undef );
}

sub clearcache {
    $GCACHEref = {};
    return;
}

sub default_product_dir {
    $PRODUCT_CONF_DIR = shift if @_;
    return $PRODUCT_CONF_DIR;
}

1;
