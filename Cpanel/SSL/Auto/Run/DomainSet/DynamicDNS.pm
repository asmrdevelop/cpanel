package Cpanel::SSL::Auto::Run::DomainSet::DynamicDNS;

# cpanel - Cpanel/SSL/Auto/Run/DomainSet/DynamicDNS.pm
#                                                  Copyright 2022 cPanel, L.L.C.
#                                                           All rights reserved.
# copyright@cpanel.net                                         http://cpanel.net
# This code is subject to the cPanel license. Unauthorized copying is prohibited

use cPstrict;

=encoding utf-8

=head1 NAME

Cpanel::SSL::Auto::Run::DomainSet::DynamicDNS

=head1 SYNOPSIS

    my $dset = Cpanel::SSL::Auto::Run::DomainSet::DynamicDNS->new(
        $provider_obj,
        $username,
        {
            domain => 'example.com',
            certificate => $cert_obj_or_undef,
        },
    );

=head1 DESCRIPTION

This class implements L<Cpanel::SSL::Auto::Run::DomainSet> for dynamic
DNS domains.

=cut

#----------------------------------------------------------------------

use parent (
    'Cpanel::SSL::Auto::Run::DomainSet',
);

use Cpanel::Imports;

# Sibling classes (e.g., Vhost.pm) may set a different value:
use constant _can_wildcard_reduce => 0;

#----------------------------------------------------------------------

=head1 CONSTRUCTOR ARGUMENTS

\%DATA given to C<new()> should contain:

=over

=item * C<domain>

=item * C<certificate> (can be missing/undef)

=back

=cut

#----------------------------------------------------------------------

sub _get_certificate_object ($self) {
    return $self->{'certificate'};
}

sub _get_defects ($self) {
    my @defects;

    if ( !$self->{'certificate'} ) {
        push @defects, locale()->maketext('No valid [asis,SSL] certificate is available, or all valid certificates will expire soon.');
    }

    return @defects;
}

sub _name ($self) {
    return $self->{'domain'};
}

sub _domains_ar ($self) {
    return [ $self->{'domain'} ];
}

sub _unsecured_domains_ar ($self) {
    return [ $self->{'certificate'} ? () : $self->{'domain'} ];
}

1;
