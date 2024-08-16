package Cpanel::NameServers;

# cpanel - Cpanel/NameServers.pm                   Copyright 2024 cPanel, L.L.C.
#                                                           All rights reserved.
# copyright@cpanel.net                                         http://cpanel.net
# This code is subject to the cPanel license. Unauthorized copying is prohibited

use cPstrict;

use Cpanel::Binaries       ();
use Cpanel::DnsRoots       ();
use Cpanel::SafeRun::Extra ();
use Cpanel::ZoneFile::Tld  ();

use constant PUBLIC_DNS_SERVERS => qw<
  1.1.1.1
  8.8.4.4
  8.8.8.8
  9.9.9.9
>;

=encoding utf-8

=head1 NAME

Cpanel::NameServers - Find NameServers for a domain or zone.

=head1 SYNOPSIS

    use cPstrict;
    use Cpanel::NameServers ();

    my $list = Cpane::NameServers::get_nameservers_for_domain( "cpanel.net" );

    foreach my $ns ( $list->@* ) {
        say $ns;
    }


=head1 DESCRIPTION

This modules is a wrapper around DNS::Unbound with a few extra fallback options
to find/guess the current NameServers of a domain.

In some cases where the NS are not correctly setup, DNS::Unbound or a request
to the public servers would be enough to get the accurate list of nameservers.

We use as a fallback a 'dig +strace' which then should returns us the accurate values.

=head1 FUNCTIONS

=head2 get_nameservers_for_domain( $domain )

Return an ArrayRef with the list of NameServers (sorted).
The list is empty when none are found.

=cut

sub get_nameservers_for_domain ($domain) {
    return unless length $domain;

    my $zone = Cpanel::ZoneFile::Tld::guess_root_domain($domain) or return;

    my $list = _request_dns_unbound($zone)     # DNS::Unbound first
      // _request_public_dns_servers($zone)    # check public DNS Servers
      // _request_ns_dig_trace($zone)          # check dig with +trace
      // [];

    return [ sort @$list ];
}

sub _request_dns_unbound ($zone) {
    require Cpanel::DNS::Unbound;
    no warnings 'redefine';

    local *Cpanel::DNS::Unbound::_warn_query_failure = sub { };
    my $ns   = eval { Cpanel::DnsRoots->new()->get_nameservers_for_domain($zone) } // {};
    my @list = keys $ns->%*;

    return unless scalar @list;
    return \@list;
}

sub _request_public_dns_servers ($zone) {

    my @servers = _shuffle(PUBLIC_DNS_SERVERS);

    my $list;

    foreach my $server (@servers) {
        last if $list = _request_ns_dig( $zone, $server );
    }

    return $list;
}

sub _request_ns_dig ( $zone, $server = undef ) {

    my @list;

    my @args = qw{ +short NS };
    push @args, '@' . $server if length $server;

    my $run = eval {
        Cpanel::SafeRun::Extra->new_or_die(
            program => Cpanel::Binaries::path('dig'),
            args    => [ @args, $zone ],
            timeout => 5
        );
    } or return;

    # only request it once for now
    my $stdout = $run->stdout // '';

    my @rows = split( "\n", $stdout );
    foreach my $r (@rows) {
        $r =~ s/\.$//;
        next unless length $r;
        push @list, $r;
    }

    return unless scalar @list;
    return \@list;
}

sub _request_ns_dig_trace ($zone) {

    my @list;

    my $run = eval {
        Cpanel::SafeRun::Extra->new_or_die(
            program => Cpanel::Binaries::path('dig'),
            args    => [ qw{ +trace NS }, $zone ],
            timeout => 5
        );
    } or return;

    my $stdout = $run->stdout // '';
    my @lines  = split( "\n", $stdout );
    foreach my $line (@lines) {
        next unless $line =~ m{^ \Q$zone\E\. \s .+ IN \s+ NS \s+ (\S+) }x;
        my $ns = $1;
        $ns =~ s{\.$}{};
        push @list, $ns if length $ns;
    }

    return unless scalar @list;
    return \@list;
}

sub _shuffle (@list) {
    my %h = map { $_ => undef } @list;
    return keys %h;
}

1;
