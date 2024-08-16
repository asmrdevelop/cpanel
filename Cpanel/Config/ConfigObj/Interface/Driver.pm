package Cpanel::Config::ConfigObj::Interface::Driver;

# cpanel - Cpanel/Config/ConfigObj/Interface/Driver.pm
#                                                  Copyright 2022 cPanel, L.L.C.
#                                                           All rights reserved.
# copyright@cpanel.net                                         http://cpanel.net
# This code is subject to the cPanel license. Unauthorized copying is prohibited

# Super class for Cpanel::Config::ConfigObj::Config::*
#  atm, this class is simply for assertion purposes
our $VERSION = 1.0;

use strict;

sub new {
    my $class          = shift;
    my $class_defaults = shift || {};
    my $software_obj   = shift;

    if ( ref $class_defaults ne 'HASH' ) {
        $class_defaults = {};
    }

    my $default_settings = {
        'software_interface' => undef,
    };

    %{$default_settings} = ( %{$default_settings}, %{$class_defaults} );

    my $obj = bless $default_settings, $class;

    if ($software_obj) {
        $obj->set_interface($software_obj);
    }

    return $obj;
}

sub set_interface {
    my $self         = shift;
    my $software_obj = shift;

    die("Invalid obj reference") if ( !ref $software_obj || !$software_obj->isa("Cpanel::Config::ConfigObj") );
    $self->{'software_interface'} = $software_obj;
    return 1;
}

sub interface {
    my ($self) = @_;
    return $self->{'software_interface'};
}

1;
