package Cpanel::Config::ConfigObj::Filter::FilterList;

# cpanel - Cpanel/Config/ConfigObj/Filter/FilterList.pm
#                                                  Copyright 2022 cPanel, L.L.C.
#                                                           All rights reserved.
# copyright@cpanel.net                                         http://cpanel.net
# This code is subject to the cPanel license. Unauthorized copying is prohibited

#
# Class that provides an internal list structure and methods for Filter.pm
#  'filter' routines to work against

use strict;

use Cpanel::Config::ConfigObj ();
use Cpanel::Debug             ();

########### PUBLIC INTERFACE METHODS ###########

sub new {
    my ( $class, $configObj ) = @_;
    my $internals = {
        'configObj' => undef,
        'drivers'   => {},
        'data'      => {},
    };
    my $self = bless $internals, $class;

    if ( !$configObj ) {
        $configObj = $self->_create_configObj();
    }
    $self->set_configObj($configObj)->set_data( $self->{'drivers'} );

    return $self;
}

# Remove a driver(s) from the internal data list
#  pass a (list of) driver name(s)
sub remove {
    my ( $self, @drivers ) = @_;
    delete @{ $self->{'data'} }{@drivers};
    return $self;
}

# Add a driver(s) to the internal data list
#  pass a (list of) driver name(s)
# NOTE: these must be an valid drivers (likely filtered out previously).
#  This method would likely be used by filters that undo some default behavior
#  of so user of the ConfigObj:
#  EX: licensed software/features with a driver would not normal be available
#    if the cpanel license was missing the respective flag...but maybe you're
#    managing a list of 'everything', so a 'not_licensed' filter would add back
#    in drivers for the unlicensed software [whether the driver is actually
#    useful for action() would be specific to the scenario and driver ;)
#    ...But as least you can easily get access to the name/meta for that
#    software/feature].
sub add {
    my ( $self, @drivers ) = @_;
    foreach (@drivers) {
        $self->{'data'}->{$_} = $self->{'drivers'}->{$_} if exists $self->{'drivers'}->{$_};
    }
    return $self;
}

# "coerce" obj to an array (or arrayref).
# Returned list will be sorted alphabetically (ascending) by driver name
sub to_array {
    my ($self) = @_;
    my @list = map { ( $self->{'data'}->{$_} ) } sort keys %{ $self->{'data'} };
    return \@list;
}

sub to_list {
    my ($self) = @_;
    return @{ $self->to_array };
}

# "coerce" obj to a hashref.
sub to_hash {
    my ($self) = @_;
    return { %{ $self->{'data'} } };
}

########### CORE METHODS ###########

sub set_configObj {
    my ( $self, $obj ) = @_;
    if ( !ref $obj || !$obj->isa("Cpanel::Config::ConfigObj") ) {
        Cpanel::Debug::log_warn("Invalid object argument");
        return;
    }
    $self->{'configObj'} = $obj;

    # re-establish driver refs
    $self->init_drivers();

    return $self;
}

sub get_configObj {
    my ($self) = @_;
    return $self->{'configObj'};
}

sub init_drivers {
    my ($self)    = @_;
    my $configObj = $self->get_configObj();
    my $drivers   = $configObj->_get_drivers();

    foreach my $d_name ( keys %{$drivers} ) {
        $self->{'drivers'}->{$d_name} = $configObj->get_driver($d_name);
    }

    return $self;
}

sub set_data {
    my ( $self, $hashref, $append ) = @_;

    $self->{'data'} = {} unless $append;

    # make copy of value refs
    foreach ( keys %{$hashref} ) {
        $self->{'data'}->{$_} = $hashref->{$_};
    }

    return $self;
}

########### FUNCTIONS ###########

sub _create_configObj {
    return Cpanel::Config::ConfigObj->new();
}

1;
