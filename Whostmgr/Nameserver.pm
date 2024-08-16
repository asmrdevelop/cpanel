package Whostmgr::Nameserver;

# cpanel - Whostmgr/Nameserver.pm                  Copyright 2022 cPanel, L.L.C.
#                                                           All rights reserved.
# copyright@cpanel.net                                         http://cpanel.net
# This code is subject to the cPanel license. Unauthorized copying is prohibited

use Cpanel::Config::LoadWwwAcctConf ();
use Cpanel::NameserverCfg           ();
use Cpanel::DnsUtils::NameServerIPs ();

sub cleanup_ns_cruft {
    my ($wwwacct_ref) = @_;

    # Cruft cleanup
    if ( length $wwwacct_ref->{'ns4'} && !length $wwwacct_ref->{'NS4'} ) {
        $wwwacct_ref->{'NS4'} = delete $wwwacct_ref->{'ns4'};
    }

    return 1;
}

sub get_nameserver_config {
    my @ns;
    if ( $ENV{'REMOTE_USER'} eq 'root' ) {
        my %wwwacct = Cpanel::Config::LoadWwwAcctConf::loadwwwacctconf();
        cleanup_ns_cruft( \%wwwacct );
        @ns = @wwwacct{qw(NS NS2 NS3 NS4)};
    }
    elsif ( my $reseller_nameservers = Cpanel::NameserverCfg::fetch_reseller_nameservers( $ENV{'REMOTE_USER'} ) ) {
        @ns = map { $reseller_nameservers->[$_] || undef } ( 0 .. 3 );
    }
    return grep { length } @ns;
}

sub get_ip_from_nameserver {
    return Cpanel::DnsUtils::NameServerIPs::get_ip_from_nameserver(@_);
}

sub get_ips_for_nameserver {
    return Cpanel::DnsUtils::NameServerIPs::get_all_ips_for_nameserver(@_);
}

1;
