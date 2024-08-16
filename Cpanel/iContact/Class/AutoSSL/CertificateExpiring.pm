package Cpanel::iContact::Class::AutoSSL::CertificateExpiring;

# cpanel - Cpanel/iContact/Class/AutoSSL/CertificateExpiring.pm
#                                                  Copyright 2022 cPanel, L.L.C.
#                                                           All rights reserved.
# copyright@cpanel.net                                         http://cpanel.net
# This code is subject to the cPanel license. Unauthorized copying is prohibited

=encoding utf-8

=head1 NAME

Cpanel::iContact::Class::AutoSSL::CertificateExpiring - Hook module for the AutoSSL Certificate Expiry iContact Notification

=head1 SYNOPSIS

    use Cpanel::Notify ();

    Cpanel::Notify::notification_class(
        'class'            => 'AutoSSL::CertificateExpiring',
        'application'      => 'AutoSSL::CertificateExpiring',
        'constructor_args' => [
            username                          => $user,
            to                                => $user,
            user                              => $user,
            vhost_name                        => $vhost_name,
            notification_targets_user_account => 1,
            origin                            => "AutoSSL",
            replace_after_time                => 123456789,
            source_ip_address                 => Cpanel::IP::Remote::get_current_remote_ip(),
        ]
    );

=head1 DESCRIPTION

Hook module for the AutoSSL Certificate Expiring iContact Notification

Currently this module is called by bin/autossl_check

Notify when AutoSSL cannot request a certificate because all domains on the website have failed DCV.

=cut

use strict;
use warnings;

use Cpanel::Set                     ();
use Cpanel::SSL::Auto::Problems     ();
use Cpanel::SSL::Auto::Config::Read ();

use parent qw(
  Cpanel::iContact::Class::SSL::CertificateExpiring
);

sub _template_args {
    my ($self) = @_;

    my $username                  = $self->{'_opts'}{'username'};
    my $vh_domains_ar             = $self->get_vhost_domains();
    my %domains_to_get_status_for = map { $_->{'name'} => 1 } @$vh_domains_ar;

    my $autossl_provider = Cpanel::SSL::Auto::Config::Read->new()->get_provider();

    my $probs_ar = [ grep { $domains_to_get_status_for{ $_->{'domain'} } } @{ Cpanel::SSL::Auto::Problems->new()->get_for_user($username) } ];

    return (
        'autossl_provider'   => $autossl_provider,
        'autossl_problems'   => $probs_ar,
        'ssl_tls_status_url' => $self->assemble_cpanel_url('?goto_app=SSL_TLS_Status'),
        'old_dcv_failures'   => $self->_get_old_dcv_failures($probs_ar),
        $self->SUPER::_template_args(),
    );

}

#Ideally this would not be in this module since the CertificateExpiring
#notification itself doesn’t use this data point; however, it’s useful for
#CertificateExpiringCoverage and CertificateRenewalCoverage, both of which
#subclass this module.
sub _get_old_dcv_failures {
    my ( $self, $probs_ar ) = @_;

    my @old_secured_domains = Cpanel::Set::intersection(
        $self->get_cert_obj()->domains(),
        [ map { $_->{'name'} } @{ $self->get_vhost_domains() } ],
    );

    my %domain_prob = map { $_->{'domain'} => $_ } @$probs_ar;

    my @old_dcv_failures = grep { $domain_prob{$_} } @old_secured_domains;

    return \@old_dcv_failures;
}

1;
