
# cpanel - Whostmgr/Cpaddon/Signatures.pm          Copyright 2022 cPanel, L.L.C.
#                                                           All rights reserved.
# copyright@cpanel.net                                         http://cpanel.net
# This code is subject to the cPanel license. Unauthorized copying is prohibited

package Whostmgr::Cpaddon::Signatures;

use strict;
use warnings;
use Cpanel::Config::CpConfGuard ();

=head1 NAME

Whostmgr::Cpaddon::Signatures

=head1 DESCRIPTION

Provides cpanelsync and Cpanel::HttpUpdate flags that are appropriate for checking
(or not checking) package signatures according to the current vendor and/or state
of the verify_3rdparty_cpaddons Tweak Setting.

=head1 FUNCTIONS

=head2 cpanelsync_sig_flags(VENDOR)

Given a vendor, VENDOR, returns a string to be used as arguments to the cpanelsync command
to enable signature verification. If signature verification is not suitable for the vendor
in question, then an empty list will be returned instead.

=cut

sub cpanelsync_sig_flags {
    my $vendor = shift;

    if ( $vendor eq 'cPanel' ) {
        return ('--signed=1');
    }
    elsif ( $vendor =~ /^\w+$/ && _verify_3rd_party_addons() ) {
        return ("--signed=1 --vendor=$vendor");
    }
    else {
        return ();
    }
}

=head2 httprequest_sig_flags(VENDOR)

Given a vendor, VENDOR, returns a list of key/value pairs to be used as parameters to the
Cpanel::HttpUpdate constructor to enable signature verification. If signature verification
is not suitable for the vendor in question, then an empty list will be returned instead.

=cut

sub httprequest_sig_flags {
    my $vendor = shift;

    if ( $vendor eq 'cPanel' ) {
        return ( 'signed' => 1 );
    }
    elsif ( $vendor =~ /^\w+$/ && _verify_3rd_party_addons() ) {
        return (
            'signed' => 1,
            'vendor' => $vendor
        );
    }
    else {
        return ();
    }
}

sub _verify_3rd_party_addons {
    my $conf = Cpanel::Config::CpConfGuard->new( 'loadcpconf' => 1 )->config_copy;
    return $conf->{'verify_3rdparty_cpaddons'};
}

1;
