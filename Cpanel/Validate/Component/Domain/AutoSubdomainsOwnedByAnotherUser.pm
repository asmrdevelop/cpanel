package Cpanel::Validate::Component::Domain::AutoSubdomainsOwnedByAnotherUser;

# cpanel - Cpanel/Validate/Component/Domain/AutoSubdomainsOwnedByAnotherUser.pm
#                                                  Copyright 2022 cPanel, L.L.C.
#                                                           All rights reserved.
# copyright@cpanel.net                                         http://cpanel.net
# This code is subject to the cPanel license. Unauthorized copying is prohibited

=encoding utf-8

=head1 NAME

Cpanel::Validate::Component::Domain::AutoSubdomainsOwnedByAnotherUser

=head1 REQUIRED PARAMETERS

=over

=item C<domain> - the intended domain to create

=back

=head1 METHODS

This takes the same methods as other modules in this namespace:

=cut

use strict;
use warnings;

use parent qw ( Cpanel::Validate::Component );

use Cpanel::AcctUtils::DomainOwner::Tiny ();
use Cpanel::Exception                    ();
use Cpanel::WebVhosts::AutoDomains       ();

=head2 I<OBJ>->init( KEY1 => VALUE1, KEY2 => VALUE2, … )

=cut

sub init {
    my ( $self, %OPTS ) = @_;

    $self->add_required_arguments(qw( domain ));

    my @validation_arguments = $self->get_validation_arguments();
    @{$self}{@validation_arguments} = @OPTS{@validation_arguments};

    return;
}

=head2 I<OBJ>->validate()

=cut

sub validate {
    my ($self) = @_;

    $self->validate_arguments();

    my ($domain) = @{$self}{ $self->get_validation_arguments() };

    for my $label ( Cpanel::WebVhosts::AutoDomains::ALL_POSSIBLE_AUTO_DOMAINS() ) {
        my $owner = Cpanel::AcctUtils::DomainOwner::Tiny::getdomainowner( "$label.$domain", { default => q<> } );
        next if !$owner;

        die Cpanel::Exception::create( 'DomainOwnership', '“[_1]” already controls the domain name “[_2]”.', [ $owner, "$label.$domain" ] );
    }

    return;
}

1;
