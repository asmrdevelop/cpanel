package Cpanel::PwCache::Validate;

# cpanel - Cpanel/PwCache/Validate.pm              Copyright 2022 cPanel, L.L.C.
#                                                           All rights reserved.
# copyright@cpanel.net                                         http://cpanel.net
# This code is subject to the cPanel license. Unauthorized copying is prohibited

use strict;

use Cpanel::Debug            ();
use Cpanel::PwCache::Helpers ();
use Cpanel::PwCache::Cache   ();

sub validate {
    my ( $pwkey, $record ) = @_;

    if ( exists $record->{'contents'} && ref $record->{'contents'} ne 'ARRAY' && scalar @{ $record->{'contents'} } ) { return 0; }
    my ( $stored_mtime, $hstored_mtime ) = ( $record->{'cachetime'}, $record->{'hcachetime'} );

    my $SYSTEM_CONF_DIR = Cpanel::PwCache::Helpers::default_conf_dir();

    my ( $passwdmtime, $hpasswdmtime ) = ( ( stat("$SYSTEM_CONF_DIR/passwd") )[9], ( -r "$SYSTEM_CONF_DIR/shadow" ? ( stat(_) )[9] : 0 ) );

    Cpanel::Debug::log_debug( "called for record " . dump_rec($record) ) if ( $Cpanel::Debug::level > 3 );

    if (   $hstored_mtime
        && $stored_mtime
        && $hpasswdmtime == $hstored_mtime
        && $passwdmtime == $stored_mtime ) {
        my $pwcache_ref = Cpanel::PwCache::Cache::get_cache();
        if (  !$pwcache_ref->{$pwkey}->{'cachetime'}
            || $pwcache_ref->{$pwkey}->{'cachetime'} != $stored_mtime
            || $pwcache_ref->{$pwkey}->{'hcachetime'} != $hstored_mtime ) {
            @{ $pwcache_ref->{$pwkey} }{ 'hcachetime', 'cachetime', 'contents' } = ( $hstored_mtime, $stored_mtime, $record->{'contents'} );
        }
        Cpanel::Debug::log_debug( 'returned 1 ' . dump_rec($record) ) if ( $Cpanel::Debug::level > 3 );
        return 1;

    }

    if ( $Cpanel::Debug::level > 3 ) {
        Cpanel::Debug::log_debug( "returned 0 " . dump_rec($record) );
        Cpanel::Debug::log_debug("0 [ hstored_mtime = $hstored_mtime, hpasswdmtime = $hpasswdmtime ] [ stored_mtime = $stored_mtime, passwdmtime = $stored_mtime ]");
    }

    return 0;
}

sub invalidate {
    my $keyname = shift;
    if    ( $keyname eq 'user' ) { $keyname = 0; }
    elsif ( $keyname eq 'uid' )  { $keyname = 2; }
    my $key = shift;

    $keyname = int $keyname;
    $key =~ s/\///g;

    my $pwkey       = $keyname . ':' . $key;
    my $pwcache_ref = Cpanel::PwCache::Cache::get_cache();

    if ( exists $pwcache_ref->{$pwkey} ) {
        Cpanel::PwCache::Cache::remove_key($pwkey);
    }

    my $PRODUCT_CONF_DIR = Cpanel::PwCache::Helpers::default_product_dir();
    my $SYSTEM_CONF_DIR  = Cpanel::PwCache::Helpers::default_conf_dir();

    if ( $keyname == 0 ) {
        unlink( $PRODUCT_CONF_DIR . '/@pwcache/' . $key );
    }
    unlink("$PRODUCT_CONF_DIR/pw.cache/$pwkey");
    unlink(
        "$SYSTEM_CONF_DIR/master.passwd.cache",
        "$SYSTEM_CONF_DIR/master.passwd.nouids.cache",
        "$SYSTEM_CONF_DIR/passwd.cache",
        "$SYSTEM_CONF_DIR/passwd.nouids.cache",
        "$SYSTEM_CONF_DIR/shadow.cache",
        "$SYSTEM_CONF_DIR/shadow.nouids.cache",
    );

    return;
}

sub dump_rec {
    my $rec = shift;

    if ( ref $rec eq 'HASH' ) {
        my $buf;
        foreach my $key ( sort keys %{$rec} ) {
            if ( ref $rec->{$key} eq 'ARRAY' ) {
                $buf .= "$key=" . join( ',', @{ $rec->{$key} } ) . "\t";
            }
            else {
                $buf .= "$key=$rec->{$key}\t";
            }
        }
        return $buf;
    }
    else {
        return $rec;
    }
}

1;
