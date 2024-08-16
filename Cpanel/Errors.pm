package Cpanel::Errors;

# cpanel - Cpanel/Errors.pm                        Copyright 2022 cPanel, L.L.C.
#                                                           All rights reserved.
# copyright@cpanel.net                                         http://cpanel.net
# This code is subject to the cPanel license. Unauthorized copying is prohibited

use strict;
use warnings;

use Cpanel::MagicRevision ();

our $VERSION = '2.0';

################################################################################
# HTML table begin/end output functions
################################################################################
sub _print_html_table_begin {
    print qq{<table width="100%"><tr><td>\n};
}

sub _print_html_table_end {
    print qq{</td><td width="30"><img src="} . Cpanel::MagicRevision::calculate_magic_url('/cjt/images/icons/error.png') . qq{"></td></tr></table>\n\n};
}

################################################################################
# undeaderror - print html version of error if appropriate
################################################################################
sub undeaderror {
    my $error  = shift;
    my $whm    = $ENV{'WHM50'}  || '';
    my $cpanel = $ENV{'CPANEL'} || '';

    if ( $whm ne '' || $cpanel ne '' ) {
        _print_html_table_begin();
    }
    print "$error\n";
    if ( $whm ne '' || $cpanel ne '' ) {
        _print_html_table_end();
    }
}

################################################################################
# deaderror - print html version of error if appropriate
################################################################################
sub deaderror {
    my $error     = shift;
    my $skipdeath = shift;
    my $whm       = $ENV{'WHM50'} || '';

    if ($whm) {
        _print_html_table_begin();
    }
    print "$error\n";
    if ($whm) {
        _print_html_table_end();
    }
    else {
        sleep 4;
    }
    if ( !$skipdeath ) { exit; }
}

sub warnerror {

    goto &undeaderror;
}

1;
