package Cpanel::PwCache::Helpers;

# cpanel - Cpanel/PwCache/Helpers.pm               Copyright 2022 cPanel, L.L.C.
#                                                           All rights reserved.
# copyright@cpanel.net                                         http://cpanel.net
# This code is subject to the cPanel license. Unauthorized copying is prohibited

# This module is used by scripts/perlinstaller / system Perl.  Do not use cPstrict here
use strict;
use warnings;

my $skip_uid_cache = 0;

sub no_uid_cache { $skip_uid_cache = 1; return }
sub uid_cache    { $skip_uid_cache = 0; return }

sub skip_uid_cache {
    return $skip_uid_cache;
}

sub init {
    my ( $totie, $skip_uid_cache_value ) = @_;

    tiedto($totie);
    $skip_uid_cache = $skip_uid_cache_value;

    return;
}

{    # debugging helpers
    sub confess { require Carp; return Carp::confess(@_) }
    sub cluck   { require Carp; return Carp::cluck(@_) }
}

{    # tie logic and cache

    my $pwcacheistied = 0;
    my $pwcachetie;

    sub istied { return $pwcacheistied }
    sub deinit { $pwcacheistied = 0; return; }

    # accessor
    sub tiedto {
        my $v = shift;

        if ( !defined $v ) {    # get
            return $pwcacheistied ? $pwcachetie : undef;
        }
        else {                  # set
            $pwcacheistied = 1;
            $pwcachetie    = $v;
        }

        return;
    }

}

{
    my $SYSTEM_CONF_DIR  = '/etc';
    my $PRODUCT_CONF_DIR = '/var/cpanel';

    sub default_conf_dir    { return $SYSTEM_CONF_DIR }
    sub default_product_dir { return $PRODUCT_CONF_DIR; }
}

1;
