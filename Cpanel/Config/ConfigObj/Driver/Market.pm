package Cpanel::Config::ConfigObj::Driver::Market;

# cpanel - Cpanel/Config/ConfigObj/Driver/Market.pm
#                                                  Copyright 2022 cPanel, L.L.C.
#                                                           All rights reserved.
# copyright@cpanel.net                                         http://cpanel.net
# This code is subject to the cPanel license. Unauthorized copying is prohibited

use strict;
use warnings;

use Cpanel::Config::ConfigObj::Driver::Market::META ();
*VERSION = \$Cpanel::Config::ConfigObj::Driver::Market::META::VERSION;

use Cpanel::LoadModule ();

# This driver implements v1 spec
use parent qw(Cpanel::Config::ConfigObj::Interface::Config::v1);

=head1 NAME

Cpanel::Config::ConfigObj::Driver::Market

=head1 DESCRIPTION

Feature Showcase driver for SSL Status in cPanel

=cut

=head1 SYNOPSIS

Boilerplate subroutines for the feature showcase.

=cut

=head1 Subroutines

=head2 init

Initializes the feature showcase object.

=cut

sub init {
    my ( $class, $software_obj ) = @_;

    my $defaults = {
        'settings'      => {},
        'thirdparty_ns' => "",
    };

    my $self = $class->SUPER::base( $defaults, $software_obj );

    return $self;
}

=head2 enable

returns 1, and enables the cPStore market provider

=cut

sub enable {
    my ($self) = @_;

    return $self->_update_setting(1);
}

=head2 disable

returns 1, does nothing since this is never displayed if any market provider is enabled

=cut

sub disable {
    my ($self) = @_;
    return $self->_update_setting(0);
}

=head2 info

returns the info text.

=cut

sub info {
    my ($self) = @_;
    return $self->meta()->abstract();
}

=head2 check

Returns 1 or 0 depending on if it is already turned on

=cut

sub status {
    my ($self) = @_;
    return $self->check();
}

=head2 check

Only display if its not already turned on

=cut

sub check {
    my ($self) = @_;

    return Cpanel::Config::ConfigObj::Driver::Market::META::can_be_enabled();
}

sub _update_setting {
    my ( $self, $new_setting ) = @_;

    Cpanel::LoadModule::load_perl_module('Cpanel::Market');
    if ($new_setting) {
        Cpanel::Market::enable_provider('cPStore');
    }

    # No disable function since its never displayed if enabled already

    return 1;
}

1;
