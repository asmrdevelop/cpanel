# cpanel - Cpanel/iContact/Class/Market/WHMPluginInstall.pm
#                                                  Copyright 2022 cPanel, L.L.C.
#                                                           All rights reserved.
# copyright@cpanel.net                                         http://cpanel.net
# This code is subject to the cPanel license. Unauthorized copying is prohibited

package Cpanel::iContact::Class::Market::WHMPluginInstall;

use strict;
use warnings;

use parent qw(
  Cpanel::iContact::Class
);

sub _required_args {
    my ($class) = @_;

    return (
        $class->SUPER::_required_args(),
        'product',
        'error',
        'url',
    );
}

sub _template_args {
    my ($self) = @_;

    return (
        $self->SUPER::_template_args(),
        product => $self->{_opts}{product},
        error   => $self->{_opts}{error},
        url     => $self->{_opts}{url},
    );
}

1;

__END__

=head1 Cpanel::iContact::Class::Market::WHMPluginInstall

Used to inform users of install failures whenever installing plugins they purchased via the WHM marketplace
