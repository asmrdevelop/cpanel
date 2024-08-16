package Cpanel::DnsUtils::NameServerIPs;

# cpanel - Cpanel/DnsUtils/NameServerIPs.pm        Copyright 2022 cPanel, L.L.C.
#                                                           All rights reserved.
# copyright@cpanel.net                                         http://cpanel.net
# This code is subject to the cPanel license. Unauthorized copying is prohibited

use strict;
use warnings;

use Cpanel::AdminBin::Serializer ();
use Cpanel::CachedDataStore      ();
use Cpanel::Debug                ();
use Cpanel::OS                   ();

our $nameserver_ips_file = '/var/cpanel/nameserverips.yaml';
our $all_parse_cache_dir = 'parse_cache';
our $ns_parse_cache_dir  = 'ns_parse_cache';
our $named_dir;

# Required due to compiled code using this.
# Scoped this way because no external callers should ever need to call this.
my $init = sub {
    require Cpanel::OS;
    $named_dir = Cpanel::OS::dns_named_basedir() . '/';
    return;
};

sub load_nameserver_ips {
    my $write = shift;

    # Usage as safe as we own the dir and file
    my $nameserverips_db = Cpanel::CachedDataStore::loaddatastore( $nameserver_ips_file, $write );
    $nameserverips_db->{'data'} = {} unless 'HASH' eq ref $nameserverips_db->{'data'};

    return $nameserverips_db;
}

sub do_action_on_local_zones {
    my ( $args, $result ) = @_;
    $init->();

    my $dh;
    if ( !opendir $dh, $named_dir ) {
        $result->{'result'} = 0;
        $result->{'reason'} = "Failed to open $named_dir for reading";
        return;
    }
    foreach my $cache_dir ( $all_parse_cache_dir, $ns_parse_cache_dir ) {
        if ( !-e "$named_dir/$cache_dir" ) {
            require Cpanel::Mkdir;
            Cpanel::Mkdir::ensure_directory_existence_and_mode( "$named_dir/$cache_dir", 0700 );
        }
    }

    while ( my $file = readdir $dh ) {
        next   if substr( $file, -3 ) ne '.db';
        return if !$args->{'action'}( { 'filename' => "$named_dir/$file" }, $result );
    }
    closedir $dh;
    $result->{'result'} = 1;
    $result->{'reason'} = 'OK';
    return 1;
}

sub _make_action_extract_ns_to_zones {
    my ($args) = @_;

    my $debug       = $args->{'debug'};
    my $zones_in_ns = $args->{'zones_in_ns'};

    my $action = sub {
        my ( $args, $result ) = @_;
        my $records;
        eval { $records = _parse_or_load_zone_cache( $args->{filename}, 'NS' ) };
        if ($@) {
            $result->{'result'} = 0;
            $result->{'reason'} = "Unable to parse zone file [$args->{'filename'}]: $@";
            return;
        }

        #No post-process for TXT, SPF, and HINFO records is needed here since
        #we only care about NS records.

        foreach my $record (@$records) {
            $record->{'nsdname'} =~ tr{A-Z}{a-z};
            chop $record->{'nsdname'} while substr( $record->{'nsdname'}, -1 ) eq '.';
            chop $record->{'name'}    while substr( $record->{'name'},    -1 ) eq '.';
            if ( $debug && !exists $zones_in_ns->{ $record->{'nsdname'} } ) {
                print $record->{'nsdname'}, "\n";
            }
            if ( exists $zones_in_ns->{ $record->{'nsdname'} } ) {
                $zones_in_ns->{ $record->{'nsdname'} }{'count'} += 1;
                $zones_in_ns->{ $record->{'nsdname'} }{'zones'} .= ',' . $record->{'name'};
            }
            else {
                $zones_in_ns->{ $record->{'nsdname'} }{'count'} = 1;
                $zones_in_ns->{ $record->{'nsdname'} }{'zones'} = $record->{'name'};
            }
        }

        $result->{'result'} = 1;
        $result->{'reason'} = 'OK';
        return 1;
    };

    return $action;
}

sub updatenameserveriplist {
    my $debug = shift;

    my %zones_in_ns;

    my $action_args = {
        'debug'       => $debug,
        'zones_in_ns' => \%zones_in_ns,
    };
    my $action_result = {
        'result' => 0,
        'reason' => 'Unknown error',
    };

    my $action = _make_action_extract_ns_to_zones( $action_args, $action_result );
    if ( !do_action_on_local_zones( { 'action' => $action }, $action_result ) ) {
        Cpanel::Debug::log_info( $action_result->{'reason'} );
        return;
    }

    foreach my $ns ( keys %zones_in_ns ) {
        my $nameserver_ips = get_all_ips_for_nameserver($ns);
        $zones_in_ns{$ns}{'ipv4'} = ( $nameserver_ips->{'ipv4'} ? $nameserver_ips->{'ipv4'} : '' );
        $zones_in_ns{$ns}{'ipv6'} = ( $nameserver_ips->{'ipv6'} ? $nameserver_ips->{'ipv6'} : '' );
    }

    Cpanel::CachedDataStore::savedatastore( $nameserver_ips_file, { 'data' => \%zones_in_ns } );

    # Usage as safe as we own the dir and file
    chmod 0600, $nameserver_ips_file;
    return;
}

sub listassignednsips {
    my ($refresh) = shift;
    if ($refresh) {
        updatenameserveriplist();
    }

    my ( $nsips, $nscounts );
    my $nameserverips_db = load_nameserver_ips(0);

    foreach my $nameserver ( keys %{ $nameserverips_db->{'data'} } ) {
        foreach my $ip_type (qw(ipv4 ipv6)) {
            $nsips->{$nameserver}->{$ip_type} = $nameserverips_db->{'data'}->{$nameserver}->{$ip_type};
        }

        $nscounts->{$nameserver} = $nameserverips_db->{'data'}->{$nameserver}->{'count'};
    }

    return $nsips, $nscounts;
}

sub listnszones {
    my ( $ns, $refresh ) = @_;
    if ($refresh) {
        updatenameserveriplist();
    }

    my $nameserverips_db = load_nameserver_ips(0);
    my %nameserverips    = %{ $nameserverips_db->{'data'} };

    my @zones = ();
    if ( exists $nameserverips{$ns} ) {
        @zones = split( /,/, $nameserverips{$ns}{'zones'} );
    }
    else {
        Cpanel::Debug::log_warn("No zone records found for name server: $ns");
        return;
    }

    return wantarray ? @zones : \@zones;
}

sub get_all_ips_for_nameserver {
    my $nameserver = shift;
    my $ips        = _resolve_ns_ips($nameserver);
    if ( $ips->{'ipv4'} || $ips->{'ipv6'} ) {
        return $ips;
    }

    return _get_nsip_for_from_zonefile($nameserver);
}

sub get_ip_from_nameserver {
    my $nameserver = shift;
    my $ips        = _resolve_ns_ips($nameserver);
    return $ips->{'ipv4'} if $ips->{'ipv4'};

    return _get_nsip_for_from_zonefile($nameserver)->{'ipv4'};
}

sub _resolve_ns_ips {
    my $ns = shift;

    require Cpanel::Validate::Domain::Tiny;
    require Cpanel::Validate::Domain::Normalize;
    my $nameserver = Cpanel::Validate::Domain::Normalize::normalize($ns);
    return if !Cpanel::Validate::Domain::Tiny::validdomainname($nameserver);

    require Cpanel::DnsRoots;
    my $ips = Cpanel::DnsRoots::resolve_addresses_for_domain($nameserver);
    return $ips;
}

sub _get_nsip_for_from_zonefile {
    my $nameserver = shift;
    $init->();

    my $ips = {
        'ipv4' => '',
        'ipv6' => '',
    };

    my @nameserver_parts = split /\./, $nameserver;

    my $records;
    my $record_to_search_for;
    while ( scalar @nameserver_parts >= 2 ) {
        my $zonefile = $named_dir . join( '.', @nameserver_parts ) . '.db';
        if ( -e $zonefile ) {
            eval { $records = _parse_or_load_zone_cache( $zonefile, 'all' ) };
            foreach my $record (@$records) {

                # Cpanel::Net::DNS::ZoneFile::LDNS incorrect adds a "." to the "name" field
                # so we need to account for that when looking for matching records.
                next if $record->{'name'} && $record->{'name'} ne ( $record_to_search_for ? "$record_to_search_for." : "$nameserver." );

                if ( $record->{'type'} eq 'A' ) {
                    $ips->{'ipv4'} = $record->{'address'};
                }
                elsif ( $record->{'type'} eq 'AAAA' ) {
                    $ips->{'ipv6'} = $record->{'address'};
                }
            }
            last;
        }
        $record_to_search_for .= ( $record_to_search_for ? '.' : '' ) . shift @nameserver_parts;
    }

    return $ips;
}

sub _parse_or_load_zone_cache {
    my ( $filepath, $cache_type ) = @_;

    my @path                 = split( m{/}, $filepath );
    my $filename             = pop @path;
    my $all_parse_cache_file = join( '/', @path, $all_parse_cache_dir, $filename );
    my $ns_parse_cache_file  = join( '/', @path, $ns_parse_cache_dir,  $filename );
    my $cache_file           = $cache_type eq 'NS' ? $ns_parse_cache_file : $all_parse_cache_file;
    my $cache_file_mtime     = ( stat($cache_file) )[9];
    if ( $cache_file_mtime && $cache_file_mtime > ( stat($filepath) )[9] ) {
        my $records;
        local $@;
        warn            if !eval { $records = Cpanel::AdminBin::Serializer::LoadFile($cache_file); };
        return $records if !$@;
    }
    require Cpanel::Net::DNS::ZoneFile::LDNS;
    my $all_records = Cpanel::Net::DNS::ZoneFile::LDNS::parse( 'file' => $filepath );

    require Cpanel::FileUtils::Write;
    my $ns_records = [ grep { $_->{type} eq 'NS' } @$all_records ];

    # The all cache file must always be written first since
    # its the one the system checks the mtime of and it
    # always needs to be the oldest
    Cpanel::FileUtils::Write::overwrite( $all_parse_cache_file, Cpanel::AdminBin::Serializer::Dump($all_records), 0600 );

    # Any other subset caches are written next.  In this case
    # we just need NS
    Cpanel::FileUtils::Write::overwrite( $ns_parse_cache_file, Cpanel::AdminBin::Serializer::Dump($ns_records), 0600 );
    return $cache_type eq 'NS' ? $ns_records : $all_records;
}
1;
