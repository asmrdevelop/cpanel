package Cpanel::cPAddons::Globals::Static;

# cpanel - Cpanel/cPAddons/Globals/Static.pm       Copyright 2022 cPanel, L.L.C.
#                                                           All rights reserved.
# copyright@cpanel.net                                         http://cpanel.net
# This code is subject to the cPanel license. Unauthorized copying is prohibited

use strict;
use warnings;

=encoding utf-8

=head1 NAME

Cpanel::cPAddons::Globals::Static

=head1 DESCRIPTION

Global configuration values for cPAddons that do not require an initialization function to run.

=head1 SYNOPSIS

    use Cpanel::cPAddons::Globals::Static;

    print $Cpanel::cPAddons::Globals::Static::base . "\n";

=cut

our $base = '/usr/local/cpanel/cpaddons';

1;
