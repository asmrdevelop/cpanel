package Cpanel::iContact::Class::SSL::CertificateExpiring;

# cpanel - Cpanel/iContact/Class/SSL/CertificateExpiring.pm
#                                                  Copyright 2022 cPanel, L.L.C.
#                                                           All rights reserved.
# copyright@cpanel.net                                         http://cpanel.net
# This code is subject to the cPanel license. Unauthorized copying is prohibited

=encoding utf-8

=head1 NAME

Cpanel::iContact::Class::SSL::CertificateExpiring - Hook module for the SSL Certificate Expiry iContact Notification

=head1 SYNOPSIS

    use Cpanel::Notify ();

    Cpanel::Notify::notification_class(
        'class'            => 'SSL::CertificateExpiring',
        'application'      => 'SSL::CertificateExpiring',
        'constructor_args' => [
            username                          => $user,
            to                                => $user,
            user                              => $user,
            vhost_name                        => $vhost_name,
            notification_targets_user_account => 1,
            origin                            => "AutoSSL",
            source_ip_address                 => Cpanel::IP::Remote::get_current_remote_ip(),
        ]
    );

=head1 DESCRIPTION

Hook module for the SSL Certificate Expiring iContact Notification

This module should not be used for AutoSSL certificates.
Please use Cpanel::iContact::Class::AutoSSL::CertificateExpiring
instead for AutoSSL certificates.

Currently this module is called by scripts/notify_expiring_certificates

=cut

use strict;
use warnings;

use List::MoreUtils qw(uniq);

use parent qw(
  Cpanel::iContact::Class
);

use Cpanel::Apache::TLS                     ();
use Cpanel::Market::Tiny                    ();
use Cpanel::SSL::Objects::Certificate::File ();
use Cpanel::WebVhosts                       ();
use Cpanel::WildcardDomain                  ();
use Cpanel::Time::Split                     ();

sub _required_args {
    my ($class) = @_;

    return (
        $class->SUPER::_required_args(),
        'username',
        'vhost_name',
    );
}

=head2 get_vhost_domains

Return a an arrayref of hashrefs that represent each
domain on the virtual host and if the certificate
covers the domain.

Example
[
  {
    'name' => 'domain.tld',
    'coverted' => 1,
  },
  {
    'name' => 'other.domain.tld',
    'coverted' => 0,
  },
  ...
]

=cut

sub get_vhost_domains {
    my ($self) = @_;

    my $vh_name = $self->{'_opts'}{'vhost_name'};
    return $self->{'_vh_domains'}{$vh_name} ||= do {
        my $username   = $self->{'_opts'}{'username'};
        my @vhost_data = Cpanel::WebVhosts::list_ssl_capable_domains( $username, $vh_name );

        #Don’t filter by “vhost_is_ssl” here for testing purposes.
        my @vh_domains   = uniq sort map { $_->{'vhost_name'} eq $vh_name ? $_->{'domain'} : () } @vhost_data;
        my $cert_obj     = $self->get_cert_obj();
        my @cert_domains = @{ $cert_obj->domains() };

        for my $vd (@vh_domains) {
            my $covered = grep { Cpanel::WildcardDomain::wildcard_domains_match( $vd, $_ ) } @cert_domains;

            $vd = {
                name    => $vd,
                covered => $covered ? 1 : 0,
            };
        }

        # Sort by covered first, and by name second
        @vh_domains = sort { $b->{'covered'} <=> $a->{'covered'} || $a->{'name'} cmp $b->{'name'} } @vh_domains;

        \@vh_domains;
    };
}

=head2 get_cert_obj

Returns a Cpanel::SSL::Objects::Certificate for the certificate PEM
that was passed in when this object was created via the iContact
interface.

=cut

sub get_cert_obj {
    my ($self) = @_;

    my $path = Cpanel::Apache::TLS->get_certificates_path( $self->{'_opts'}{'vhost_name'} );

    return $self->{'_cert_obj'} ||= Cpanel::SSL::Objects::Certificate::File->new( path => $path );
}

sub _template_args {
    my ($self) = @_;

    my $cert_obj = $self->get_cert_obj();
    my $now      = time();

    my $remaining_time = ( $cert_obj->not_after() - $now );
    return (
        $self->SUPER::_template_args(),
        enabled_providers_count    => scalar Cpanel::Market::Tiny::get_enabled_providers_count(),
        certificate_pem            => $cert_obj->text(),
        certificate                => $cert_obj,
        vhost_name                 => $self->{'_opts'}{'vhost_name'},
        'ssl_tls_manager_url'      => $self->assemble_cpanel_url('?goto_app=SSL_TLS_Manager'),
        'ssl_tls_wizard_url'       => $self->assemble_cpanel_url('?goto_app=SSL_TLS_Wizard'),
        'remaining_time'           => $remaining_time,
        'remaining_time_localized' => Cpanel::Time::Split::seconds_to_locale($remaining_time),
        vhost_domains              => $self->get_vhost_domains(),
    );
}

1;
