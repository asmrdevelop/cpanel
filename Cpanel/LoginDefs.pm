#!/usr/local/cpanel/3rdparty/bin/perl

# cpanel - Cpanel/LoginDefs.pm                     Copyright 2022 cPanel, L.L.C.
#                                                           All rights reserved.
# copyright@cpanel.net                                         http://cpanel.net
# This code is subject to the cPanel license. Unauthorized copying is prohibited

package Cpanel::LoginDefs;

use strict;
use warnings;

use Cpanel::Exception            ();
use Cpanel::Config::LoadConfig   ();
use Cpanel::AdminBin::Serializer ();    # PPI USE OK - For fast LoadConfig

use Cpanel::OS ();

our $logindefs = q{/etc/login.defs};

{
    # could use a static variable here
    my $_cache      = {};
    my $_login_defs = {};

    sub get_uid_min {

        # we could also use a constant (500/1000)
        #	but any admin can change that value, so let's read it
        #	fallback to the CentOS 6 value if we cannot read the file
        return _get_cache( 'UID_MIN', Cpanel::OS::default_uid_min() );
    }

    sub get_uid_max {
        return _get_cache( 'UID_MAX', 60000 );
    }

    sub get_gid_min {
        return _get_cache( 'GID_MIN', Cpanel::OS::default_gid_min() );
    }

    sub get_gid_max {
        return _get_cache( 'GID_MAX', 60000 );
    }

    sub get_sys_uid_min {
        return _get_cache( 'SYS_UID_MIN', Cpanel::OS::default_sys_uid_min() );
    }

    sub get_sys_uid_max {
        return _get_cache( 'SYS_UID_MAX', get_uid_min() - 1 );
    }

    sub get_sys_gid_min {
        return _get_cache( 'SYS_GID_MIN', Cpanel::OS::default_sys_gid_min() );
    }

    sub get_sys_gid_max {
        return _get_cache( 'SYS_GID_MAX', get_gid_min() - 1 );
    }

    sub get_uid_gid_sys_min {
        if ( !$_cache->{'UID_MIN'} || !$_cache->{'SYS_UID_MIN'} || !$_cache->{'GID_MIN'} || !$_cache->{'SYS_GID_MIN'} ) {
            $_login_defs->{$logindefs} ||= Cpanel::Config::LoadConfig::loadConfig( $logindefs, undef, '\s+' );
            die Cpanel::Exception::create( 'IO::FileReadError', [ path => $logindefs, error => $! ] ) if !$_login_defs->{$logindefs};
            $_cache->{'UID_MIN'}     = $_login_defs->{$logindefs}->{'UID_MIN'}     || Cpanel::OS::default_uid_min();
            $_cache->{'GID_MIN'}     = $_login_defs->{$logindefs}->{'GID_MIN'}     || Cpanel::OS::default_gid_min();
            $_cache->{'SYS_UID_MIN'} = $_login_defs->{$logindefs}->{'SYS_UID_MIN'} || Cpanel::OS::default_sys_uid_min();
            $_cache->{'SYS_GID_MIN'} = $_login_defs->{$logindefs}->{'SYS_GID_MIN'} || Cpanel::OS::default_sys_gid_min();
        }
        return ( $_cache->{'UID_MIN'}, $_cache->{'SYS_UID_MIN'}, $_cache->{'GID_MIN'}, $_cache->{'SYS_GID_MIN'} );
    }

    sub get_value_for {
        my $want = shift or return;
        $_login_defs->{$logindefs} ||= Cpanel::Config::LoadConfig::loadConfig( $logindefs, undef, '\s+' );
        die Cpanel::Exception::create( 'IO::FileReadError', [ path => $logindefs, error => $! ] ) if !$_login_defs->{$logindefs};
        return $_login_defs->{$logindefs}->{$want};
    }

    sub _get_cache {
        my ( $k, $default ) = @_;
        return $_cache->{$k} if defined $_cache->{$k};

        $_cache->{$k} = int( get_value_for($k) || 0 ) || $default;
        return $_cache->{$k};
    }

    # for unit test
    sub _clear_cache {
        $_cache      = {};
        $_login_defs = {};
        return;
    }
}

1;
