package Cpanel::Cpses::Mailman;

# cpanel - Cpanel/Cpses/Mailman.pm                 Copyright 2022 cPanel, L.L.C.
#                                                           All rights reserved.
# copyright@cpanel.net                                         http://cpanel.net
# This code is subject to the cPanel license. Unauthorized copying is prohibited

use strict;
use warnings;

use Cpanel::Rand::Get          ();
use Cpanel::Session::Constants ();
use Cpanel::FileUtils::Write   ();

sub generate_mailman_otp {
    my ($list_name) = @_;

    if ( !length $list_name ) {
        return ( 0, "The mailing list name was not provided." );
    }
    elsif ( $list_name =~ tr/_// == 1 && $list_name =~ m/^_/ ) {
        return ( 0, "The mailing list $list_name must have a list name." );
    }
    elsif ( $list_name =~ m/_$/ ) {
        return ( 0, "The mailing list $list_name must have a domain name." );
    }
    elsif ( $list_name !~ tr/_// ) {
        return ( 0, "A one time password may only be generated for virtual lists." );
    }
    elsif ( $list_name =~ tr{/\0}{} ) {
        return ( 0, "The mailing list $list_name may not contain slashes or null bytes." );
    }
    elsif ( $list_name !~ m/^[\w\.\-]+$/ ) {
        return ( 0, "The mailing list $list_name contains invalid characters." );
    }
    elsif ( !_list_exists($list_name) ) {
        return ( 0, "The mailing list $list_name does not exist." );
    }

    my $onetimeuser = Cpanel::Rand::Get::getranddata( 8,  [ 0 .. 9, 'A' .. 'Z', 'a' .. 'z' ] );
    my $onetimepass = Cpanel::Rand::Get::getranddata( 32, [ 0 .. 9, 'A' .. 'Z', 'a' .. 'z' ] );

    if ( !Cpanel::FileUtils::Write::overwrite_no_exceptions( "$Cpanel::Session::Constants::CPSES_MAILMAN_DIR/${list_name}_$onetimeuser", $onetimepass, 0600 ) ) {
        return ( 0, "Failed to create temporary password file for $list_name." );
    }

    return ( 1, "$onetimeuser\_$onetimepass" );
}

sub _list_exists {
    my ($list_name) = @_;

    die if $list_name =~ tr{/\0}{};

    return -e "/usr/local/cpanel/3rdparty/mailman/lists/$list_name" ? 1 : 0;
}

1;
