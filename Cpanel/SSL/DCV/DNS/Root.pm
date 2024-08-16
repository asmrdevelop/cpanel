package Cpanel::SSL::DCV::DNS::Root;

# cpanel - Cpanel/SSL/DCV/DNS/Root.pm              Copyright 2022 cPanel, L.L.C.
#                                                           All rights reserved.
# copyright@cpanel.net                                         http://cpanel.net
# This code is subject to the cPanel license. Unauthorized copying is prohibited

use strict;
use warnings;

=encoding utf-8

=head1 NAME

Cpanel::SSL::DCV::DNS - DNS-based DCV logic to run as root

=head1 SYNOPSIS

    my $results_ar = Cpanel::SSL::DCV::DNS::Root::verify_domains(
        username => $username,
        domains => \@domains,
    );

=cut

use Cpanel::SSL::DCV::DNS        ();
use Cpanel::SSL::DCV::DNS::Setup ();

=head1 FUNCTIONS

=head2 verify_domains( %OPTS )

The same as L<Cpanel::SSL::DCV::DNS::User>’s function of the same name
but meant to run as root. This requires a C<username> parameter in
addition to those mentioned in the User module.

=cut

sub verify_domains {
    my (@opts_kv) = @_;

    return Cpanel::SSL::DCV::DNS::_verify_domains(
        \&_install_as_root,
        @opts_kv,
    );
}

*_install_as_root = *Cpanel::SSL::DCV::DNS::Setup::set_up_for_zones;

1;
