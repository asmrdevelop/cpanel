package Cpanel::SSL::Auto::Run::NAT;

# cpanel - Cpanel/SSL/Auto/Run/NAT.pm              Copyright 2022 cPanel, L.L.C.
#                                                           All rights reserved.
# copyright@cpanel.net                                         http://cpanel.net
# This code is subject to the cPanel license. Unauthorized copying is prohibited

use cPstrict;

=encoding utf-8

=head1 NAME

Cpanel::SSL::Auto::Run::NAT

=head1 DESCRIPTION

This module holds AutoSSL’s logic for checking and reporting the local
system’s NAT configuration.

=cut

#----------------------------------------------------------------------

use Cpanel::Imports;

use Cpanel::NAT           ();
use Cpanel::NAT::Diagnose ();

use constant _DNS_PORT => 53;

#----------------------------------------------------------------------

=head1 FUNCTIONS

=head2 evaluate( $PROVIDER_OBJ )

Accepts an instance of L<Cpanel::SSL::Auto::Provider> and appends
appropriate messages to its log.

Nothing is returned.

=cut

sub evaluate ($provider_obj) {
    $provider_obj->log( 'info', locale()->maketext('Looking for potential [output,abbr,NAT,Network Address Translation] problems …') );

    my $indent = $provider_obj->create_log_level_indent();

    # The is_nat() check here appears to be redundant,
    # but it’s at least consistent with other NAT-handling code.
    my $status_ar = Cpanel::NAT::is_nat() && Cpanel::NAT::Diagnose::find_loopback_nat_problems(
        port    => _DNS_PORT(),
        timeout => 5,
    );

    if ( $status_ar && @$status_ar ) {
        for my $ip_err (@$status_ar) {
            my ( $local, $public, $err ) = @$ip_err;

            my $hdr = "$public ($local):";

            if ( defined $err ) {
                if ($err) {
                    $err = locale()->maketext( 'The system failed to evaluate loopback [asis,NAT] on this [asis,IP] address because of an error: [_1]', $err );
                }

                $err ||= locale()->maketext( 'Loopback [asis,NAT] on this [asis,IP] address appears to be defective. [asis,AutoSSL] will likely fail to secure any domain whose authoritative nameserver uses this address. You can test this by running “[_1]” at a command prompt.', "dig \@$public . NS" );

                $provider_obj->log( 'error', "$hdr $err" );
            }
            else {
                $provider_obj->log( 'success', "$hdr OK" );
            }
        }
    }
    else {
        $provider_obj->log( 'info', locale()->maketext('This server does not use [asis,NAT].') );
    }

    return;
}

1;
