package Cpanel::DNSLib::Check;

# cpanel - Cpanel/DNSLib/Check.pm                  Copyright 2022 cPanel, L.L.C.
#                                                           All rights reserved.
# copyright@cpanel.net                                         http://cpanel.net
# This code is subject to the cPanel license. Unauthorized copying is prohibited

use strict;
use warnings;

use Cpanel::Debug           ();
use Cpanel::DNSLib::Find    ();
use Cpanel::SafeRun::Errors ();

=encoding utf-8

=head1 NAME

Cpanel::DNSLib::Check

=head1 DESCRIPTION

Package providing helpers to check rndc status.

=head1 CLASS METHODS

=head2 checkrndc()

This function does not requires any input.
It returns a boolean 0 or 1, depending on that
success of 'rndc status' otuput and will log any
warnings to the cpanel error_log.

=cut

sub checkrndc {

    my ( $rndc, $rndcprog ) = Cpanel::DNSLib::Find::find_rndc();

    if ( !$rndc ) {
        Cpanel::Debug::log_warn('Unable to locate either rndc or ndc. Please check Bind installation.');
        return 1;
    }

    my $output = Cpanel::SafeRun::Errors::saferunallerrors( $rndc, 'status' );

    if ( !$output ) {
        Cpanel::Debug::log_warn("$rndc status did not return any output");
        return 0;
    }

    return 1 if $output =~ m/server\s+is\s+up\s+and\s+running/mi;

    $output =~ s/[\r\n]//g;    # so info/error messages stack up nicely in output

    if ( $output =~ m/failed/mi || $output =~ m/\sneither.+\sfound/mi || $output =~ m/connection\s+refused/mi ) {
        Cpanel::Debug::log_warn("$rndc status failed: $output");
        return 0;
    }

    Cpanel::Debug::log_warn("$rndc status failed (Unable to parse output): $output");
    return 0;
}

1;
