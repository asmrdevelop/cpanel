package Cpanel::Config::ConfigObj::Driver::ExampleDriver;

# cpanel - Cpanel/Config/ConfigObj/Driver/ExampleDriver.pm
#                                                  Copyright 2022 cPanel, L.L.C.
#                                                           All rights reserved.
# copyright@cpanel.net                                         http://cpanel.net
# This code is subject to the cPanel license. Unauthorized copying is prohibited

use strict;
use Cpanel::Config::ConfigObj::Driver::ExampleDriver::META ();
*VERSION = \$Cpanel::Config::ConfigObj::Driver::ExampleDriver::META::VERSION;

# This driver implements v1 spec
use parent qw{Cpanel::Config::ConfigObj::Interface::Config::v1};

# Testing stub; must implement per spec
sub init {
    my ( $class, $software_obj ) = @_;

    my $defaults = {
        'settings' => {
            'foobar_enabled' => undef,
            'meta'           => {}
        },
        'thirdparty_ns' => "",
    };
    my $self = $class->SUPER::base( $defaults, $software_obj );

    return $self;
}

# Testing stub; must implement per spec
sub enable {
    my ($self) = @_;
    return 1;
}

# Testing stub; must implement per spec
sub disable {
    my ($self) = @_;
    return 1;
}

# Testing stub; must implement per spec
sub info {
    return "All FooBar, All the time!";
}

## Testing stub; optional per spec.
#
#sub check {
#    my ( $self ) = @_;
#    return
#}

1;
