package Cpanel::SafeRun::API;

# cpanel - Cpanel/SafeRun/API.pm                   Copyright 2022 cPanel, L.L.C.
#                                                           All rights reserved.
# copyright@cpanel.net                                         http://cpanel.net
# This code is subject to the cPanel license. Unauthorized copying is prohibited

use strict;
use warnings;

use Cpanel::SafeRun::Simple ();
use Cpanel::Parser::Vars    ();
use Cpanel::Encoder::Tiny   ();

sub html_encoded_api_safe_system {
    if ($Cpanel::Parser::Vars::trap_defaultfh) {
        my $out       = Cpanel::Encoder::Tiny::safe_html_encode_str( Cpanel::SafeRun::Simple::saferun(@_) );
        my $exit_code = $?;
        print $out if defined $out;
        return $exit_code;    #system returns the exit status of the program from "wait".   This is just $?
    }
    else {
        return system(@_);
    }
}

sub api_safe_system {
    if ($Cpanel::Parser::Vars::trap_defaultfh) {
        my $out       = Cpanel::SafeRun::Simple::saferun(@_);
        my $exit_code = $?;
        print $out if defined $out;
        return $exit_code;    #system returns the exit status of the program from "wait".   This is just $?
    }
    else {
        return system(@_);
    }
}

1;
