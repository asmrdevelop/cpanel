package Cpanel::Config::Hulk;

# cpanel - Cpanel/Config/Hulk.pm                   Copyright 2022 cPanel, L.L.C.
#                                                           All rights reserved.
# copyright@cpanel.net                                         http://cpanel.net
# This code is subject to the cPanel license. Unauthorized copying is prohibited

use strict;
use warnings;

our $WHITE_LIST_TYPE         = 1;
our $BLACK_LIST_TYPE         = 2;
our $COUNTRY_WHITE_LIST_TYPE = 3;
our $COUNTRY_BLACK_LIST_TYPE = 4;

our $LOGIN_TYPE_USER_SERVICE_BRUTE = -4;
our $LOGIN_TYPE_EXCESSIVE_BRUTE    = -3;
our $LOGIN_TYPE_BRUTE              = -2;
our $LOGIN_TYPE_FAILED             = -1;
our $LOGIN_TYPE_GOOD               = 1;

our $MAX_LENGTH = 6;

our %LIST_TYPES = (
    $WHITE_LIST_TYPE => 'white',
    $BLACK_LIST_TYPE => 'black'
);

our %LIST_TYPE_VALUES = reverse %LIST_TYPES;

our $HTTP_PORT = 579;

our $conf_dir     = '/var/cpanel/hulkd';
our $app_key_path = '/var/cpanel/cphulkd/keys';
our $socket       = '/var/run/cphulkd.sock';
our $dbsocket     = '/var/run/cphulkd_db.sock';

sub get_sqlite_db { return "$conf_dir/cphulk.sqlite"; }

sub get_cache_dir { return "$conf_dir/cache"; }

sub get_debug_file {
    return -e "$conf_dir/debug" ? "$conf_dir/debug" : '/var/cpanel/hulk_debug';
}

sub get_auth_file {
    my $auth_file = "$conf_dir/password";
    return -e $auth_file ? $auth_file : -e '/var/cpanel/hulkdpass' ? '/var/cpanel/hulkdpass' : $auth_file;
}

sub get_conf_file {
    my $conf_file = "$conf_dir/conf";

    return -e $conf_file ? $conf_file : -e '/var/cpanel/cphulk.conf' ? '/var/cpanel/cphulk.conf' : $conf_file;
}

sub get_action_file {
    my $action_file = "$conf_dir/action";
    return -e $action_file ? $action_file : -e '/var/cpanel/hulkd.conf' ? '/var/cpanel/hulkd.conf' : $action_file;
}

sub get_conf_path { goto &get_conf_file; }

our $enabled_cache;

sub is_enabled {
    return $enabled_cache if defined $enabled_cache;
    return ( $enabled_cache = -e _get_enabled_file() ? 1 : ( -e '/var/cpanel/cphulk_enable' ) ? 1 : 0 );
}

sub disable {
    unlink _get_enabled_file(), '/var/cpanel/cphulk_enable';
    return;
}

sub enable {
    if ( open my $enabled_fh, '>', _get_enabled_file() ) {
        print {$enabled_fh} time();
        close $enabled_fh;
    }
    return;
}

sub _get_enabled_file {
    return "$conf_dir/enabled";
}

1;
