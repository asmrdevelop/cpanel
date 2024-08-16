package Cpanel::NAT::Build;

# cpanel - Cpanel/NAT/Build.pm                      Copyright 2022 cPanel L.L.C.
#                                                           All rights reserved.
# copyright@cpanel.net                                         http://cpanel.net
# This code is subject to the cPanel license. Unauthorized copying is prohibited

use strict;
use warnings;

=encoding utf-8

=head1 NAME

Cpanel::NAT::Build - Build NAT config files when NAT configuration is changed.

=head1 SYNOPSIS

    use Cpanel::NAT::Build;

    Cpanel::NAT::Build::update();

=cut

=head2 update()

This function takes care of updating any service or system configuration
files when the NAT configuration is changed.  It is called whenever
/var/cpanel/cpnat is changed.

=cut

sub update {
    require Cpanel::NAT::Object;
    my $public_ips_ar = Cpanel::NAT::Object->new()->get_all_public_ips();

    require Cpanel::Exim::Config::NAT;
    Cpanel::Exim::Config::NAT::sync($public_ips_ar);

    return;
}

1;
