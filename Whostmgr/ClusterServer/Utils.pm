#!/usr/local/cpanel/3rdparty/bin/perl

# cpanel - Whostmgr/ClusterServer/Utils.pm         Copyright 2022 cPanel, L.L.C.
#                                                           All rights reserved.
# copyright@cpanel.net                                         http://cpanel.net
# This code is subject to the cPanel license. Unauthorized copying is prohibited

package Whostmgr::ClusterServer::Utils;

use strict;

sub sanitize_key {
    my $s = shift;
    return unless defined($s);

    $s =~ s/[^0-9A-Za-z]//g;

    return $s;
}

sub sanitize_key_for_signature {
    my $s = shift;
    return unless defined($s);

    $s = lc($s);
    $s =~ s/[^0-9a-f]//g;

    return $s;
}

sub get_key_signature {
    my $k = shift;
    $k = sanitize_key_for_signature($k);
    return unless $k;

    my $signature = substr( $k, 0, 32 );

    $signature =~ s/(.{2})/$1:/g;
    $signature =~ s/:$//;

    return $signature;
}

1;
