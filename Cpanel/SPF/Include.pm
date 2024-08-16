package Cpanel::SPF::Include;

# cpanel - Cpanel/SPF/Include.pm                   Copyright 2022 cPanel L.L.C.
#                                                           All rights reserved.
# copyright@cpanel.net                                         http://cpanel.net
# This code is subject to the cPanel license. Unauthorized copying is prohibited

use strict;
use warnings;

use Cpanel::AdminBin::Serializer::FailOK ();
use Cpanel::AdminBin::Serializer         ();

our $VERSION = 1.1;
our $TTL     = 5 * 60;    # 5 minutes

our $_spf_includes_cache;
our %_txt_cache;

=encoding utf-8

=head1 NAME

Cpanel::SPF::Include - Obtain a list of spf includes host for the system

=head1 SYNOPSIS

    use Cpanel::SPF::Include;

    my $hosts_ar = Cpanel::SPF::Include::get_spf_include_hosts();

=head2 get_spf_include_hosts()

Returns an arrayref of SPF include hosts configured
on this system and ones found with autodiscovery.

Autodiscovery will search each label in each smarthost
route_list for SPF records and add them to the include
list if they exist.

For example if the smarthost route_list is set to:
"* relay1.cpanel.net"

If SPF records exists for relay1.cpanel.net or cpanel.net
the system will include them in the return.

=cut

sub get_spf_include_hosts {
    $_spf_includes_cache ||= _load_cache();

    return $_spf_includes_cache if $_spf_includes_cache;

    my %spf_includes;
    require Cpanel::Exim::Config::LocalOpts;
    my $cf = Cpanel::Exim::Config::LocalOpts::get_exim_localopts_config();

    my $autodiscover = $cf->{'smarthost_autodiscover_spf_include'} // 1;

    if ( $cf->{'smarthost_routelist'} && $autodiscover ) {
        _autodiscover_spf_includes_from_routelist( \%spf_includes, $cf->{'smarthost_routelist'} );
    }
    if ( $cf->{'spf_include_hosts'} ) {
        _add_spf_includes_from_spf_include_hosts( \%spf_includes, $cf->{'spf_include_hosts'} );
    }

    $_spf_includes_cache = [ sort keys %spf_includes ];
    _write_cache($_spf_includes_cache);
    return $_spf_includes_cache;
}

sub _DATASTORE_FILE {
    require Cpanel::CachedCommand::Utils;
    return Cpanel::CachedCommand::Utils::get_datastore_filename( __PACKAGE__, 'default' );
}

sub _load_cache {
    my $datastore_file = _DATASTORE_FILE();
    if ( -s $datastore_file ) {
        my $datastore_mtime = ( stat(_) )[9];
        require Cpanel::Exim::Config::LocalOpts;
        my $exim_config_mtime = ( stat($Cpanel::Exim::Config::LocalOpts::EXIM_LOCALOPTS_CONFIG) )[9];
        my $now               = time();
        return undef if ( defined $exim_config_mtime && $exim_config_mtime >= $datastore_mtime ) || ( $datastore_mtime + $TTL ) < $now || $datastore_mtime > $now;
        local $@;
        my $cache = eval { Cpanel::AdminBin::Serializer::FailOK::LoadFile($datastore_file); };
        if ( ref $cache eq 'HASH' && $cache->{'VERSION'} && $cache->{'VERSION'} == $VERSION ) {
            return $cache->{'hosts'};
        }
    }
    return undef;
}

sub _write_cache {
    my ($include_hosts_ar) = @_;

    my $datastore_file = _DATASTORE_FILE();
    require Cpanel::FileUtils::Write;
    Cpanel::FileUtils::Write::overwrite( $datastore_file, Cpanel::AdminBin::Serializer::Dump( { 'VERSION' => $VERSION, 'hosts' => $include_hosts_ar } ), 0644 );

    return 1;
}

sub _autodiscover_spf_includes_from_routelist {
    my ( $spf_includes_hr, $smarthost_routelist ) = @_;

    require Cpanel::StringFunc::Trim;
    require Cpanel::DnsUtils::ResolverSingleton;
    foreach my $routing_rule ( split( m{\s+;\s+}, $smarthost_routelist ) ) {
        my ( $route, $destinations, $options ) = split( m{[ \t]+}, $routing_rule, 3 );
        next if !$destinations;

        # misconfigured smarthost the correct format
        # is <domain pattern>  <list of hosts>  <options>
        # see https://www.exim.org/exim-html-current/doc/html/spec_html/ch-the_manualroute_router.html#SECID120
        my @hosts = map { Cpanel::StringFunc::Trim::ws_trim( $_ =~ tr{+}{}dr ) } split( m{[ \t]*:[ \t]*}, $destinations );
        my %seen;
        foreach my $host (@hosts) {
            my @parts = split( m{\.}, $host );
            while ( scalar @parts >= 1 ) {
                my $domain = join( '.', @parts );
                require Cpanel::PublicSuffix;
                last if $seen{$domain}++ || Cpanel::PublicSuffix::domain_isa_tld($domain);
                my @records = @{ $_txt_cache{$domain} ||= [ Cpanel::DnsUtils::ResolverSingleton::singleton()->recursive_query( $domain, 'TXT' ) ] };
                if ( grep { index( $_, 'v=spf' ) > -1 } @records ) {
                    $spf_includes_hr->{$domain} = 1;
                }
                shift @parts;
            }
        }
    }
    return;
}

sub _add_spf_includes_from_spf_include_hosts {
    my ( $spf_includes_hr, $spf_include_hosts ) = @_;
    if ( my @hosts = grep { length } split( m{[ \t]*[;,:]+[ \t]*}, $spf_include_hosts ) ) {
        @{$spf_includes_hr}{@hosts} = (1) x scalar @hosts;
    }
    return 1;
}

1;
