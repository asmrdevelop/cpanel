package Cpanel::iContact::Class::AutoSSL::DynamicDNSNewCertificate;

# cpanel - Cpanel/iContact/Class/AutoSSL/DynamicDNSNewCertificate.pm
#                                                  Copyright 2022 cPanel, L.L.C.
#                                                           All rights reserved.
# copyright@cpanel.net                                         http://cpanel.net
# This code is subject to the cPanel license. Unauthorized copying is prohibited

use cPstrict;

=encoding utf-8

=head1 NAME

Cpanel::iContact::Class::AutoSSL::DynamicDNSNewCertificate

=head1 SYNOPSIS

    use Cpanel::Notify ();

    Cpanel::Notify::notification_class(
        'class'            => 'AutoSSL::DynamicDNSNewCertificate',
        'application'      => 'AutoSSL::DynamicDNSNewCertificate',
        'constructor_args' => [

            # Redundancy for legacy reasons …
            username                          => $username,
            to                                => $username,
            user                              => $username,
            notification_targets_user_account => 1,

            domain => $fqdn,
            certificate_id => $cert_id,
        ]
    );

=head1 DESCRIPTION

This notification informs the user that AutoSSL has procured a new
certificate for a specific dynamic DNS subdomain.

=cut

#----------------------------------------------------------------------

use parent qw(
  Cpanel::iContact::Class
);

use Cpanel                         ();
use Cpanel::DnsUtils::Name         ();
use Cpanel::Config::LoadCpUserFile ();
use Cpanel::Services::Ports        ();
use Cpanel::Themes::Get            ();

#----------------------------------------------------------------------

sub _required_args ($self) {

    return (
        $self->SUPER::_required_args(),
        'certificate_id',
        'username',
        'domain',
    );
}

sub _template_args ($self) {

    my $domain = $self->_get_best_url_domain();

    my $cp_port = $Cpanel::Services::Ports::SERVICE{'cpanels'};

    my $theme = $Cpanel::CPDATA{'RS'} || Cpanel::Themes::Get::cpanel_default_theme();

    my $dl_url = "https://$domain:$cp_port/frontend/$theme/dynamic-dns/index.html#/ssl?cert_id=$self->{'_opts'}{'certificate_id'}";

    return (
        $self->SUPER::_template_args(),
        base_domain  => $domain,
        download_url => $dl_url,
        %{ $self->{'_opts'} }{ 'certificate_id', 'domain' },
    );
}

sub _get_best_url_domain ($self) {
    my $cpuser_hr = Cpanel::Config::LoadCpUserFile::load_or_die(
        $self->{'_opts'}{'username'},
    );

    my $cert_domain = $self->{'_opts'}{'domain'};

    my @domains = ( $cpuser_hr->{'DOMAIN'}, @{ $cpuser_hr->{'DOMAINS'} } );

    my @matches = grep { Cpanel::DnsUtils::Name::is_subdomain_of( $cert_domain, $_ ) } @domains;

    my $shortest = ( sort { length $a <=> length $b } @matches )[0];

    return $shortest;
}

1;
