package Whostmgr::HTMLInterface::Output;

# cpanel - Whostmgr/HTMLInterface/Output.pm        Copyright 2022 cPanel, L.L.C.
#                                                           All rights reserved.
# copyright@cpanel.net                                         http://cpanel.net
# This code is subject to the cPanel license. Unauthorized copying is prohibited

use strict;
use warnings;

use Cpanel::StringFunc::HTML ();

our $transform_raw;
our $transform_html;

sub print2anyoutput {
    my $data = shift;
    if ( ref $data eq 'GLOB' ) { die "GLOB passed to print2anyoutput"; }
    if ( !output_html() ) {

        # trim_html() currently removes newline chars that are part of a <pre> block,
        # this causes issues with restorepkg's output, so we check to see if the
        # data has a newline char at the end, and add it back.
        my $add_newline = substr( $data, -1, 1 ) eq "\n";
        $data = Cpanel::StringFunc::HTML::trim_html($data);
        $data .= "\n" if $add_newline;

        $data = $transform_raw->($data) if $transform_raw;
    }
    else {
        $data = $transform_html->($data) if $transform_html;
    }
    return print $data;
}

sub output_html {
    return ( -t STDIN || !defined $ENV{'GATEWAY_INTERFACE'} || $ENV{'GATEWAY_INTERFACE'} !~ m{CGI}i ) ? 0 : 1;
}

1;
