package Cpanel::DnsRoots;

# cpanel - Cpanel/DnsRoots.pm                      Copyright 2022 cPanel, L.L.C.
#                                                           All rights reserved.
# copyright@cpanel.net                                         http://cpanel.net
# This code is subject to the cPanel license. Unauthorized copying is prohibited

use strict;
use warnings;

use Cpanel::DNS::Unbound ();
use Cpanel::SocketIP     ();
use Cpanel::Exception    ();
use Cpanel::LoadModule   ();
use Cpanel::Sort::Utils  ();

$Cpanel::DnsRoots::VERSION = '4.0';

# Public Methods

sub fetchnameservers {
    my ( $domain, $consider_soa, $get_ips ) = @_;
    my $resolver = _resolver();

    require Cpanel::DNS::GetNameservers;

    $get_ips //= 1;
    my $nameservers_ref = Cpanel::DNS::GetNameservers::get_nameservers( $resolver, $domain, $consider_soa, $get_ips );

    return ( 0, [], {}, $domain ) if !$nameservers_ref || !scalar keys %$nameservers_ref;

    $_ = $_->[0] for values %$nameservers_ref;

    return ( 1, [ values %{$nameservers_ref} ], $nameservers_ref, $domain );
}

# This is really 'resolve nameservers for a domain'
# It first fetches the NS records for the domain specified,
# and resolves the IP addresses for resulint NS records.
#
# If you are querying the IP addresses for a specific NS, then
# you want to use one of the 'get_ipv[4|6]_addresses_for_domain' functions.
sub resolvenameservers {
    my ($domain)        = @_;
    my $self            = __PACKAGE__->new();
    my $nameservers_ref = $self->get_nameservers_for_domain($domain);
    return if !$nameservers_ref || !scalar keys %$nameservers_ref;
    return values %{$nameservers_ref};
}

sub resolve_addresses_for_domain {
    my $domain = shift;
    my $self   = __PACKAGE__->new();

    return {
        'ipv4' => ( $self->get_ipv4_addresses_for_domain($domain) )[0] || '',
        'ipv6' => ( $self->get_ipv6_addresses_for_domain($domain) )[0] || '',
    };
}

# BAMP = By Any Means Possible
sub resolveIpAddressBAMP {
    my $domain = shift;
    my $nsip   = Cpanel::SocketIP::_resolveIpAddress($domain);
    return !$nsip ? return _resolveIpAddress($domain) : $nsip;
}

# Object Methods

sub new {
    my ($class) = @_;
    return bless {
        'resolver' => _resolver(),
    }, $class;
}

sub get_ipv6_addresses_for_domain {
    my ( $self, $domain ) = @_;
    return $self->{'resolver'}->recursive_query( $domain, 'AAAA' );
}

sub get_ipv4_addresses_for_domain {
    my ( $self, $domain ) = @_;
    return $self->{'resolver'}->recursive_query( $domain, 'A' );
}

sub get_ipv4_addresses_for_domains {
    my ( $self, @domains ) = @_;

    my $ret = $self->{'resolver'}->recursive_queries( [ map { [ $_, 'A' ] } @domains ] );

    return map { ref $_ ? $_->{'decoded_data'} : undef } @$ret;
}

#NOTE: It is conceivable that we may want to expose this at some point
#for a more programmatic interface.
sub _get_local_domain_resolution {
    my ( $self, $domain ) = @_;

    my @addrs = $self->get_ipv4_addresses_for_domain($domain);

    if ( !@addrs ) {
        my $is_reg = $self->domains_are_registered($domain);
        return $is_reg->error() if $is_reg->error();

        return 'not_registered' if !$is_reg->get();

        return 'no_ipv4';
    }

    Cpanel::LoadModule::load_perl_module('Cpanel::IP::LocalCheck');

    #NOTE: This potentially has us grabbing the list of server IPs
    #from the kernel for every IP on every domain.
    my @remotes = grep { !Cpanel::IP::LocalCheck::ip_is_on_local_server($_) } @addrs;
    if (@remotes) {
        Cpanel::LoadModule::load_perl_module('Cpanel::Sort::Utils');

        @remotes = Cpanel::Sort::Utils::sort_ipv4_list(@remotes);
        return 'remote', \@remotes;
    }

    return undef;
}

# Should return 1 on success
sub ensure_domain_resides_only_locally {
    my ( $self, $domain ) = @_;

    my ( $failure, $metadata ) = $self->_get_local_domain_resolution($domain);

    return 1 if !$failure;

    if ( $failure eq 'not_registered' ) {
        die Cpanel::Exception->create( '“[_1]” is not a registered internet domain.', [$domain] );
    }
    elsif ( $failure eq 'no_ipv4' ) {
        die Cpanel::Exception->create( '“[_1]” does not resolve to any [asis,IPv4] addresses on the internet.', [$domain] );
    }
    elsif ( $failure eq 'remote' ) {
        die Cpanel::Exception->create( '“[_1]” resolves to the following [asis,IPv4] [numerate,_2,address,addresses], which [numerate,_2,does not,do not] exist on this server: [list_and,_3]', [ $domain, scalar(@$metadata), $metadata ] );
    }

    #We should not get here, but just in case.
    die "Unknown failure: “$failure”!";
}

sub get_txtdata_for_domain {
    my ( $self, $domain ) = @_;
    return $self->{'resolver'}->recursive_query( $domain, 'TXT' );
}

sub domains_are_registered {
    my ( $self, @domains ) = @_;

    return $self->{'resolver'}->domains_are_registered(@domains);
}

sub get_nameservers_for_domain {
    my ( $self, $domain ) = @_;

    my @nsnames = $self->{'resolver'}->get_nameservers_for_domain($domain);

    my %nameservers;
    @nameservers{@nsnames} = map { ref $_ ? $_->[0] : undef } $self->get_ipv4_addresses_for_domains(@nsnames);

    return \%nameservers;
}

sub get_ip_addresses_for_domains {
    my ( $self, @domains ) = @_;

    my $ret = $self->{'resolver'}->recursive_queries( [ map { [ $_, 'A' ], [ $_, 'AAAA' ] } @domains ] );

    my %ips_by_domain;
    foreach my $domain (@domains) {
        my $v4 = shift @$ret;
        my $v6 = shift @$ret;
        $ips_by_domain{$domain}{v4} = ref $v4 ? ( $v4->{'decoded_data'} // [] ) : [];
        $ips_by_domain{$domain}{v6} = ref $v6 ? ( $v6->{'decoded_data'} // [] ) : [];
    }
    return \%ips_by_domain;
}

sub get_resolver {
    return $_[0]->{'resolver'};
}

# Private Methods

sub _resolveIpAddress {
    my ( $domain, %p_options ) = @_;

    my $self = __PACKAGE__->new();
    my $ipv6 = $p_options{'ipv6'} || 0;
    my @IPS;
    if ($ipv6) {
        @IPS = $self->get_ipv6_addresses_for_domain($domain);
    }
    else {
        @IPS = $self->get_ipv4_addresses_for_domain($domain);
    }
    return wantarray ? @IPS : $IPS[0];
}

our $resolver;

sub _resolver {
    return $resolver ||= Cpanel::DNS::Unbound->new();
}

END {
    undef $resolver;
}

1;
