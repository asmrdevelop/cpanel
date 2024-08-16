# cpanel - Whostmgr/Store/Product/ImunifyAV/Util.pm Copyright 2022 cPanel, L.L.C.
#                                                           All rights reserved.
# copyright@cpanel.net                                         http://cpanel.net
# This code is subject to the cPanel license. Unauthorized copying is prohibited

package Whostmgr::Store::Product::ImunifyAV::Util;

use strict;
use warnings;
use Whostmgr::Store::Product::ImunifyAV ();

=head1 NAME

Whostmgr::Store::Product::ImunifyAV::Util

=head1 DESCRIPTION

Wrapper functions for Whostmgr::Store::Product::ImunifyAV to facilitate calling from Feature Showcase
JSON files, which do not have a sophisticated enough Perl capability to instantiate an object directly.

Note: This is for the unpaid version of ImunifyAV, not ImunifyAV+.

=head1 FUNCTIONS

=head2 precheck()

If ImunifyAV or Imunify360 is already installed, precheck returns false,
indicating that this should be skipped in the Feature Showcase.

=cut

sub precheck {
    require Whostmgr::Imunify360;
    return 0 if Whostmgr::Imunify360::is_imunify360_installed();
    return 0 if Whostmgr::Store::Product::ImunifyAV->is_product_installed();
    return 1;
}

=head2 install()

Install ImunifyAV.

=cut

sub install {
    return Whostmgr::Store::Product::ImunifyAV->new( redirect_path => '/' )->install();
}

1;
