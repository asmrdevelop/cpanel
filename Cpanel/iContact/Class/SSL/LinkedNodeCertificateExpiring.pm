package Cpanel::iContact::Class::SSL::LinkedNodeCertificateExpiring;

# cpanel - Cpanel/iContact/Class/SSL/LinkedNodeCertificateExpiring.pm
#                                                  Copyright 2022 cPanel, L.L.C.
#                                                           All rights reserved.
# copyright@cpanel.net                                         http://cpanel.net
# This code is subject to the cPanel license. Unauthorized copying is prohibited

use cPstrict;

=encoding utf-8

=head1 NAME

Cpanel::iContact::Class::SSL::LinkedNodeCertificateExpiring

=head1 DESCRIPTION

An iContact notification for when a linked node’s hostname SSL certificate
is expiring.

This module subclasses L<Cpanel::iContact::Class>.

=cut

#----------------------------------------------------------------------

use parent qw(
  Cpanel::iContact::Class
);

use Cpanel::Time::Split ();

#----------------------------------------------------------------------

sub _required_args ($class) {
    return (
        $class->SUPER::_required_args(),
        'node_info',
    );
}

# Tested directly.
sub _template_args ($self) {

    my $cert_obj = $self->{'_opts'}{'node_info'}{'certificate'};

    my $validity_left = $cert_obj->not_after() - _time();

    my $validity_left_loc = Cpanel::Time::Split::seconds_to_locale($validity_left);

    my %node_info = (
        %{ $self->{'_opts'}{'node_info'} },
        validity_left_localized => $validity_left_loc,
    );

    return (
        $self->SUPER::_template_args(),
        node_info => \%node_info,
    );
}

# mocked in tests
sub _time { return time; }

1;
