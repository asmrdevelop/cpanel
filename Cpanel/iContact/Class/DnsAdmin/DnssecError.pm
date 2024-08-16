package Cpanel::iContact::Class::DnsAdmin::DnssecError;

# cpanel - Cpanel/iContact/Class/DnsAdmin/DnssecError.pm
#                                                  Copyright 2022 cPanel, L.L.C.
#                                                           All rights reserved.
# copyright@cpanel.net                                         http://cpanel.net
# This code is subject to the cPanel license. Unauthorized copying is prohibited

use warnings;
use strict;

use parent qw(
  Cpanel::iContact::Class::FromUserAction
);

=encoding utf-8

=head1 NAME

Cpanel::iContact::Class::DnsAdmin::DnssecError

=head1 SYNOPSIS

    use Cpanel::Notify ();

    Cpanel::Notify::notification_class(
        'class'            => 'DnsAdmin::DnssecError',
        'application'      => 'DnsAdmin',
        'constructor_args' => [
            'origin'            => 'DnsAdmin DNSSEC Sync Keys',
            'source_ip_address' => $ENV{'REMOTE_ADDR'},
            'zone'              => $zone,
            'failed_peers'      => \@failed,
        ]
    );

=head1 DESCRIPTION

This module is used to notify when a cPanel DNS cluster peer fails to serve DNSSEC records for a zone after a keysync.

=cut

my @required_args = qw(
  zone
  failed_peers
);

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
        'dnssec_script'      => $self->_get_dnssec_sync_script(),
        %{ $self->{'_opts'} }
    );
}

sub _get_cluster_status_url {
    my ($self) = @_;

    return 'https://' . $self->{'_opts'}{'host_server'} . ':2087/scripts7/clusterstatus';
}

sub _get_dnssec_sync_script {
    my ($self) = @_;
    return "/usr/local/cpanel/scripts/dnssec-cluster-keys --sync --zone=" . $self->{'_opts'}{'zone'};
}

1;
