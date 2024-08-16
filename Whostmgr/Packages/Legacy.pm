package Whostmgr::Packages::Legacy;

# cpanel - Whostmgr/Packages/Legacy.pm             Copyright 2022 cPanel, L.L.C.
#                                                           All rights reserved.
# copyright@cpanel.net                                         http://cpanel.net
# This code is subject to the cPanel license. Unauthorized copying is prohibited

use strict;
use warnings;

# Deprecated values removed, but need to be preserved to keep a consistent
# mapping when creating a new account:
my @_old_format = (
    'IP',
    'CGI',
    'QUOTA',
    '__DEPRECATED__',    # FRONTPAGE - case FB-104361
    'CPMOD',
    'MAXFTP',
    'MAXSQL',
    'MAXPOP',
    'MAXLST',
    'MAXSUB',
    'BWLIMIT',
    'HASSHELL',
    'MAXPARK',
    'MAXADDON',
    'FEATURELIST',
    'LANG',
    'MAX_EMAIL_PER_HOUR',
    'MAX_DEFER_FAIL_PERCENTAGE',
    '__DEPRECATED__',    # MIN_DEFER_FAIL_TO_TRIGGER_PROTECTION - case FB-51825
    'DIGESTAUTH',
    'MAX_EMAILACCT_QUOTA',
    'MAXPASSENGERAPPS',
    'MAX_TEAM_USERS',
);

my %_addpkg_api_translations = ( LANG => 'language' );

sub pkgref_to_old_format {
    my $pkg_ref = shift;
    if ( ref $pkg_ref ne 'HASH' ) {
        require Carp;
        Carp::confess('No reference value passed to pkgref_to_old_format');
    }
    my @values = @{$pkg_ref}{@_old_format};
    return wantarray ? @values : join( ',', map { $_ // '' } @values );
}

sub pkgref_to_whmapi1_addpkg_args {
    my ($pkg_ref) = @_;

    my $api_ref = {};
    foreach my $pkg_key ( keys %$pkg_ref ) {
        my $api_key = $_addpkg_api_translations{$pkg_key} || $pkg_key =~ tr/A-Z/a-z/r;
        $api_ref->{$api_key} = $pkg_ref->{$pkg_key};
    }

    return $api_ref;
}

1;
