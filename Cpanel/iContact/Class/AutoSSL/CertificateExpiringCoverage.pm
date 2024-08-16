package Cpanel::iContact::Class::AutoSSL::CertificateExpiringCoverage;

# cpanel - Cpanel/iContact/Class/AutoSSL/CertificateExpiringCoverage.pm
#                                                  Copyright 2022 cPanel, L.L.C.
#                                                           All rights reserved.
# copyright@cpanel.net                                         http://cpanel.net
# This code is subject to the cPanel license. Unauthorized copying is prohibited

=encoding utf-8

=head1 NAME

Cpanel::iContact::Class::AutoSSL::CertificateExpiringCoverage - Hook module for the AutoSSL Certificate Expiring Coverage iContact Notification

=head1 DESCRIPTION

This class allows distinct contact settings for partial DCV failure.

The L<Cpanel::iContact::Class::AutoSSL::CertificateExpiring> module
is used for full DCV failure.

This module is used for partial DCV failure.

Notify when AutoSSL defers certificate renewal because a
domain on the current certificate has failed DCV.

This notification is only sent after has deferred the renewal
for at least half of the renewal period. (DAYS_TO_RENEW / 2)

=cut

use strict;
use warnings;

use parent qw(
  Cpanel::iContact::Class::AutoSSL::CertificateExpiring
);

use Cpanel::SSL::VhostCheck ();

sub _template_args {
    my ($self) = @_;

    return (
        $self->SUPER::_template_args(),
        'replace_after_time' => $self->_replace_after_time(),
    );
}

sub _replace_after_time {
    my ($self) = @_;

    my $not_after = $self->get_cert_obj()->not_after();
    return 1 + $not_after - ( $Cpanel::SSL::VhostCheck::MIN_VALIDITY_DAYS_LEFT_BEFORE_CONSIDERED_ALMOST_EXPIRED * 86400 );
}

1;
