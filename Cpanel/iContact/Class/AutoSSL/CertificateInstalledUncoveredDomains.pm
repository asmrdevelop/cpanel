package Cpanel::iContact::Class::AutoSSL::CertificateInstalledUncoveredDomains;

# cpanel - Cpanel/iContact/Class/AutoSSL/CertificateInstalledUncoveredDomains.pm
#                                                  Copyright 2022 cPanel, L.L.C.
#                                                           All rights reserved.
# copyright@cpanel.net                                         http://cpanel.net
# This code is subject to the cPanel license. Unauthorized copying is prohibited

#FIXME: Move this to a different namespace since it now has things like
#order ID, provider, and certificate ID.

=encoding utf-8

=head1 NAME

Cpanel::iContact::Class::AutoSSL::CertificateInstalledUncoveredDomains

=head1 SYNOPSIS

    use Cpanel::Notify ();

    Cpanel::Notify::notification_class(
        'class'            => 'AutoSSL::CertificateInstalledUncoveredDomains',
        'application'      => 'AutoSSL::CertificateInstalledUncoveredDomains',
        'constructor_args' => [
            username                          => $user,
            'certificate_pem'                 => $cert_pem,
            'key_id'                          => $key_id,
            to                                => $user,
            user                              => $user,
            vhost_name                        => $vhost_name,
            notification_targets_user_account => 1,
            origin                            => "AutoSSL",
            source_ip_address                 => Cpanel::IP::Remote::get_current_remote_ip(),
            uncovered_domains                 => \@uncovered_fqdns,
            added_domains                     => \@added_fqdns,
        ]
    );

=head1 DESCRIPTION

Use this module when AutoSSL clobbers a previous certificate and, in so
doing, accepts a reduction in SSL coverage for the given Apache vhost.

=cut

use strict;
use warnings;

use Cpanel::SSL::Auto::Problems ();

use parent qw(
  Cpanel::iContact::Class::AutoSSL::CertificateInstalled
);

sub _required_args {
    my ($class) = @_;

    return (
        $class->SUPER::_required_args(),
        'uncovered_domains',
    );
}

sub _template_args {
    my ($self) = @_;

    my $problems = Cpanel::SSL::Auto::Problems->new()->get_for_user(
        $self->{'_opts'}{'user'},
    );

    my %domain_problem = map { ( $_->{'domain'} => $_ ) } @$problems;

    my @uncovered_domains_probs = map { $domain_problem{$_} || $self->_generic_problem($_) } @{ $self->{'_opts'}{'uncovered_domains'} };

    return (
        $self->SUPER::_template_args(),
        uncovered_domain_problems => \@uncovered_domains_probs,
        domain_problems           => \%domain_problem,
    );
}

1;
