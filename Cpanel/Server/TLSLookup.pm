package Cpanel::Server::TLSLookup;

# cpanel - Cpanel/Server/TLSLookup.pm              Copyright 2022 cPanel, L.L.C.
#                                                           All rights reserved.
# copyright@cpanel.net                                         http://cpanel.net
# This code is subject to the cPanel license. Unauthorized copying is prohibited

use cPstrict;

=encoding utf-8

=head1 NAME

Cpanel::Server::TLSLookup - Logic to look up TLS certificates for cpsrvd

=head1 SYNOPSIS

    my ($path, $was_valid, $known_match) = Cpanel::Server::TLSLookup::get_path_and_info('foo.example.com');

=head1 DESCRIPTION

This module contains logic that dictates which Domain TLS or Apache TLS
entries cpsrvd will use when fetching a TLS certificate chain to serve up.

=cut

#----------------------------------------------------------------------

use Cpanel::Context                ();
use Cpanel::Domain::TLS            ();
use Cpanel::WebVhosts::AutoDomains ();
use Cpanel::WildcardDomain         ();

# Overridden in tests:
our @_FALLBACK_LABELS = keys %{ { Cpanel::WebVhosts::AutoDomains::PROXY_SUBDOMAIN_REDIRECTS_KV() } };

#----------------------------------------------------------------------

=head1 FUNCTIONS

=head2 ($path, $known_match) = get_domain_and_info($DOMAIN)

Queries on-disk datastores for certificate & key to use for TLS for $DOMAIN.

If such is found, this returns:

=over

=item * The datastore entry that contains the TLS info.

=item * A boolean. If truthy, that means to read from Domain TLS.
If falsy, that means to read from Apache TLS.

=back

=cut

sub get_domain_and_info ($domain) {
    Cpanel::Context::must_be_list();

    my @domain_tls_entries_to_check = (
        _get_lookup_domains($domain),
        _get_parent_fallback_domain_or_nothing($domain),
    );

    for my $d (@domain_tls_entries_to_check) {
        return ( $d, 1 ) if Cpanel::Domain::TLS->has_tls($d);
    }

    # If our Domain TLS lookups yielded nothing, then we deduce the
    # parent domain’s web vhost and load Apache TLS’s certificate
    # for that vhost. This is slow, so hopefully it’s also rare. Note
    # that we do cache the CTX objects, so the lookup overhead below
    # won’t apply more than once per session except under high load.
    if ( my $d = _get_httpd_fallback_domain($domain) ) {

        local ( $!, $@ );
        require Cpanel::Apache::TLS;

        return ( $d, 0 ) if Cpanel::Apache::TLS->has_tls($d);
    }

    return;
}

sub _get_lookup_domains ($domain) {
    Cpanel::Context::must_be_list();

    my @domains = ($domain);

    my $dot_at = index( $domain, '.' );

    # No need to do a wild card check for single label
    # domains such as localhost
    if ( $dot_at > 0 ) {
        push @domains, Cpanel::WildcardDomain::to_wildcards($domain);
    }

    return @domains;
}

sub _get_parent_fallback_domain_or_nothing ($domain) {
    return _if_fallback_eligible( $domain, sub { shift() } );
}

sub _if_fallback_eligible ( $domain, $todo_cr ) {
    my $dot_at = index( $domain, '.' );

    if ( -1 != $dot_at ) {

        # In case neither “whm.example.com” nor “*.example.com” exist,
        # try “example.com”.
        my $first_label = substr( $domain, 0, $dot_at );
        if ( grep { $_ eq $first_label } @_FALLBACK_LABELS ) {
            return $todo_cr->( substr( $domain, 1 + $dot_at ) );
        }
    }

    return;
}

sub _get_httpd_fallback_domain ($domain) {
    return _if_fallback_eligible(
        $domain,

        sub ($stripped) {
            my $vh_name;

            require Cpanel::AcctUtils::DomainOwner::Tiny;
            my $owner = Cpanel::AcctUtils::DomainOwner::Tiny::getdomainowner( $stripped, { default => 'nobody' } );

            if ($owner) {
                require Cpanel::Config::WebVhosts;
                my $wvh = Cpanel::Config::WebVhosts->load($owner);

                $vh_name = $wvh->get_vhost_name_for_domain($stripped);
            }

            return $vh_name;
        }
    );
}

1;
