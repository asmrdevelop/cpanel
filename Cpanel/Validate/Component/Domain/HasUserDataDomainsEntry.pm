package Cpanel::Validate::Component::Domain::HasUserDataDomainsEntry;

# cpanel - Cpanel/Validate/Component/Domain/HasUserDataDomainsEntry.pm
#                                                    Copyright 2022 cPanel L.L.C.
#                                                           All rights reserved.
# copyright@cpanel.net                                         http://cpanel.net
# This code is subject to the cPanel license. Unauthorized copying is prohibited

use strict;
use warnings;
#
use base qw ( Cpanel::Validate::Component );

use Cpanel::Config::userdata::Cache ();
use Cpanel::Exception               ();

=encoding utf-8

=head1 NAME

Cpanel::Validate::Component::Domain::HasUserDataDomainsEntry - Check to see if a domain is in the userdata cache

=head1 SYNOPSIS

    use Cpanel::Validate::Component::Domain::HasUserDataDomainsEntry ();

=head2 init(domain => $domain)

Initilize the module and accept the domain.

=cut

sub init {
    my ( $self, %OPTS ) = @_;

    $self->add_required_arguments(qw( domain ));
    my @validation_arguments = $self->get_validation_arguments();
    @{$self}{@validation_arguments} = @OPTS{@validation_arguments};

    return;
}

=head2 validate()

Check to see if the domain already exists in the userdata cache
and throw the DomainAlreadyExists exception if it does.

=cut

sub validate {
    my ($self) = @_;

    $self->validate_arguments();

    my ($domain) = @{$self}{ $self->get_validation_arguments() };

    if ( my $user = Cpanel::Config::userdata::Cache::get_user($domain) ) {
        if ( $self->has_root() ) {
            die Cpanel::Exception::create( 'DomainAlreadyExists', 'The domain “[_1]” already exists in the userdata for the user “[_2]”.', [ $domain, $user ] );
        }
        else {
            die Cpanel::Exception::create( 'DomainAlreadyExists', 'The domain “[_1]” already exists in the userdata.', [$domain] );
        }
    }

    return;
}

1;
