package Cpanel::WebVhosts;

# cpanel - Cpanel/WebVhosts.pm                     Copyright 2022 cPanel, L.L.C.
#                                                           All rights reserved.
# copyright@cpanel.net                                         http://cpanel.net
# This code is subject to the cPanel license. Unauthorized copying is prohibited

=pod

=encoding utf-8

=head1 NAME

Cpanel::WebVhosts - Utilities for interacting with web vhosts

=head1 SYNOPSIS

    use Cpanel::WebVhosts ();

    my $docroot = Cpanel::WebVhosts::get_docroot_for_domain();

=head1 DESCRIPTION

This module is meant to take on interactions with web virtual hosts.
It is foreseen that, eventually, internal APIs labeled “Domains” will be
agnostic as to the actual service involved.

This module overlaps somewhat with the DomainInfo modules; however,
where that module focuses on domains specifically (with cPanel’s
traditional concepts of “main”, “addon”, “parked”, and “sub”domains),
this module’s reporting focuses specifically on the vhosts
-- i.e., which sites go to which vhost. It is completely agnostic
as to what is an “addon” domain, a “parked” domain, etc., and instead
considers each of a given vhost’s domains to be coequal.

NOTE: !!!IMPORTANT!!! It is BY DESIGN that this module presents NO MENTION
whatsoever of any of the following to the caller: ServerName, ServerAlias,
main domain, addon domain, parked domain, subdomain

=head1 FUNCTIONS

=cut

use strict;
use warnings;

use Cpanel::Context                ();
use Cpanel::Security::Authz        ();
use Cpanel::WebVhosts::AutoDomains ();

my $auto_subdomains_re = join(
    '|',
    Cpanel::WebVhosts::AutoDomains::ON_ALL_CREATED_DOMAINS(),
    Cpanel::WebVhosts::AutoDomains::WEB_SUBDOMAINS_FOR_ZONE(),
    Cpanel::WebVhosts::AutoDomains::OPTIONAL_SUBDOMAINS_FOR_ZONE(),
    Cpanel::WebVhosts::AutoDomains::ALL_POSSIBLE_PROXIES()
);

=head2 get_docroot_for_domain( DOMAIN )

Fetch the user-owned document root that applies to the given DOMAIN, if any.
This is useful for creating domain-control validation files.

If the user controls DOMAIN, then DOMAIN’s non-SSL vhost’s document root
will be the response. Otherwise, the return is undef.

=cut

sub get_docroot_for_domain {
    my ($domain) = @_;

    Cpanel::Security::Authz::verify_not_root();

    require Cpanel::DomainLookup::DocRoot;
    my $docroot_hr = Cpanel::DomainLookup::DocRoot::getdocroots();

    # If they have an explict auto-created subdomain
    # (cf. $auto_subdomains_re) we return this.
    if ( !$docroot_hr->{$domain} ) {
        $domain = strip_auto_domains($domain);
    }

    return $docroot_hr->{$domain};
}

=head2 strip_auto_domains( DOMAIN )

Removes the auto-created subdomains from a domain string.

Example:

  Input:  autodiscover.koston.org
  Output: koston.org

=cut

sub strip_auto_domains {
    my ($maybe_auto_domain) = @_;

    # case CPANEL-9560:
    # If they do not we need to strip it because they may
    # have a "magic" one that is in the userdata but
    # not in the cpanel users file

    return ( $maybe_auto_domain =~ s<\A (?:$auto_subdomains_re) \.><>rxo );    # /o since this will never change after BEGIN
}

=head2 get_a_domain_on_vhost( VHOST_NAME )

Returns one of the domains on the vhost indicated by the given name.

This does B<NOT> define which of the vhost’s domains get returned.

NOTE: Right now this does nothing useful; however, down the line we may
add the ability to name vhosts, so for future expansion we should assume
no correlation between vhost names and domains.

=cut

sub get_a_domain_on_vhost {
    my ($vhost_name) = @_;
    return $vhost_name;
}

=head2 list_domains()

Returns a list of hashes, one per domain:

    (
        {
            vhost_name => '...',
            domain => '...',
            vhost_is_ssl => 0 or 1,

            #Present only when vhost_is_ssl is true.
            #Contents vary according to configuration.
            proxy_subdomains => [ 'cpanel', 'webmail' ],
        },
        ...
    )

C<vhost_name>, as of 11.56, is always one of the domains on the vhost;
however, this need not always be the case. Users could assign names
themselves, for example, if we added the ability. The only thing
guaranteed about C<vhost_name> is that it and C<vhost_is_ssl> together
uniquely identify the vhost.

At least as of 11.56, an SSL and non-SSL vhost with the same C<vhost_name>
will also have the same domains. THIS MAY NOT ALWAYS BE THE CASE.

=cut

sub list_domains {
    my ($username) = @_;

    Cpanel::Context::must_be_list();

    require Cpanel::Config::WebVhosts;
    my $vhosts_conf  = Cpanel::Config::WebVhosts->load($username);
    my @domains_data = _return_domain_vhosts_list( $username, \&_vhost_list_to_domain_list, $vhosts_conf );

    my %vhpxy_subd;

    for my $dd (@domains_data) {
        next if !$dd->{'vhost_is_ssl'};

        $vhpxy_subd{ $dd->{'vhost_name'} } ||= $vhosts_conf->ssl_proxy_subdomains_zone_hash_for_vhost( $dd->{'vhost_name'} );

        #Should always be an array reference.
        $dd->{'proxy_subdomains'} = $vhpxy_subd{ $dd->{'vhost_name'} }{ $dd->{'domain'} } || [];
    }

    return @domains_data;
}

=head2 list_ssl_capable_domains($username, [$vhost])

Returns a list of hashes, each hash representing a domain capable of receiving an ssl certificate:

    (
        {
            vhost_name => '...',
            domain => '...',
            is_proxy => 0 or 1,
        },
        ...
    )

See above about C<vhost_name>.

=over 2

=item Input

=over 3

=item $username C<SCALAR>

    A cPanel user

=item $vhost C<SCALAR> (optional)

    If a virtual host is specified the result
    will be limited to the domains on the
    virtual host.

=back

=back

=cut

sub list_ssl_capable_domains {
    my ( $username, $vhost ) = @_;

    Cpanel::Context::must_be_list();

    require Cpanel::Config::WebVhosts;
    my $vhosts_conf  = Cpanel::Config::WebVhosts->load($username);
    my @domains_data = _return_domain_vhosts_list( $username, \&_vhost_list_to_domain_list, $vhosts_conf, $vhost );

    my %vhpxy_subd;

    # Only keep vhosts that are non-ssl since the ones that have
    # ssl will be duplicates and will be an incomplete list if
    # there is no ssl vhost yet

    my @non_ssl_domains = grep { !delete $_->{'vhost_is_ssl'} } @domains_data;

    # default to not-proxy, proxies added below
    $_->{'is_proxy'} = 0 for @non_ssl_domains;

    my @ssl_capable_domains = @non_ssl_domains;

    # Now we look at the base non_ssl domains to see if there are any ssl proxies on them
    for my $dd (@non_ssl_domains) {
        $vhpxy_subd{ $dd->{'vhost_name'} } ||= $vhosts_conf->ssl_proxy_subdomains_zone_hash_for_vhost( $dd->{'vhost_name'} );

        my $proxies = $vhpxy_subd{ $dd->{'vhost_name'} }{ $dd->{'domain'} };

        if ($proxies) {

            for my $proxy ( @{$proxies} ) {

                push @ssl_capable_domains, {
                    'domain'     => $proxy . '.' . $dd->{'domain'},
                    'vhost_name' => $dd->{'vhost_name'},
                    'is_proxy'   => 1,
                };

            }
        }

    }

    return @ssl_capable_domains;

}

=head2 list_vhosts()

Returns a list of hashes, one per web virtual host:

    (
        {
            vhost_name => '...',
            domains => [ 'fqdn1.tld', ... ],
            vhost_is_ssl => 0 or 1,

            #Present only when vhost_is_ssl is true.
            #Contents vary according to configuration.
            proxy_subdomains => [
                'cpanel.fqdn1.tld',
                'webdisk.fqdn1.tld',
                'cpanel.fqdn2.tld',
            ],
        },
        ...
    )

See above about C<vhost_name>. Note that C<proxy_subdomains> here
contains the full FQDN, not just the leading label.

=cut

sub list_vhosts {
    my ( $username, $vhconf ) = @_;

    Cpanel::Context::must_be_list();

    require Cpanel::Config::WebVhosts;
    $vhconf ||= Cpanel::Config::WebVhosts->load($username);

    return _return_domain_vhosts_list(
        $username,
        sub {
            my ( $vhosts_ar, $is_ssl_hr ) = @_;

            my @result;

            require Cpanel::Config::userdata::Utils;

            #NB: each $ud_hr corresponds to a unique vhost
            for my $ud_hr (@$vhosts_ar) {
                my @d = Cpanel::Config::userdata::Utils::get_all_vhost_domains_from_vhost_userdata($ud_hr);

                push @result, {
                    vhost_name   => $ud_hr->{'servername'},
                    domains      => \@d,
                    vhost_is_ssl => $is_ssl_hr->{$ud_hr},
                };

                if ( $is_ssl_hr->{$ud_hr} ) {
                    $result[-1]{'proxy_subdomains'} = [
                        $vhconf->ssl_proxy_subdomains_for_vhost( $ud_hr->{'servername'} ),
                    ];
                }
            }

            return @result;
        },
        $vhconf
    );
}

#----------------------------------------------------------------------

sub _vhost_list_to_domain_list {
    my ( $vhosts_ar, $is_ssl_hr ) = @_;

    require Cpanel::Config::userdata::Utils;
    return map {
        my $ud_hr = $_;
        map {
            {
                vhost_name   => $ud_hr->{'servername'},
                domain       => $_,
                vhost_is_ssl => $is_ssl_hr->{$ud_hr},
            }
        } Cpanel::Config::userdata::Utils::get_all_vhost_domains_from_vhost_userdata($ud_hr)
    } @$vhosts_ar;
}

sub _return_domain_vhosts_list {
    my ( $username, $list_maker_cr, $vhosts_cnf, $vhost ) = @_;

    die 'Need a username!' if !$username;

    Cpanel::Context::must_be_list();

    require Cpanel::Config::WebVhosts;
    $vhosts_cnf ||= Cpanel::Config::WebVhosts->load($username);

    die "The main domain is missing for “$username”." if !$vhosts_cnf->main_domain();

    require Cpanel::Config::userdata::Load;

    #NOTE: This is the pattern in cPanel since ages past: the subdomain
    #is the Apache ServerName.
    my ( @ud_filename_domains, @ssl_domains );
    if ($vhost) {
        push @ud_filename_domains, $vhost if Cpanel::Config::userdata::Load::user_has_domain( $username, $vhost );
        push @ssl_domains,         $vhost if Cpanel::Config::userdata::Load::user_has_ssl_domain( $username, $vhost );
    }
    else {
        @ud_filename_domains = (
            $vhosts_cnf->main_domain(),
            $vhosts_cnf->subdomains(),
        );
        @ssl_domains = Cpanel::Config::userdata::Load::get_ssl_domains($username);
    }

    my @non_ssl_ud = map { _load_ud_and_check( $username, 'load_userdata',            $_ ); } @ud_filename_domains;
    my @ssl_ud     = map { _load_ud_and_check( $username, 'load_ssl_domain_userdata', $_ ); } @ssl_domains;

    #A hash keyed on the 'HASH(0x...)' stringification of the
    #reference to the userdata hashes.
    my %is_ssl;
    @is_ssl{@non_ssl_ud} = (0) x @non_ssl_ud;
    @is_ssl{@ssl_ud}     = (1) x @ssl_ud;

    return $list_maker_cr->(
        [
            ( sort { $a->{'servername'} cmp $b->{'servername'} } @non_ssl_ud ),
            ( sort { $a->{'servername'} cmp $b->{'servername'} } @ssl_ud ),
        ],
        \%is_ssl
    );
}

my %_load_func_cache;

sub _load_ud_and_check {
    my ( $username, $func, $name ) = @_;

    if ( !$_load_func_cache{$func} ) {
        require Cpanel::Config::userdata::Load;
        $_load_func_cache{$func} = Cpanel::Config::userdata::Load->can($func);
    }

    my $hr = $_load_func_cache{$func}->( $username, $name, $Cpanel::Config::userdata::Load::ADDON_DOMAIN_CHECK_SKIP );

    if ( !%$hr ) {

        #NOTE: Error messages would ideally be more helpful; however, the
        #module that handles userdata interaction reports to the log rather
        #than to the caller directly.
        warn "$func($name) failed - check /usr/local/cpanel/logs/error_log for additional details!";

        return ();
    }

    return $hr;
}

# for tests
sub _clear_load_func_cache {
    %_load_func_cache = ();
    return;
}

1;
