package Cpanel::iContact::Class::DnsAdmin::ClusterError;

# cpanel - Cpanel/iContact/Class/DnsAdmin/ClusterError.pm
#                                                  Copyright 2022 cPanel, L.L.C.
#                                                           All rights reserved.
# copyright@cpanel.net                                         http://cpanel.net
# This code is subject to the cPanel license. Unauthorized copying is prohibited

use strict;

use parent qw(
  Cpanel::iContact::Class::FromUserAction
);

my @required_args = qw(
  origin
  dnspeer
  clusterstatus
  clustererror
  url_host
);

my @template_args = (@required_args);

sub _required_args {
    my ($class) = @_;

    return (
        $class->SUPER::_required_args(),
        @required_args,
    );
}

sub _template_args {
    my ($self) = @_;

    return (
        $self->SUPER::_template_args(),

        'cluster_status_url' => $self->_get_cluster_status_url(),

        map { $_ => $self->{'_opts'}{$_} } (@template_args)
    );
}

sub _get_cluster_status_url {
    my ($self) = @_;

    return 'https://' . $self->{'_opts'}{'url_host'} . ':2087/cgi/clusterstatus.cgi';
}

1;
