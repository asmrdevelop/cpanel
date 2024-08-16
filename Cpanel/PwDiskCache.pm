package Cpanel::PwDiskCache;

# cpanel - Cpanel/PwDiskCache.pm                   Copyright 2022 cPanel, L.L.C.
#                                                           All rights reserved.
# copyright@cpanel.net                                         http://cpanel.net
# This code is subject to the cPanel license. Unauthorized copying is prohibited

#----------------------------------------------------------------------
# A disk cache for pw lookups. Cpanel::PwCache contains a memory cache;
# this module stores those cache values in simple disk-based datastores.
# It ends up being faster to read these than to parse pw.
#
# XXX: This module is pretty tightly coupled with Cpanel::PwCache.
# It would be good to rebuild these two modules at some point.
#----------------------------------------------------------------------

use strict;
use Cpanel::PwCache                      ();
use Cpanel::PwCache::Validate            ();
use Cpanel::PwCache::Load                ();
use Cpanel::PwCache::Helpers             ();
use Cpanel::Debug                        ();
use Cpanel::JSON                         ();
use Cpanel::AdminBin::Serializer::FailOK ();
use Cpanel::FileUtils::Write             ();

# use Cpanel::Logger ();

our $VERSION = '1.01';

#FIXME: Move everything that deals with this into
#Cpanel::PwDiskCache::Utils. Leaving this here in the interest of
#having a smaller commit for 11.48.
our $cachedir = '/var/cpanel/pw.cache';

my %SECURE_PWCACHE;

sub TIEHASH {
    my ( $pkg, %opts ) = @_;
    return bless { 'opts' => \%opts }, $pkg;
}

#NOTE: The only thing that seems to call this is the FETCH routine below;
#maybe we shouldn't expose this logic publicly?
#
sub STORE {
    my ( $self, $key, $dt ) = @_;
    return if $> != 0;

    # Cpanel::Logger::cplog("STORE called for $key",'info',__PACKAGE__, 1);
    if ( $Cpanel::Debug::level > 3 ) {
        print STDERR __PACKAGE__ . "::STORE for key $key.\n";
    }

    $key =~ tr{/}{}d;
    return if ( !ref $dt || !scalar keys %{$dt} || !ref $dt->{'contents'} || $#{ $dt->{'contents'} } == -1 );

    # Don't write caches for UID 0 users other than root, as it causes
    # widespread breakage.
    return if $dt->{'contents'}->[2] == 0 && $dt->{'contents'}->[0] ne "root";

    # No need to lock as  Cpanel::JSON has sanity checks and this is just a cache
    # If we fail to fetch the cache we just fallback to reading the password file
    # anyways
    #

    $dt->{'VERSION'} = $VERSION;

    if ( !-e $cachedir ) {
        mkdir $cachedir, 0700;
    }

    if ( Cpanel::FileUtils::Write::overwrite( $cachedir . '/' . $key, Cpanel::JSON::Dump($dt), 0600 ) ) {

        # Make sure the key file is linked to the uid or user key file
        # Example:  0:root should always be a hard link to 2:0
        my $twin_key = ( index( $key, '0:' ) == 0 ? '2:' . $dt->{'contents'}->[2] : '0:' . $dt->{'contents'}->[0] );

        my ( $key_file_inode, $key_file_nlinks ) = ( stat( $cachedir . '/' . $key ) )[ 1, 3 ];
        my $twin_inode = ( stat( $cachedir . '/' . $twin_key ) )[1];

        if ( defined $key_file_nlinks && defined $twin_inode && -f $cachedir . '/' . $twin_key && $key_file_inode == $twin_inode && $key_file_nlinks >= 2 ) {    #hard link
            return 1;
        }
        else {
            unlink( $cachedir . '/' . $twin_key );
            return 1 if link( $cachedir . '/' . $key, $cachedir . '/' . $twin_key );
        }
    }
    return;
}

sub FETCH {
    my ( $self, $key ) = @_;
    $key =~ tr{/}{}d;

    # This will only use the cach eif it exists
    my $obj = Cpanel::PwCache::Load::load_cached($key);
    return $obj if $obj && $obj->{'contents'}->[1] ne 'x';

    $obj = $self->_read_pwdisk_cache($key);
    if ( $obj && $obj->{'contents'}->[1] ne 'x' ) {
        Cpanel::PwCache::_cache_pwdata( $obj->{'contents'} );
        return $obj;
    }

    if ( $Cpanel::Debug::level > 3 ) {
        print STDERR __PACKAGE__ . "::FETCH did not return valid data, doing load.\n";
    }
    $obj = Cpanel::PwCache::Load::load($key);

    $self->STORE( $key, $obj ) if $obj;

    return $obj;
}

sub _read_pwdisk_cache {
    my ( $self, $key ) = @_;

    # Cpanel::Logger::cplog( "FETCH called for $key", 'info', __PACKAGE__, 1);
    if ( open( my $fh, '<', "$cachedir/$key" ) ) {

        # we do not care about using safeopen as if its a partial write  Cpanel::JSON will just not loaded it and we will manually retrieve it from the password file
        # if its invalid data it will be caught by the validate callback anyways
        my $ref = Cpanel::AdminBin::Serializer::FailOK::LoadFile( $fh, "$cachedir/$key" );
        if ( $ref && ref $ref eq 'HASH' && $ref->{'VERSION'} && $ref->{'VERSION'} eq $VERSION && Cpanel::PwCache::Validate::validate( $key, $ref ) ) {
            if ( $Cpanel::Debug::level > 3 ) {
                print STDERR __PACKAGE__ . "::FETCH said key $key was valid.\n";
            }

            return $ref;
        }
    }
    return;
}

sub EXISTS {
    my ( $self, $key ) = @_;
    $key =~ tr{/}{}d;

    # Cpanel::Logger::cplog( "EXISTS called for $key", 'info', __PACKAGE__, 1);
    return ( -e $cachedir . '/' . $key ) ? 1 : 0;
}

sub enable {
    tie %SECURE_PWCACHE, 'Cpanel::PwDiskCache' or die "Could not init password cache";
    Cpanel::PwCache::Helpers::init( \%SECURE_PWCACHE, 1 );    #do not cache uids
}

sub disable {
    untie %SECURE_PWCACHE;
    Cpanel::PwCache::Helpers::deinit();
}

1;
