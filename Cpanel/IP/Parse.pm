package Cpanel::IP::Parse;

# cpanel - Cpanel/IP/Parse.pm                        Copyright 2022 cPanel L.L.C.
#                                                           All rights reserved.
# copyright@cpanel.net                                         http://cpanel.net
# This code is subject to the cPanel license. Unauthorized copying is prohibited

use strict;

# flags
our $BRACKET_IPV6 = 1;

sub parse {
    my ( $ipdata, $port, $flags ) = @_;

    my ( $ip, $version, $parsed_port );
    if ( $ipdata =~ tr/*// ) {
        ( $ip, $parsed_port ) = split( /:/, $ipdata, 2 );
        $version = 4;    #default to 4
    }
    elsif ( $ipdata =~ tr/\.// && ( $ipdata =~ tr/:// ) >= 2 ) {    #ipv4 embedded in ipv6
        $ipdata =~ tr/[]//d;
        substr( $ipdata, 0, 6, '0000' ) if index( $ipdata, '(null)' ) == 0;
        $version = 4;
        ( $ip, $parsed_port ) = $ipdata =~ /:([0-9]+\.[0-9]+\.[0-9]+\.[0-9]+):?([0-9]*)$/;
    }
    elsif ( $ipdata =~ tr/\[// ) {                                  #ipv6
        substr( $ipdata, 0, 6, '0000' ) if index( $ipdata, '(null)' ) == 0;
        $version = 6;
        if ( index( $ipdata, ']:' ) > -1 ) {
            ( $ip, $parsed_port ) = split( /]/, $ipdata, 2 );
            $ip          =~ tr/[//d;
            $parsed_port =~ tr/://d;
            require Cpanel::IP::Expand;
            $ip = Cpanel::IP::Expand::expand_ip($ip);
        }
        else {
            $ipdata =~ tr/[]//d;
            require Cpanel::IP::Expand;
            $ip = Cpanel::IP::Expand::expand_ip($ipdata);
        }
    }
    elsif ( $ipdata =~ tr/\.// ) {    #ipv4
        substr( $ipdata, 0, 6, '0.0.0.0' ) if index( $ipdata, '(null)' ) == 0;
        $version = 4;
        ( $ip, $parsed_port ) = split( /:/, $ipdata, 2 );
    }
    elsif ( ( $ipdata =~ tr/:// ) == 1 || $ipdata eq '(null)' || ( index( $ipdata, '(null):' ) == 0 && substr( $ipdata, 7 ) !~ tr{0-9}{}c ) ) {    #empty
        $version = 4;
        ($parsed_port) = ( split( /:/, $ipdata, 2 ) )[1];
        if ( $parsed_port && $parsed_port =~ tr{0-9}{}c ) {
            $parsed_port = undef;
        }
        $ip = '0.0.0.0';
    }
    else {                                                                                                                                         #default to ipv6
        substr( $ipdata, 0, 6, '0000' ) if index( $ipdata, '(null)' ) == 0;
        $version = 6;
        if ( ( $ipdata =~ tr/:// ) >= 8 ) {
            my @split_ip = split( /:/, $ipdata );
            $parsed_port = pop @split_ip;
            require Cpanel::IP::Expand;
            $ip = Cpanel::IP::Expand::expand_ip( join( ':', @split_ip ) );
        }
        else {
            require Cpanel::IP::Expand;
            $ip = Cpanel::IP::Expand::expand_ip($ipdata);
        }
    }

    if ($parsed_port) { $port = $parsed_port; }

    $ip = '[' . $ip . ']' if $version == 6 && $flags && ( $flags & $BRACKET_IPV6 );

    return ( $version, $ip, $port );
}
1;
