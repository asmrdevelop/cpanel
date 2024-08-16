package Cpanel::UrlTools;

# cpanel - Cpanel/UrlTools.pm                      Copyright 2022 cPanel, L.L.C.
#                                                           All rights reserved.
# copyright@cpanel.net                                         http://cpanel.net
# This code is subject to the cPanel license. Unauthorized copying is prohibited

use strict;
use Cpanel::Debug ();

sub urltofile {
    my ($url) = @_;
    my (@URL) = split( /\//, $url );
    return ( $URL[$#URL] );
}

sub buildurlfromuri {
    my ( $rHOSTS, $uri ) = @_;
    if ( substr( $uri, 0, 1 ) ne '/' ) { $uri = '/' . $uri; }
    my (@URLS);
    foreach my $host ( @{$rHOSTS} ) {
        push @URLS, 'http://' . $host . $uri;
    }
    return wantarray ? @URLS : \@URLS;
}

sub extracthosts {
    my ($rURLS) = @_;
    my @HOSTS;
    foreach my $url ( @{$rURLS} ) {
        if ( $url =~ m/https?\:\/\/([^\/]+)\// ) {
            push @HOSTS, $1;
        }
        else {
            Cpanel::Debug::log_warn( 'Invalid URL: ' . $url );
        }
    }
    return wantarray ? @HOSTS : \@HOSTS;
}

sub extract_host_uri {
    my ($url) = @_;
    if ( $url =~ m/https?\:\/\/([^\/]+)(\/.*)/ ) {
        return ( $1, $2 );
    }
    else {
        Cpanel::Debug::log_warn( 'Invalid URL: ' . $url );
    }

    return;
}

1;
