package Cpanel::iContact::Class::Check::SSLCertExpired;

# cpanel - Cpanel/iContact/Class/Check/SSLCertExpired.pm
#                                                  Copyright 2022 cPanel, L.L.C.
#                                                           All rights reserved.
# copyright@cpanel.net                                         http://cpanel.net
# This code is subject to the cPanel license. Unauthorized copying is prohibited

use strict;

use parent qw(
  Cpanel::iContact::Class
);

my @args          = qw(origin service hostname url_host);
my @optional_args = qw(certificate certificate_error);

sub _required_args {
    my ($class) = @_;

    return (
        $class->SUPER::_required_args(),
        @args,
    );
}

sub _template_args {
    my ($self) = @_;

    my %template_args = (
        $self->SUPER::_template_args(),
        'manage_service_certificates_url' => $self->_get_manage_service_certificates_url(),
        map { $_ => $self->{'_opts'}{$_} } ( @args, @optional_args ),
    );

    return %template_args;
}

sub _get_manage_service_certificates_url {
    my ($self) = @_;

    return 'https://' . $self->{'_opts'}{'url_host'} . ':2087/scripts2/manageservicecrts';
}

1;
