package Cpanel::Exception::DomainNameStillConfigured;

# cpanel - Cpanel/Exception/DomainNameStillConfigured.pm
#                                                    Copyright 2022 cPanel L.L.C.
#                                                           All rights reserved.
# copyright@cpanel.net                                         http://cpanel.net
# This code is subject to the cPanel license. Unauthorized copying is prohibited

use strict;
use warnings;

use parent qw( Cpanel::Exception );

use Cpanel::LocaleString ();

=encoding utf-8

=head1 NAME

Cpanel::Exception::DomainNameStillConfigured - An exception for when we try to delete a dns zone that is still linked to an HTTP domain

=cut

#Parameters:
#   - domain: the domain name that is still configured
#   - owner: (optional) The owner of the domain
#
sub _default_phrase {
    my ($self) = @_;

    my ( $domain, $owner ) = map { $self->get($_) } qw(domain owner);

    if ( length $owner ) {
        return Cpanel::LocaleString->new(
            'You cannot remove the domain “[_1]” because it is still configured for HTTP use on the “[_2]” account. Remove the domain from the account by deleting the subdomain, addon domain, parked domain, or the linked account.',
            $domain,
            $owner,
        );
    }

    return Cpanel::LocaleString->new(
        'You cannot remove the domain “[_1]” because it is still configured for HTTP use on an active account. Remove the domain from the account by deleting the subdomain, addon domain, parked domain, or the linked account.',
        $domain
    );
}

1;
