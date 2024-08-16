package Cpanel::PwCache::Load;

# cpanel - Cpanel/PwCache/Load.pm                  Copyright 2022 cPanel, L.L.C.
#                                                           All rights reserved.
# copyright@cpanel.net                                         http://cpanel.net
# This code is subject to the cPanel license. Unauthorized copying is prohibited

use strict;
use Cpanel::PwCache          ();
use Cpanel::PwCache::Cache   ();
use Cpanel::Debug            ();
use Cpanel::JSON::FailOK     ();
use Cpanel::PwCache::Helpers ();

sub load_pw_cache_file {
    my ( $file, $passwduid, $passwdmtime, $no_uidcheck, $keepforever ) = @_;

    if ( !defined $passwduid || !defined $passwdmtime ) {
        ( $passwduid, $passwdmtime ) = ( stat($file) )[ 4, 9 ];
    }

    if ( !$INC{'Cpanel/JSON.pm'} || ( !$no_uidcheck && $passwduid != 0 ) || !$passwdmtime ) { return; }
    my $pwdata_ref = Cpanel::JSON::FailOK::LoadFile($file);
    if ( !$pwdata_ref || !ref $pwdata_ref ) { return; }
    my $pwdata = ( ref $pwdata_ref eq 'ARRAY' ? $pwdata_ref : $pwdata_ref->{'contents'} );
    if ( !$pwdata || ref $pwdata ne 'ARRAY' ) { return; }

    Cpanel::PwCache::_cache_pwdata($pwdata);

    # Year 2038 problem
    if ($keepforever) {
        $pwdata->[11] = 2147483647;
        $pwdata->[12] = 2147483647;
    }

    return $pwdata->[0];
}

# ...
#The key is a concatenation of:
#   - the array index in a pw entry (e.g., 2 for UID)
#   - a colon
#   - the username
#
sub load {
    my $pwkey = shift;
    my ( $field, $value ) = split( /:/, $pwkey, 2 );
    my $SYSTEM_CONF_DIR = Cpanel::PwCache::Helpers::default_conf_dir();

    my $running_as_root = $> == 0 ? 1 : 0;
    my ( $passwdmtime, $hpasswdmtime ) = ( ( stat("$SYSTEM_CONF_DIR/passwd") )[9], ( $running_as_root ? ( stat("$SYSTEM_CONF_DIR/shadow") )[9] : 0 ) );

    Cpanel::Debug::log_debug("called for pwkey $pwkey") if ( $Cpanel::Debug::level > 3 );

    my $pwdata = Cpanel::PwCache::_getpwdata( $value, $field, $passwdmtime, $hpasswdmtime, $running_as_root );

    Cpanel::PwCache::_cache_pwdata($pwdata) if $pwdata && @$pwdata;

    return Cpanel::PwCache::Cache::get_cache()->{$pwkey};
}

#The key is a concatenation of:
#   - the array index in a pw entry (e.g., 2 for UID)
#   - a colon
#   - the username
#
sub load_cached {
    my $pwkey           = shift;
    my $SYSTEM_CONF_DIR = Cpanel::PwCache::Helpers::default_conf_dir();
    my $pwcache_ref     = Cpanel::PwCache::Cache::get_cache();
    if ( exists $pwcache_ref->{$pwkey} ) {
        my ( $passwdmtime, $hpasswdmtime ) = ( ( stat("$SYSTEM_CONF_DIR/passwd") )[9], ( $> == 0 ? ( stat("$SYSTEM_CONF_DIR/shadow") )[9] : 0 ) );
        if ( $pwcache_ref->{$pwkey}->{'hcachetime'} == $hpasswdmtime && $pwcache_ref->{$pwkey}->{'cachetime'} == $passwdmtime ) {
            return $pwcache_ref->{$pwkey};
        }
        else {
            # The whole cache is invalid since there is only
            # once mtime and one file
            Cpanel::PwCache::Cache::clear();
        }
    }
    return;
}

1;
