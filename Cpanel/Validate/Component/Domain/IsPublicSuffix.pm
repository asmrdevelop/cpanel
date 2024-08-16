package Cpanel::Validate::Component::Domain::IsPublicSuffix;

# cpanel - Cpanel/Validate/Component/Domain/IsPublicSuffix.pm
#                                                  Copyright 2022 cPanel, L.L.C.
#                                                           All rights reserved.
# copyright@cpanel.net                                         http://cpanel.net
# This code is subject to the cPanel license. Unauthorized copying is prohibited

=pod

=encoding utf-8

=head1 NAME

Cpanel::Validate::Component::Domain::IsPublicSuffix - Validation frontend for Cpanel::PublicSuffix

=head1 SYNOPSIS

    use Cpanel::Validate::Component::Domain::IsPublicSuffix ();

    my $validator = Cpanel::Validate::Component::Domain::IsPublicSuffix->new( 'domain' => 'cpanel.net' );
    $validator->validate();

=head1 CONSTRUCTOR

=head2 new( domain => ... )

=head3 ARGUMENTS

=over

=item domain - string

Domain which should be checked against the Public Suffix List

=back

=head1 METHODS

=cut

use strict;
use warnings;

use base qw ( Cpanel::Validate::Component );

use Cpanel::Exception    ();
use Cpanel::PublicSuffix ();

sub init {
    my ( $self, %OPTS ) = @_;

    $self->add_required_arguments(qw( domain ));
    my @validation_arguments = $self->get_validation_arguments();
    @{$self}{@validation_arguments} = @OPTS{@validation_arguments};

    return;
}

=head2 validate()

Load the list and perform the validation.

=head3 THROWS

=over

=item Cpanel::Exception::MissingArgument

When the domain parameter was not passed to the constructor

=item Cpanel::Excpetion::DomainNotAllowed

When the provided domain is on the PSL list

=back

=cut

sub validate {
    my ($self) = @_;

    $self->validate_arguments();

    my ($domain) = @{$self}{ $self->get_validation_arguments() };

    if ( Cpanel::PublicSuffix::domain_isa_tld($domain) ) {
        die Cpanel::Exception::create( 'DomainNameNotAllowed', 'The system cannot create the domain “[_1]” because it is a top-level domain or other public suffix. You must use a different domain name.', [$domain] );
    }

    return;
}

1;
