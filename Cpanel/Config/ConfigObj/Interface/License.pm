package Cpanel::Config::ConfigObj::Interface::License;

# cpanel - Cpanel/Config/ConfigObj/Interface/License.pm
#                                                  Copyright 2022 cPanel, L.L.C.
#                                                           All rights reserved.
# copyright@cpanel.net                                         http://cpanel.net
# This code is subject to the cPanel license. Unauthorized copying is prohibited

# Super class for Cpanel::Config::ConfigObj::Driver::* which provides a default
#  methods/functions to be overridden

our $VERSION = 1.0;

use strict;

use parent qw(Cpanel::Config::ConfigObj::Interface::Driver);

use Cpanel::Logger ();

my $logger = Cpanel::Logger->new();

####### FUNCTIONS #######

####### METHODS #######

sub init {
    $logger->die( "'init()' must be implemented by subclasses of '" . __PACKAGE__ . "'" );
}

sub license_data {
    return {};
}

1;
