package Cpanel::WebVhosts::AutoDomains;

# cpanel - Cpanel/WebVhosts/AutoDomains.pm         Copyright 2022 cPanel, L.L.C.
#                                                           All rights reserved.
# copyright@cpanel.net                                         http://cpanel.net
# This code is subject to the cPanel license. Unauthorized copying is prohibited

use cPstrict;

=encoding utf-8

=head1 NAME

Cpanel::WebVhosts::AutoDomains

=head1 DISCUSSION

This module attempts to corral all of the different subdomains that we
create for the user automatically. There are a few different patterns
in play that dictate which collection includes which module.

The idea is to mitigate against the duplication of this information
in our codebase. That mitigation won’t be complete, but it can
at least help.

=head1 CONSTANTS

These all return lists of leftmost domain labels (e.g., C<www>).

#----------------------------------------------------------------------

=head2 ON_ALL_CREATED_DOMAINS()

These labels are added to every B<NON-WILDCARD> domain that is created
via API submission: subdomains, parked domains, and addon domains.
The label is added regardless of whether the created domain receives
its own DNS zone.

These domains appear in the web vhosts config (i.e.,
“userdata”), but do B<not> appear in the cpuser file.

The classic example is C<www>.

B<IMPORTANT:> These domains do B<NOT> apply to wildcard domains.
If you’re using this list, you B<MUST> take care here, otherwise
you may inadvertently create names like C<www.*.example.com>.

=cut

use constant ON_ALL_CREATED_DOMAINS => ('www');

#----------------------------------------------------------------------

=head2 WEB_SUBDOMAINS_FOR_ZONE()

These labels are added to each created DNS zone, and B<if> the user
hasn’t already created the resulting FQDN via the API, will add the
FQDN onto the respective Apache virtual host.

The classic example is C<mail>, which we add to every DNS zone but
which the user can directly create by removing that automatically
created DNS zone and doing a manual domain creation via API call.
If that hasn’t happened, then the FQDN is added to the DNS zone’s
corresponding virtual host.

These domains appear in the web vhosts config (i.e.,
“userdata”), but do B<not> appear in the cpuser file.

=cut

use constant WEB_SUBDOMAINS_FOR_ZONE => ('mail');

#----------------------------------------------------------------------

=head2 OPTIONAL_SUBDOMAINS_FOR_ZONE()

These labels are added to each created DNS zone, and B<if> the user
hasn’t enabled related features, will add the
FQDN onto the respective Apache virtual host.

The classic example is C<ipv6>, which we add to every DNS zone but
which the user can directly create by removing that automatically
created DNS zone and doing a manual domain creation via API call.
If that hasn’t happened, then the FQDN is added to the DNS zone’s
corresponding virtual host.

These domains do not appear in the main web vhosts config (i.e.,
“userdata”), do B<not> appear in the cpuser file, but do appear
in the parent domain web vhosts config (i.e.,“userdata”).

=cut

use constant OPTIONAL_SUBDOMAINS_FOR_ZONE => ('ipv6');

#----------------------------------------------------------------------

my %_EVERY_USER_PROXY_REDIRECTS_KV;
my %_ALL_POSSIBLE_PROXY_REDIRECTS_KV;

use constant PRODUCT_CUSTOM_DOMAINS => qw< cpanel >;

#TODO: There’s no need to have ProxyPass here, repeated for
#every single service (formerly proxy) subdomain. It can just be once, at the global level.
BEGIN {

    %_EVERY_USER_PROXY_REDIRECTS_KV = (    #
        map {                              #
            $_ => 'RewriteRule ^/(.*) /___proxy_subdomain_cpanel/$1 [PT]' . "\n\t\t" . 'ProxyPass "/___proxy_subdomain_cpanel" "http://127.0.0.1:2082" max=1 retry=0'    #
          }    #
          PRODUCT_CUSTOM_DOMAINS
    );

    %_ALL_POSSIBLE_PROXY_REDIRECTS_KV = (
        %_EVERY_USER_PROXY_REDIRECTS_KV,
        webdisk      => 'RewriteRule ^/(.*) /___proxy_subdomain_webdisk/$1 [PT]' . "\n\t\t" . 'ProxyPass "/___proxy_subdomain_webdisk" "http://127.0.0.1:2077" max=1 retry=0',
        webmail      => 'RewriteRule ^/(.*) /___proxy_subdomain_webmail/$1 [PT]' . "\n\t\t" . 'ProxyPass "/___proxy_subdomain_webmail" "http://127.0.0.1:2095" max=1 retry=0',
        whm          => 'RewriteRule ^/(.*) /___proxy_subdomain_whm/$1 [PT]' . "\n\t\t" . 'ProxyPass "/___proxy_subdomain_whm" "http://127.0.0.1:2086" max=1 retry=0',
        cpcalendars  => 'RewriteRule ^/(.*) /___proxy_subdomain_cpcalendars/$1 [PT]' . "\n\t\t" . 'ProxyPass "/___proxy_subdomain_cpcalendars" "http://127.0.0.1:2079" max=1 retry=0',
        cpcontacts   => 'RewriteRule ^/(.*) /___proxy_subdomain_cpcontacts/$1 [PT]' . "\n\t\t" . 'ProxyPass "/___proxy_subdomain_cpcontacts" "http://127.0.0.1:2079" max=1 retry=0',
        autodiscover => 'RewriteRule ^ http://127.0.0.1/cgi-sys/autodiscover.cgi [P]',
        autoconfig   => 'RewriteRule ^ http://127.0.0.1/cgi-sys/autoconfig.cgi [P]',
    );
}

#----------------------------------------------------------------------

=head2 %label_rule = PROXY_SUBDOMAIN_REDIRECTS_KV()

A list of key/value pairs. The keys are the service (formerly proxy) subdomain
labels, and each value is the associated Apache rewrite rule string.

This logic is here to reduce duplication of the service (formerly proxy) subdomain
labels.

=cut

use constant PROXY_SUBDOMAIN_REDIRECTS_KV => (%_ALL_POSSIBLE_PROXY_REDIRECTS_KV);

#----------------------------------------------------------------------

=head2 %label_rule = PROXY_SUBDOMAIN_WEBSOCKET_REDIRECTS_KV()

Similar to C<PROXY_SUBDOMAIN_REDIRECTS_KV()>, but it contains redirects
for WebSocket connections.

=cut

use constant PROXY_SUBDOMAIN_WEBSOCKET_REDIRECTS_KV => map { $_ => ( $_ALL_POSSIBLE_PROXY_REDIRECTS_KV{$_} =~ s<http:><ws:>r =~ s<\n.*><>r =~ s<(___proxy_subdomain_)><${1}ws_>r ) } qw( cpanel webmail whm );

#----------------------------------------------------------------------

=head2 PROXIES_FOR_EVERYONE()

These labels are the service (formerly proxy) subdomains that pertain to everyone.
The classic example is C<cpanel>.

=cut

use constant PROXIES_FOR_EVERYONE => ( sort keys %_EVERY_USER_PROXY_REDIRECTS_KV );

#----------------------------------------------------------------------

=head1 ALL_POSSIBLE_MAIL_PROXIES()

Every possible mail-related service (formerly proxy) subdomain.

=cut

use constant ALL_POSSIBLE_MAIL_PROXIES => qw(
  autoconfig
  autodiscover
  cpcalendars
  cpcontacts
  webmail
);

#----------------------------------------------------------------------

=head2 ALL_POSSIBLE_PROXIES()

Every possible service (formerly proxy) subdomain. This is a superset of
C<PROXIES_FOR_EVERYONE> and also of C<ALL_POSSIBLE_MAIL_PROXIES()>.

=cut

use constant ALL_POSSIBLE_PROXIES => ( sort keys %_ALL_POSSIBLE_PROXY_REDIRECTS_KV );

#----------------------------------------------------------------------

=head2 ALWAYS_RESERVED()

These subdomains are reserved for all domains.

=cut

use constant ALWAYS_RESERVED => qw<
  ftp
  ipv6
  mail
  localhost
  www
>;

#----------------------------------------------------------------------

=head2 RESERVED_FOR_SUBS()

These subdomains are reserved for all subdomains.

=cut

use constant RESERVED_FOR_SUBS => qw<

  www
  default._domainkey

  whm
>, PRODUCT_CUSTOM_DOMAINS;

#----------------------------------------------------------------------

=head2 ALL_POSSIBLE_AUTO_DOMAINS()

Every possible label that can be auto-added to every created domain
for any reason.
This list is useful to prevent creation of users whose auto-subdomains
are already controlled by other users, e.g.:

1) C<bob> owns the domains C<cpanel.bill.com>.

2) The admin tries to create user C<bill> with domain C<bill.com>.

We want to prevent #2 above because C<bill> would not own all of the
expected auto-subdomains, which would have undesirable ramifications
such as breaking DCV checks for service (formerly proxy) subdomains.

=cut

use constant ALL_POSSIBLE_AUTO_DOMAINS => (
    sort keys {
        map { $_ => undef } ON_ALL_CREATED_DOMAINS(),
        WEB_SUBDOMAINS_FOR_ZONE(),
        ALL_POSSIBLE_PROXIES(),
        ALWAYS_RESERVED(),
        RESERVED_FOR_SUBS(),
    }->%*
);

sub all_possible_proxy_subdomains_regex {
    my @sub_domains = ALL_POSSIBLE_PROXIES();
    return join( '|', map { quotemeta($_) } sort @sub_domains );
}

#----------------------------------------------------------------------

=head2 ALL_POSSIBLE_HOSTNAME_SUBDOMAINS()

Every possible label that can be added to a hostname SSL certificate.

=cut

use constant ALL_POSSIBLE_HOSTNAME_SUBDOMAINS => (
    sort keys {
        map { $_ => undef } ON_ALL_CREATED_DOMAINS(),
        WEB_SUBDOMAINS_FOR_ZONE(),
        OPTIONAL_SUBDOMAINS_FOR_ZONE(),
        ALL_POSSIBLE_PROXIES(),
    }->%*
);

1;
