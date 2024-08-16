package Cpanel::Config::ConfigObj::Interface::Config::Version::v1;

# cpanel - Cpanel/Config/ConfigObj/Interface/Config/Version/v1.pm
#                                                  Copyright 2022 cPanel, L.L.C.
#                                                           All rights reserved.
# copyright@cpanel.net                                         http://cpanel.net
# This code is subject to the cPanel license. Unauthorized copying is prohibited

use strict;
use warnings;

=encoding utf-8

=head1 NAME

Cpanel::Config::ConfigObj::Interface::Config::Version::v1

=head1 SYNOPSIS

    use parent qw(Cpanel::Config::ConfigObj::Interface::Config::Version::v1);

=head1 DESCRIPTION

A Mix-in class for ConfigObj v1 modules.  This module is intended to be
included in the META module for a ConfigObj Driver.

=cut

=head2 spec_version

Mix-in the spec_version

=head3 Input

None

=head3 Output

Always returns 1

=cut

use constant spec_version => 1;

use constant meta_version => 1;

1;
