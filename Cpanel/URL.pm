package Cpanel::URL;

# cpanel - Cpanel/URL.pm                           Copyright 2022 cPanel, L.L.C.
#                                                           All rights reserved.
# copyright@cpanel.net                                         http://cpanel.net
# This code is subject to the cPanel license. Unauthorized copying is prohibited

sub parse {
    my $url = shift;
    return {} if !$url;

    my ( $host, $uri ) = ( split m{/+}, $url, 3 )[ 1, 2 ];
    $uri = '/' . ( $uri || '' );
    $uri =~ s{[^/]+/+\.\./}{}g;
    $uri =~ s/\.\.//g;
    my ($filename) = $uri =~ m{/([^/]+)$};

    return { 'file' => $filename, 'host' => $host, 'uri' => $uri };
}

1;
