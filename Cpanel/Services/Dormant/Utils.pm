package Cpanel::Services::Dormant::Utils;

# cpanel - Cpanel/Services/Dormant/Utils.pm        Copyright 2022 cPanel, L.L.C.
#                                                           All rights reserved.
# copyright@cpanel.net                                         http://cpanel.net
# This code is subject to the cPanel license. Unauthorized copying is prohibited

use strict;
use warnings;

use Cpanel::LoadModule ();

=encoding utf-8

=head1 NAME

Cpanel::Services::Dormant::Utils

=head1 SYNOPSIS

    use Cpanel::Services::Dormant::Utils ();

    my @enabled_dormant_services = Cpanel::Services::Dormant::Utils::get_enabled_dormant_services();

=head1 DESCRIPTION

This module is for any utility functions needed to support the dormant services model

=head1 FUNCTIONS

=head2 get_enabled_dormant_services()

This function gets all currently enabled dormant services by checking the enabled flag under C<$Cpanel::ConfigFiles::DORMANT_SERVICES_DIR>.

=head3 Arguments

None.

=head3 Returns

A list of the enabled dormant services on the system.

=head3 Exceptions

Anything Cpanel::LoadModule::load_perl_module can throw.

=cut

sub get_enabled_dormant_services {
    Cpanel::LoadModule::load_perl_module('Cpanel::ConfigFiles');
    Cpanel::LoadModule::load_perl_module('Cpanel::Config::Constants');

    return grep { -f $Cpanel::ConfigFiles::DORMANT_SERVICES_DIR . "/$_/enabled" } @Cpanel::Config::Constants::DORMANT_SERVICES_LIST;
}

1;
