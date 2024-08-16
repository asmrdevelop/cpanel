package Cpanel::Init::Enable::Base;

# cpanel - Cpanel/Init/Enable/Base.pm              Copyright 2022 cPanel, L.L.C.
#                                                           All rights reserved.
# copyright@cpanel.net                                         http://cpanel.net
# This code is subject to the cPanel license. Unauthorized copying is prohibited

use Moo;
use cPstrict;

use Carp 'croak';

has 'enabled'  => ( is => 'rw', default => sub { [] } );
has 'disabled' => ( is => 'rw', default => sub { [] } );

sub reset {
    my ($self) = @_;

    $self->{'enabled'}  = [];
    $self->{'disabled'} = [];

    return;
}

sub collect_enable {
    my ( $self, $service ) = @_;

    push @{ $self->{'enabled'} }, $service;
    return;
}

sub collect_disable {
    my ( $self, $service ) = @_;

    push @{ $self->{'disabled'} }, $service;
    return;
}

sub enable {
    croak 'Must implement in subclass!';
}

sub disable {
    croak 'Must implement in subclass!';
}

sub is_enabled {
    croak 'Must implement in subclass!';
}

1;

=head1 NAME

Cpanel::Init::Enable::Base

=head1 DESCRIPTION

    Cpanel::Init::Enable::Base for all the enabler subclasses. It holds all the
    common methods for the subclasses.

=head1 INTERFACE

=head2 Methods

=over 4

=item collect_enable

Argument list: $service_name

This method takes a service name and adds to a list of services that need to be enabled.

=item collect_disable

This method takes a service name and adds to a list of services that need to be disabled.

=back
