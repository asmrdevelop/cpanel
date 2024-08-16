package Cpanel::IPv6::DNSUtil;

# cpanel - Cpanel/IPv6/DNSUtil.pm                  Copyright 2022 cPanel, L.L.C.
#                                                           All rights reserved.
# copyright@cpanel.net                                         http://cpanel.net
# This code is subject to the cPanel license. Unauthorized copying is prohibited

use cPstrict;

use Whostmgr::DNS::Zone             ();
use Cpanel::ZoneFile                ();
use Cpanel::DnsUtils::AskDnsAdmin   ();
use Cpanel::NameServer::Utils::BIND ();
use Cpanel::SafeFile                ();
use Cpanel::Locale                  ();
use Cpanel::Config::userdata::Load  ();
use Cpanel::Ips::Fetch              ();
use Cpanel::NAT                     ();
use Cpanel::WebVhosts::AutoDomains  ();

my $locale;

my $IPS_ref;

my %special_subdomain_list = (
    'localhost' => '::1'

      # May need to add those subdomains that should always point to the server's main shared IP here
);

# domain we are updating, ipv6 address we are adding, whether or not to replace any existing ipv6 addresses
sub add_aaaa_records_to_domain {
    my ( $user, $domain, $ipv6, $replace ) = @_;

    $locale ||= Cpanel::Locale->get_handle();

    my %domains;

    my $zone_data = Whostmgr::DNS::Zone::fetchdnszone($domain);
    my $zone      = Cpanel::ZoneFile->new( domain => $domain, text => $zone_data );

    if ( $zone && $zone->{'dnszone'} ) {
        foreach my $line ( @{ $zone->{'dnszone'} } ) {
            next if !exists $line->{'name'} || $line->{'name'} eq '';
            my $name = _unqualify( $line->{'name'}, $domain );
            my $type = $line->{'type'};
            my $addr = $line->{'address'};
            if ( $type eq 'AAAA' || $type eq 'A' ) {
                $domains{$name}->{$type} //= [];
                push @{ $domains{$name}->{$type} }, $line;
            }
        }

        # Enable adding of ipv6 AAAA if it doesn't exist:
        $domains{'ipv6'} //= {};

        foreach my $node ( keys %domains ) {
            my $A_records    = $domains{$node}->{'A'}    || [];
            my $AAAA_records = $domains{$node}->{'AAAA'} || [];

            my $remote_count = grep { _is_remote_ip( $_->{'address'} ) } @$A_records;
            my $local_count  = scalar @$A_records - $remote_count;

            # Don't do anything if it's not the user's.
            if ( _record_is_acct_resource( $user, $domain, substr( $node, -1 ) eq '.' ? $node : "$node.$domain." ) ) {

                # Skip if there are A records but all addrs are remote. In this case, both
                # adding and modifying AAAA records is unlikely to be right.
                if ( $local_count == 0 && $remote_count > 0 ) {
                    next;
                }

                # Otherwise, if there aren't any AAAA records, or if A records are a mixture of local
                # and remote, add a new AAAA record. The rationale for the latter condition is that
                # if the hostname has multiple A records, with some remote and some local, either
                # the multiple A records are an accident, or the user is doing round-robin DNS, and
                # a new AAAA record makes the most sense.
                elsif ( scalar @$AAAA_records == 0 || ( $local_count > 0 && $remote_count > 0 ) ) {
                    my %new_record;
                    $new_record{'name'}    = scalar @$A_records == 1 ? $A_records->[0]->{'name'} : $node;
                    $new_record{'class'}   = 'IN';
                    $new_record{'type'}    = 'AAAA';
                    $new_record{'address'} = $special_subdomain_list{$node} || $ipv6;

                    $zone->add_record( \%new_record );
                }

                # Otherwise, if there is only a single AAAA record, modify if $replace.
                elsif ( scalar @$AAAA_records == 1 ) {
                    if ($replace) {
                        my $record = $AAAA_records->[0];
                        $record->{'address'} = $special_subdomain_list{$node} || $ipv6;
                    }
                }

                # Log if hopelessly confused, so that at least the admin knows.
                else {
                    require Cpanel::Logger;
                    Cpanel::Logger->new()->info("Multiple AAAA records have been found for “$node” in “$domain”. Adjust zone manually.");
                }
            }
        }

        my ( $ret, $msg ) = Whostmgr::DNS::Zone::_bump_serial_number($zone);
        if ( $ret != 1 ) {
            return ( 0, $locale->maketext( "The system could not update [output,acronym,SOA,Start of Authority] for “[_1]”: [_2]", $domain, $msg ) );
        }
    }

    my ( $status, $statusmsg, $zonelines_ref ) = $zone->dns_zone_obj_to_zonelines();
    if ($status) {
        Cpanel::DnsUtils::AskDnsAdmin::askdnsadmin( 'SAVEZONE', 0, $domain, join( "\n", @{$zonelines_ref} ) );
        Cpanel::DnsUtils::AskDnsAdmin::askdnsadmin( 'RELOADBIND', 0, $domain );
        return ( 1, $locale->maketext( "The system updated the zone file for “[_1]” with IPv6 entries that point to “[_2]”.", $domain, $ipv6 ) );
    }
    else {
        return ( 0, $locale->maketext( "The system could not update the zone file with IPv6 entries: [_1]", $statusmsg ) );
    }

}

sub _unqualify {
    my ( $name, $domain ) = @_;
    if ( $name =~ m/\.$/ ) {
        $name =~ s/\.$domain\.$//i;
    }
    return $name;
}

#
# If the ipv6_alias_remove parameter is specified, it will only remove records with
# the same name as that parameter.
#
sub remove_aaaa_records_for_domain {
    my ( $user, $domain, $ipv6_alias_remove ) = @_;

    $locale ||= Cpanel::Locale->get_handle();

    my ( $ret, $records_ref ) = get_aaaa_records_for_domain($domain);
    if ( $ret != 1 ) {
        return ( 0, $locale->maketext( "The system could not get [asis,AAAA] records for “[_1]”: [_2]", $domain, $records_ref ) );
    }

    # The DNS record names all have a '.' appended
    $ipv6_alias_remove .= '.' if $ipv6_alias_remove;

    my @records_to_remove;
    foreach my $rec ( @{$records_ref} ) {
        next if ( $ipv6_alias_remove && $ipv6_alias_remove ne $rec->{'name'} );
        next unless _record_is_acct_resource( $user, $domain, $rec->{'name'} );
        push( @records_to_remove, $rec );
    }

    return ( 1, $locale->maketext("No AAAA records to remove") ) unless scalar(@records_to_remove);

    my $zone = Cpanel::ZoneFile->new( domain => $domain, text => [ Whostmgr::DNS::Zone::fetchdnszone($domain) ] );
    if ( $zone && $zone->{'dnszone'} ) {
        $zone->remove_records( \@records_to_remove );

        my ( $ret, $msg ) = Whostmgr::DNS::Zone::_bump_serial_number($zone);
        if ( $ret != 1 ) {
            return ( 0, $locale->maketext( "The system could not update [output,acronym,SOA,Start of Authority] for “[_1]”: [_2]", $domain, $msg ) );
        }
    }

    my ( $status, $statusmsg, $zonelines_ref ) = $zone->dns_zone_obj_to_zonelines();
    if ($status) {
        Cpanel::DnsUtils::AskDnsAdmin::askdnsadmin( 'SAVEZONE', 0, $domain, join( "\n", @{$zonelines_ref} ) );
        Cpanel::DnsUtils::AskDnsAdmin::askdnsadmin( 'RELOADBIND', 0, $domain );
        return ( 1, $locale->maketext( "The system updated the zone file for “[_1]” to remove IPv6 entries.", $domain ) );
    }
    else {
        return ( 0, $locale->maketext( "Could not update zone file to remove IPv6 entries: [_1]", $statusmsg ) );
    }

}

sub get_aaaa_records_for_domain {
    my ($domain) = @_;
    my @response;
    my @quadAAAAs;

    $locale ||= Cpanel::Locale->get_handle();

    # Get existing zone records
    my ( $result, $msg ) = Whostmgr::DNS::Zone::get_zone_records_by_type( \@quadAAAAs, $domain, 'AAAA' );
    if ( !$result ) {
        return ( 0, $locale->maketext( "The system could not get the records for “[_1]”: [_2]", $domain, $msg ) );

    }

    foreach my $record_line (@quadAAAAs) {
        push( @response, $record_line );
    }

    return ( 1, \@response );

}

# This is a separate subroutine for test purposes.
sub _restart_named {
    return system( '/usr/local/cpanel/scripts/restartsrv_named', '--no-verbose' );
}

sub enable_ipv6_in_named_conf {

    $locale ||= Cpanel::Locale->get_handle();

    # edit named.conf, ensure it is ipv6 friendly
    my $named_dot_conf = Cpanel::NameServer::Utils::BIND::find_namedconf();

    my $f_lock;
    if ( $f_lock = Cpanel::SafeFile::safeopen( my $named_fh, '+<', $named_dot_conf ) ) {
        my $ndc;
        while (<$named_fh>) {
            $ndc .= $_;
        }

        # We've read in the file, now we seek back to the start and can start writing to it
        seek( $named_fh, 0, 0 );

        if ( $ndc !~ m/listen-on-v6\s+{.+any\;.+}/s ) {

            # need to add ipv6 config option to named.conf
            $ndc =~ s/options\s+{/options {\n\tlisten-on-v6 { any; }; \/\*\tupdated by cPanel \*\/\n/;

            print {$named_fh} $ndc;

            # End the file where we currently are and save it ( to clear out any extra data )
            truncate( $named_fh, tell($named_fh) );
            Cpanel::SafeFile::safeclose( $named_fh, $f_lock );

            # restart named to enable ipv6
            _restart_named();

            return ( 1, $locale->maketext( "The system updated “[_1]” with IPv6 support.", $named_dot_conf ) );
        }
        else {
            Cpanel::SafeFile::safeclose( $named_fh, $f_lock );
            return ( 1, $locale->maketext( "The config file, [_1], already has support for [output,acronym,IPv6,Internet Protocol Version 6].", $named_dot_conf ) );
        }

    }
    else {
        return ( 0, $locale->maketext( "The system could not open “[_1]” to edit it: [_2]", $named_dot_conf, $! ) );
    }
}

# Method determines if an IP is remote.
# parameters: ( $ip ) -
#   $ip - the IP address
#
# returns 1 : 0

sub _is_remote_ip {
    my ($ip) = @_;
    return 0 if $ip eq '127.0.0.1';    # localhost should be treated as local
    $IPS_ref //= Cpanel::Ips::Fetch::fetchipslist();
    my $local_ip = Cpanel::NAT::get_local_ip($ip);
    return !exists $IPS_ref->{$local_ip} ? 1 : 0;
}

# parameters: ( $username, $domain, $record ) f.ex. ('foo', 'foo.com', 'bar.foo.com.')
# returns:  boolean indiciating whether the record in question is an addon domain,
# sub domain, parked domain, main domain OR built in associated with the $username provided
sub _record_is_acct_resource {
    my ( $user, $domain, $record ) = @_;
    my $userdata_main = Cpanel::Config::userdata::Load::load_userdata_main($user);

    # list of NS records that we'll allow no matter what.
    my @builtins = map { $_ . '.' . $domain } Cpanel::WebVhosts::AutoDomains::ALL_POSSIBLE_AUTO_DOMAINS();

    my @subdomain_builtins;
    foreach my $proxy ( Cpanel::WebVhosts::AutoDomains::ALL_POSSIBLE_PROXIES() ) {
        push @subdomain_builtins, map { $proxy . '.' . $_ } @{ $userdata_main->{'sub_domains'} };
    }

    # Addon domains and parked domains may be subdomains of an account
    my @domain_list = (
        @builtins,
        @subdomain_builtins,
        $userdata_main->{'main_domain'},
        @{ $userdata_main->{'sub_domains'} },
        @{ $userdata_main->{'parked_domains'} },
        keys %{ $userdata_main->{'addon_domains'} },
    );

    $record =~ s/\.$//;
    return scalar grep /^$record$/, @domain_list;
}

1;
