package Cpanel::SSL::DCV::DNS::Setup;

# cpanel - Cpanel/SSL/DCV/DNS/Setup.pm             Copyright 2022 cPanel, L.L.C.
#                                                           All rights reserved.
# copyright@cpanel.net                                         http://cpanel.net
# This code is subject to the cPanel license. Unauthorized copying is prohibited

use strict;
use warnings;

=encoding utf-8

=head1 NAME

Cpanel::SSL::DCV::DNS::Setup

=head1 SYNOPSIS

    my ($value, $state) = Cpanel::SSL::DCV::DNS::Setup::set_up_for_zones( [ 'foo.com', 'bar.org' ] );

=head1 DESCRIPTION

This module implements the logic to alter a DNS zone for the purposes
of DCV.

=cut

use Cpanel::Context                  ();
use Cpanel::DnsUtils::Install        ();
use Cpanel::Rand::Get                ();
use Cpanel::SSL::DCV::DNS::Constants ();

=head1 FUNCTIONS

=head2 ($value, $state) = set_up_for_zones( \@DOMAINS )

This accepts an arrayref of domain names that will receive the
TEST_RECORD_NAME and TEST_RECORD_TYPE.

The return is the opaque string that gets assigned to all of the @DOMAINS,
then the “state” from
C<Cpanel::DnsUtils::Install::install_records_for_multiple_domains()>.

The caller must examine $state to determine if there are any errors.
For more information on $state see
Cpanel::DnsUtils::Install::install_records_for_multiple_domains

=cut

sub set_up_for_zones {
    my ($zones_ar) = @_;

    Cpanel::Context::must_be_list();

    my $value = Cpanel::SSL::DCV::DNS::Constants::TEST_RECORD_NAME() . '=' . Cpanel::Rand::Get::getranddata(64);

    my ( undef, undef, $state ) = Cpanel::DnsUtils::Install::install_records_for_multiple_domains(
        'domains' => { map { $_ => 'all' } @{$zones_ar} },
        'reload'  => 1,
        'records' => [
            {
                'match'       => Cpanel::SSL::DCV::DNS::Constants::TEST_RECORD_NAME() . '=',
                'removematch' => Cpanel::SSL::DCV::DNS::Constants::TEST_RECORD_NAME() . '=',
                'domain'      => '%domain%',
                'record'      => Cpanel::SSL::DCV::DNS::Constants::TEST_RECORD_NAME() . '.' . '%domain%',
                'type'        => Cpanel::SSL::DCV::DNS::Constants::TEST_RECORD_TYPE(),
                'operation'   => 'add',
                'value'       => $value,
                'domains'     => 'all'
            }
        ],
    );

    #
    # We rely on the caller to process the $state
    # variable since $ok can mean partial failure
    # which means we cannot die on !$ok because
    # the caller could never be able to discern
    # what happened.
    #
    # At the time of this writing, all calls into this logic
    # ultimately originate from Cpanel::SSL::DCV::DNS::_verify_domains,
    # which knows how to handle the $state.
    #
    # Note: some of the calls pass-though the zone adminbin.
    #
    return $value, $state;
}

1;
