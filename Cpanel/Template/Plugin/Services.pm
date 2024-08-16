package Cpanel::Template::Plugin::Services;

# cpanel - Cpanel/Template/Plugin/Services.pm      Copyright 2022 cPanel, L.L.C.
#                                                           All rights reserved.
# copyright@cpanel.net                                         http://cpanel.net
# This code is subject to the cPanel license. Unauthorized copying is prohibited

use strict;
use warnings;

=encoding utf-8

=head1 NAME

Cpanel::Template::Plugin::Services - Template Toolkit plugin for services

=head1 SYNOPSIS

    [% use Services %]

    [% IF Services.is_service_provided('servicename') %]
        [%# Do something when the service is enabled %]
    [% END %]

=cut

use parent 'Cpanel::Template::Plugin::BaseDefault';

=head2 new

Constructor

=over 2

=item Input

=over 3

None

=back

=item Output

=over 3

=item C<SCALAR>

A new C<Cpanel::Template::Plugin::Services> object

=back

=back

=cut

sub new {
    return bless {}, $_[0];
}

=head2 is_service_provided

Determines if a service is provided to the server. We define
provided as enabled locally or enable on a remote system.

=over 2

=item Input

=over 3

=item C<SCALAR>

The name of the service module to check to see if its is provided

=back

=item Output

=over 3

Returns 1 if the service is provided, 0 otherwise

=back

=back

=cut

sub is_service_provided {
    return $_[0]->{'_is_service_provided'}{ $_[1] } if exists $_[0]->{'_is_service_provided'}{ $_[1] };
    require Cpanel::Services::Enabled;
    return ( $_[0]->{'_is_service_provided'}{ $_[1] } = Cpanel::Services::Enabled::is_provided( $_[1] ) );
}

=head2 are_services_provided

Determines if the specified services are provided to the server

=over 2

=item Input

=over 3

This method is a thin wrapper around C<Cpanel::Services::Enabled::are_services_provided>, see that module for specifics on accepted inputs

=back

=item Output

=over 3

Outputs 1 if the services are enabled, 0 otherwise

=back

=back

=cut

sub are_services_provided {
    my ( $self, $services ) = @_;
    require Cpanel::Services::Enabled;
    return Cpanel::Services::Enabled::are_provided($services);
}

1;
