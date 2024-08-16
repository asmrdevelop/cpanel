package Cpanel::Config::ConfigObj::Driver::PipedLogging;

# cpanel - Cpanel/Config/ConfigObj/Driver/PipedLogging.pm
#                                                  Copyright 2022 cPanel, L.L.C.
#                                                           All rights reserved.
# copyright@cpanel.net                                         http://cpanel.net
# This code is subject to the cPanel license. Unauthorized copying is prohibited

use strict;
use warnings;

=encoding utf-8

=head1 NAME

Cpanel::Config::ConfigObj::Driver::PipedLogging

=head1 DESCRIPTION

Feature Showcase driver for PipedLogging

=cut

use parent qw(Cpanel::Config::ConfigObj::Interface::Config::v1);

use Cpanel::Config::ConfigObj::Driver::PipedLogging::META ();

*VERSION = \$Cpanel::Config::ConfigObj::Driver::PipedLogging::META::VERSION;

=head1 METHODS

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

Enable piped logging for Apache.

=cut

sub enable {
    my ($self) = @_;

    return $self->_update_setting(1);
}

=head2 disable

Disable piped logging for Apache.

B<Note>: Since the feature showcase entry is not displayed if Piped Logging
is already enabled, this is not used in the feature showcase interface itself.

=cut

sub disable {
    my ($self) = @_;
    return $self->_update_setting(0);
}

=head2 set_default

We want this checked by default.

=cut

sub set_default { return 1; }
sub check       { return undef; }

sub _update_setting {
    my ( $self, $new_setting ) = @_;

    require Whostmgr::TweakSettings;
    if ($new_setting) {
        Whostmgr::TweakSettings::set_value( "Main", "enable_piped_logs", 1 );
    }

    # No disable function since its never displayed if enabled already

    return 1;
}

1;
