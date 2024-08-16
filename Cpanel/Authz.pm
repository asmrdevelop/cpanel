package Cpanel::Authz;

# cpanel - Cpanel/Authz.pm                         Copyright 2022 cPanel, L.L.C.
#                                                           All rights reserved.
# copyright@cpanel.net                                         http://cpanel.net
# This code is subject to the cPanel license. Unauthorized copying is prohibited

use strict;
use warnings;

use Cpanel::Exception ();

=encoding utf-8

=head1 NAME

Cpanel::Authz - Verify authorization for cPanel

=head1 SYNOPSIS

    use Cpanel::Authz;

    Cpanel::Authz::verify_domain_access_or_die('domainnot.owned.tld');
    Cpanel::Authz::verify_domain_access_or_die('domain.owned.tld');

=head2 verify_domain_access_or_die($domain)

Dies if the current initialized user cPanel (via Cpanel::initcp()) user
does not have access to the passed in domain.

=cut

sub verify_domain_access_or_die {
    my ($domain) = @_;

    foreach my $check_domain (@Cpanel::DOMAINS) {
        return if $domain eq $check_domain;
    }

    #It's also possible that the domain doesn't exist on the server, but we shouldn't disclose that in this context (nonroot) either.
    die Cpanel::Exception->create( 'You do not have access to a domain named “[_1]”.', [$domain] );
}

1;
