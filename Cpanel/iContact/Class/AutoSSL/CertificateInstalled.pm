package Cpanel::iContact::Class::AutoSSL::CertificateInstalled;

# cpanel - Cpanel/iContact/Class/AutoSSL/CertificateInstalled.pm
#                                                  Copyright 2022 cPanel, L.L.C.
#                                                           All rights reserved.
# copyright@cpanel.net                                         http://cpanel.net
# This code is subject to the cPanel license. Unauthorized copying is prohibited

#FIXME: Move this to a different namespace since it now has things like
#order ID, provider, and certificate ID.

=encoding utf-8

=head1 NAME

Cpanel::iContact::Class::AutoSSL::CertificateInstalled - Hook module for the Certificate Installed iContact Notification

=head1 SYNOPSIS

    use Cpanel::Notify ();

    Cpanel::Notify::notification_class(
        'class'            => 'AutoSSL::CertificateInstalled',
        'application'      => 'AutoSSL::CertificateInstalled',
        'constructor_args' => [
            username                          => $user,
            'key_id'                          => $key_id,
            to                                => $user,
            user                              => $user,
            vhost_name                        => $vhost_name,
            notification_targets_user_account => 1,
            origin                            => "AutoSSL",
            source_ip_address                 => Cpanel::IP::Remote::get_current_remote_ip(),
            added_domains                     => \@added_fqdns,
        ]
    );

=head1 DESCRIPTION

Hook module for the Certificate Installed iContact Notification

=cut

use strict;
use warnings;

use parent qw(
  Cpanel::iContact::Class::SSL::CertificateExpiring
);

use Cpanel::LoadModule ();

sub _required_args {
    my ($class) = @_;

    return (
        $class->SUPER::_required_args(),
        'key_id',
    );
}

sub _template_args {
    my ($self) = @_;

    my %args = $self->SUPER::_template_args();

    my %added = map { $_ => 1 } @{ $self->{'_opts'}{'added_domains'} };

    for my $vhdomain_hr ( @{ $args{'vhost_domains'} } ) {
        $vhdomain_hr->{'added'} = delete $added{ $vhdomain_hr->{'name'} };
    }

    if ( my @leftover = keys %added ) {
        warn "Unknown added domain(s) (@leftover) for vhost $args{'vhost_name'}!";
    }

    return (
        %args,
        key_id => $self->{'_opts'}{'key_id'},
    );
}

sub _generic_problem {
    my ( $self, $domain ) = @_;

    Cpanel::LoadModule::load_perl_module('Cpanel::Time::ISO');

    my $lh = $self->locale();

    $lh->set_context_plain();

    my $prob_hr = {
        domain  => $domain,
        problem => $lh->maketext( 'There is no recorded error on the system for “[_1]”. This might mean that this domain failed [output,abbr,DCV,Domain Control Validation] when the system requested the new certificate, but the domain has since passed [asis,DCV].', $domain ),
        time    => Cpanel::Time::ISO::unix2iso(),
    };

    $lh->set_context_html();

    return $prob_hr;
}

sub _icontact_args {
    my ( $self, %args ) = @_;

    return (
        $self->SUPER::_icontact_args(%args),
        attach_files => [
            { name => 'certificate.pem', content => \$self->{'_processed_template_args'}{'certificate_pem'} },
        ]
    );
}

1;
