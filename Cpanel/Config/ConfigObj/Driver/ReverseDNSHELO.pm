package Cpanel::Config::ConfigObj::Driver::ReverseDNSHELO;

# cpanel - Cpanel/Config/ConfigObj/Driver/ReverseDNSHELO.pm
#                                                  Copyright 2022 cPanel, L.L.C.
#                                                           All rights reserved.
# copyright@cpanel.net                                         http://cpanel.net
# This code is subject to the cPanel license. Unauthorized copying is prohibited

use strict;
use warnings;

=encoding utf-8

=head1 NAME

Cpanel::Config::ConfigObj::Driver::ReverseDNSHELO

=head1 DESCRIPTION

Feature Showcase driver for ReverseDNSHELO

=cut

use parent qw(Cpanel::Config::ConfigObj::Interface::Config::v1);

use Cpanel::Config::ConfigObj::Driver::ReverseDNSHELO::META ();

*VERSION = \$Cpanel::Config::ConfigObj::Driver::ReverseDNSHELO::META::VERSION;

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

Enable use of ReverseDNS for HELO.

=cut

sub enable {
    my ($self) = @_;

    return $self->_update_setting(1);
}

=head2 disable

Disable use of ReverseDNS for HELO.

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

    if ($new_setting) {

        # Ideally we would use the same method that
        # the WHMAPI1 set_tweaksetting api uses
        #
        # Once Whostmgr::TweakSettings::Configure::Mail implements a save
        # function we can get rid of this and just use the save via
        # Whostmgr::TweakSettings::apply_module_settings
        #
        #
        require Cpanel::ServerTasks;
        require Cpanel::SMTP::ReverseDNSHELO;
        require Cpanel::SMTP::ReverseDNSHELO::SyncEximLocalOpts;
        Cpanel::SMTP::ReverseDNSHELO->set_on();
        Cpanel::SMTP::ReverseDNSHELO::SyncEximLocalOpts::sync();
        Cpanel::ServerTasks::schedule_task( ['DNSTasks'],  1,   "update_reverse_dns_cache" );
        Cpanel::ServerTasks::schedule_task( ['CpDBTasks'], 600, "update_userdomains" );
    }

    # No disable function since its never displayed if enabled already

    return 1;
}

1;
