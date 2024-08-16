package Cpanel::Config::LoadUserDomains::Tiny;

# cpanel - Cpanel/Config/LoadUserDomains/Tiny.pm   Copyright 2022 cPanel, L.L.C.
#                                                           All rights reserved.
# copyright@cpanel.net                                         http://cpanel.net
# This code is subject to the cPanel license. Unauthorized copying is prohibited

use strict;
use warnings;

use Cpanel::ConfigFiles              ();
use Cpanel::Config::LoadConfig::Tiny ();
use Cpanel::Server::Type             ();

sub loaduserdomains {
    my $conf_ref = shift;
    my $reverse  = shift;
    my $usearr   = shift;
    $conf_ref = Cpanel::Config::LoadConfig::Tiny::loadConfig(
        _userdomains(),
        $conf_ref,
        '\s*[:]\s*',
        undef, 0, 0,
        {
            'use_reverse'          => $reverse ? 0 : 1,
            'skip_keys'            => ['nobody'],
            'use_hash_of_arr_refs' => ( $usearr || 0 ),
        }
    );
    if ( !defined($conf_ref) ) {
        $conf_ref = {};
    }
    return wantarray ? %{$conf_ref} : $conf_ref;
}

sub loadtrueuserdomains {
    my $conf_ref     = shift;
    my $reverse      = shift;
    my $ignore_limit = shift;

    $conf_ref = Cpanel::Config::LoadConfig::Tiny::loadConfig(
        ( $reverse ? _domainusers() : _trueuserdomains() ),
        $conf_ref,
        '\s*[:]\s*',
        undef, 0, 0,
        {
            'use_reverse' => 0,
            'limit'       => ( $ignore_limit ? 0 : Cpanel::Server::Type::get_max_users() )
        }
    );
    if ( !defined($conf_ref) ) {
        $conf_ref = {};
    }
    return wantarray ? %{$conf_ref} : $conf_ref;
}

# allow an easy way to mock for testing
sub _userdomains {
    $Cpanel::ConfigFiles::USERDOMAINS_FILE;
}

sub _domainusers {
    $Cpanel::ConfigFiles::DOMAINUSERS_FILE;
}

sub _trueuserdomains {
    $Cpanel::ConfigFiles::TRUEUSERDOMAINS_FILE;
}
1;
