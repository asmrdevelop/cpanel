package Cpanel::Config::userdata::Constants;

# cpanel - Cpanel/Config/userdata/Constants.pm     Copyright 2022 cPanel, L.L.C.
#                                                           All rights reserved.
# copyright@cpanel.net                                         http://cpanel.net
# This code is subject to the cPanel license. Unauthorized copying is prohibited

use strict;
use warnings;

=encoding utf-8

=head1 NAME

Cpanel::Config::userdata::Constants - Constants for userdata

=head1 SYNOPSIS

    use Cpanel::Config::userdata::Constants;

    my $dir = $Cpanel::Config::userdata::Constants::USERDATA_DIR;

=cut

our $USERDATA_DIR = '/var/cpanel/userdata';

1;
