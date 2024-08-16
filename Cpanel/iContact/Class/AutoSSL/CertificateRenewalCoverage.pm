package Cpanel::iContact::Class::AutoSSL::CertificateRenewalCoverage;

# cpanel - Cpanel/iContact/Class/AutoSSL/CertificateRenewalCoverage.pm
#                                                  Copyright 2022 cPanel, L.L.C.
#                                                           All rights reserved.
# copyright@cpanel.net                                         http://cpanel.net
# This code is subject to the cPanel license. Unauthorized copying is prohibited

=encoding utf-8

=head1 NAME

Cpanel::iContact::Class::AutoSSL::CertificateRenewalCoverage - Hook module for the AutoSSL Certificate Renewal Coverage iContact Notification

=head1 SYNOPSIS

    use Cpanel::Notify ();

    Cpanel::Notify::notification_class(
        'class'            => 'AutoSSL::CertificateRenewalCoverage',
        'application'      => 'AutoSSL::CertificateRenewalCoverage',
        'constructor_args' => [
            username                          => $user,
            to                                => $user,
            user                              => $user,
            vhost_name                        => $vhost_name,
            notification_targets_user_account => 1,
            origin                            => "AutoSSL",
            source_ip_address                 => Cpanel::IP::Remote::get_current_remote_ip(),
            unsecured_domains                 => $unsecured_domains_on_vhost_ar,
        ]
    );

=head1 DESCRIPTION

Hook module for the AutoSSL Certificate Renewal Coverage warning iContact Notification

Currently this module is called by bin/autossl_check.pl

Notify when AutoSSL will not secure new domains because a domain on the current certificate has failed DCV.

This only fires prior to the DAYS_TO_REPLACE / 2 mark (i.e., “green zone”
and “yellow zone”).

=cut

use strict;
use warnings;

use Cpanel::SSL::VhostCheck ();

use parent qw(
  Cpanel::iContact::Class::AutoSSL::CertificateExpiring
);

sub _template_args {
    my ($self) = @_;

    my $not_after = $self->get_cert_obj()->not_after();

    return (
        'must_replace_window_days' => $Cpanel::SSL::VhostCheck::MIN_VALIDITY_DAYS_LEFT_BEFORE_CONSIDERED_ALMOST_EXPIRED,
        $self->SUPER::_template_args(),
    );
}

1;
