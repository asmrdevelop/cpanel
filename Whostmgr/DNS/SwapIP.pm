package Whostmgr::DNS::SwapIP;

# cpanel - Whostmgr/DNS/SwapIP.pm                  Copyright 2022 cPanel, L.L.C.
#                                                           All rights reserved.
# copyright@cpanel.net                                         http://cpanel.net
# This code is subject to the cPanel license. Unauthorized copying is prohibited

use cPstrict;

use Cpanel::DIp::MainIP           ();
use Cpanel::DnsUtils::AskDnsAdmin ();
use Cpanel::DnsUtils::Fetch       ();
use Cpanel::Encoder::URI          ();
use Cpanel::NAT                   ();
use Cpanel::Proxy::Tiny           ();
use Cpanel::IP::Loopback          ();
use Cpanel::NameserverCfg         ();
use Cpanel::Hostname              ();
use Cpanel::SPF::String           ();
use Cpanel::ZoneFile              ();

my $hr_STATICDOMAINS;
my $cpzones;

=encoding utf-8

=head1 NAME

Whostmgr::DNS::SwapIP - Swap IPs in a Cpanel::ZoneFile object

=head1 SYNOPSIS

    use Whostmgr::DNS::SwapIP;

    my $sourceip = get_sourceip_from_zonefile_obj($zone_file_obj);

    my $replace_count = Whostmgr::DNS::SwapIP::swap_zonefile_obj_ips(
        'sourceips_hr'  => { map { $_ => 1 } @previous_and_related_not_new_ips },
        'zone_file_obj' => $custom_zone_obj,
        'ftpip'         => $ftpip,
        'destip'        => $new_ip,
        'replaceip'     => $replaceip
    );

=head2 swap_ip_in_zones( %OPTS )

Replaces instances of an IP address in the zone files for the specified zones.

This function is a convenience wrapper that loads the zone files and calls
C<swap_zonefile_obj_ips> and C<swap_zonefile_spf_ips> for each zone before
(optionally) doing an AskDnsAdmin C<SYNCZONES> and C<RELOADZONES>.

=over

=item Input

A hash with the following keys:

=over

=item domainref

An C<ARRAYREF> of domains whose zone files should be updated

=item sourceip

The old IP address that will be replaced.

If specified a C<-1> then the old IP addresses will be auto-detected.

=item destip

The new IP address.

See C<swap_zonefile_obj_ips> and C<swap_zonefile_spf_ips> for usage.

=item ftpip

The new IP address for FTP records.

See C<swap_zonefile_obj_ips> and C<swap_zonefile_spf_ips> for usage.

=item zoneref

A C<HASHREF> of previously fetched zones, where the keys are domains in the domainref.

Any zones not provided by this C<HASHREF> will be fetched during execution.

=item showmsgs

An optional boolean flag that indicates whether to print some messaging about the number of records updated in each zone.

This defaults to falsy so the messaging will not be printed.

=item skipreload

An optional boolean flag that indicates whether to skip reloading the updated zones after all updates are complete.

This defaults to falsy so the reload will not be skipped.

=item skipsync

An optional boolean flag that indicates whether to skip synchronization of the updated zones after all updates are complete.

This defaults to falsy so the sync will not be skipped.

=item replaceip

C<all> or C<basic>, defaulting to C<all>

See the corresponding option on C<swap_zonefile_obj_ips> for implementation specifics

=item dnslocal

Either C<REMOTE_AND_LOCAL> or C<LOCAL_ONLY> as defined by L<Cpanel::DnsUtils::AskDnsAdmin>.

This determines whether to consider remote zones or only local zone when fetching, reloading, and syncing zone files.

This defaults to C<REMOTE_AND_LOCAL>.

=back

=item Output

Returns an C<ARRAYREF> of the records that were changed with their previous values.

=back

=cut

sub swap_ip_in_zones (%opts) {

    my $domainref  = $opts{domainref};
    my $sourceip   = $opts{sourceip};
    my $destip     = $opts{destip};
    my $ftpip      = $opts{ftpip};
    my $zoneref    = $opts{zoneref};
    my $showmsgs   = $opts{showmsgs}   || 0;
    my $skipreload = $opts{skipreload} || 0;
    my $skipsync   = $opts{skipsync}   || 0;
    my $replaceip  = $opts{replaceip}  || 'all';
    my $dnslocal   = $opts{dnslocal}   || $Cpanel::DnsUtils::AskDnsAdmin::REMOTE_AND_LOCAL;

    my %sourceips;
    if ($sourceip) {
        if ( ref $sourceip ) {
            %sourceips = map { $_ => 1 } @{$sourceip};
        }
        elsif ( $sourceip ne -1 ) {
            $sourceips{$sourceip} = 1;
        }
        delete $sourceips{''};    #safety
    }

    my @fetchlist;
    foreach my $domain (@$domainref) {
        if ( !$zoneref->{$domain} ) {
            push @fetchlist, $domain;
        }
    }

    my @replaced;
    if (@fetchlist) {

        my $added_zoneref = Cpanel::DnsUtils::Fetch::fetch_zones( 'zones' => \@fetchlist, 'flags' => $dnslocal );
        @{$zoneref}{ keys %$added_zoneref } = values %$added_zoneref;
    }

    foreach my $zone ( keys %$zoneref ) {
        my $zf = Cpanel::ZoneFile->new( 'text' => $zoneref->{$zone}, 'domain' => $zone );

        if ( !scalar keys %sourceips ) {
            my $previous_ip = get_sourceip_from_zonefile_obj($zf) or next;
            $sourceips{$previous_ip} = 1;
        }

        push @replaced, swap_zonefile_obj_ips(
            'sourceips_hr'  => \%sourceips,
            'domain'        => $zone,
            'zone_file_obj' => $zf,
            'destip'        => $destip,
            'replaceip'     => $replaceip,
            'ftpip'         => $ftpip,
        );

        push @replaced, swap_zonefile_spf_ips(
            'sourceips_hr'  => \%sourceips,
            'domain'        => $zone,
            'zone_file_obj' => $zf,
            'destip'        => $destip,
        );

        $zf->increase_serial_number();

        # it is critical that that hashref of zones is updated so multiple ip changes operate on the new zone
        $zoneref->{$zone} = $zf->to_zone_string();

    }

    my $zdata;
    my @RELOADLIST;
    foreach my $zone ( keys %$zoneref ) {
        if ( !$zoneref->{$zone} ) {
            next();
        }

        if ($showmsgs) { print "Changed $replaceip instances of [" . join( ',', keys %sourceips ) . "] -> [$destip] in $zone\n"; }

        push @RELOADLIST, $zone;

        $zdata .= 'cpdnszone-' . Cpanel::Encoder::URI::uri_encode_str($zone) . '=' . Cpanel::Encoder::URI::uri_encode_str( $zoneref->{$zone} ) . '&';
    }

    if ( !$skipsync ) {
        Cpanel::DnsUtils::AskDnsAdmin::askdnsadmin( 'SYNCZONES', $dnslocal, '', '', '', $zdata );
    }
    if ( !$skipreload ) { Cpanel::DnsUtils::AskDnsAdmin::askdnsadmin( 'RELOADZONES', $dnslocal, join( ',', @RELOADLIST ) ); }
    return \@replaced;
}

=head2 get_sourceip_from_zonefile_obj($zone_file_obj)

Returns an IP address auto-detected from the zone file.

If there is an A record for the root of the zone and it is not a loopback IP then that IP is returned.

If there is no A record for the root of the zone then the address of the first A record that does not point to a loopback address is returned.

If there are no A records or all A records point to loopback addresses the function returns undef.

=cut

sub get_sourceip_from_zonefile_obj {
    my ($zone_file_obj) = @_;

    my $zone = $zone_file_obj->{'zoneroot'};

    my $main_a_records_ar = $zone_file_obj->find_records_cached( 'type' => 'A', 'name' => $zone . '.' );
    if ( @$main_a_records_ar && $main_a_records_ar->[0]->{'address'} && !Cpanel::IP::Loopback::is_loopback( $main_a_records_ar->[0]->{'address'} ) ) {
        return $main_a_records_ar->[0]->{'address'};
    }
    my $arecords_ar = $zone_file_obj->find_records_cached( 'type' => 'A' );
    if ( @$arecords_ar && $arecords_ar->[0]->{'address'} && !Cpanel::IP::Loopback::is_loopback( $arecords_ar->[0]->{'address'} ) ) {
        return $arecords_ar->[0]->{'address'};
    }
    return;

}

=head2 swap_zonefile_obj_ips(%OPTS)

Swap the IP addresses that match the provided source IP
addresses for the new IP and/or new ftp IP.

This function modifies the zone file object.

=over 2

=item Input is a hash with the following keys:

=over 3

=item zone_file_obj C<Cpanel::ZoneFile>

    A C<Cpanel::ZoneFile> to operate on

=item sourceips_hr C<HASHREF>

    A hashref with the source ips as the keys
    Example
    {
        '1.1.1.1' => 1,
        '2.2.2.2' => 2,
    }

    These IPs are expected to be public ips.
    Consider Cpanel::NAT::get_public_ip()

=item destip C<SCALAR>

    The new ip address that will replace all the
    source IPS in sourceips_hr that match
    the zone

    This IPs is expected to be a public ip.
    Consider Cpanel::NAT::get_public_ip()

=item ftpip C<SCALAR> (optional)

    The new ftp ip address that will replace all
    dns names that begin with ftp

    This IPs is expected to be a public ip.
    Consider Cpanel::NAT::get_public_ip()

=item replaceip C<SCALAR>

    all or basic

    If 'all' is specified all A entries that
    match one of the source ip will be modified.

    If 'basic' is speciifed, only A entries that
    match one of the source ip and are for the
    domain the zone is for or a service (formerly proxy) subdomain
    of the domain the zone is for will be modified.

=back

=item Output

In scalar context, returns the number of entries in the zone_file_obj that
were modified.

In list context, returns the entries in the zone_file_obj that were modified
along with their previous values.

=back

=cut

sub swap_zonefile_obj_ips {
    my (%OPTS) = @_;

    _generate_static_domains() if !$hr_STATICDOMAINS;

    my ( $zone_file_obj, $sourceips_hr, $ftpip, $destip, $replaceip ) = @OPTS{qw(zone_file_obj sourceips_hr ftpip destip replaceip)};

    my $domain = $zone_file_obj->{'zoneroot'};

    if ( !scalar keys %$sourceips_hr ) {
        my $sourceip = get_sourceip_from_zonefile_obj($zone_file_obj) or return 0;
        $sourceips_hr->{$sourceip} = 1;
    }

    my @replaced;
    my $arecords_ar = $zone_file_obj->find_records_cached( 'type' => 'A' );
    my $zone        = $zone_file_obj->{'zoneroot'};
    for my $i ( 0 .. $#{$arecords_ar} ) {
        my $dnsname = $arecords_ar->[$i]->{'name'};
        if ( $dnsname !~ /\.$/ ) {
            $dnsname .= '.' . $zone;
        }
        else {
            $dnsname =~ s/\.$//g;
        }
        if ( exists $hr_STATICDOMAINS->{ lc($dnsname) } ) {
            next;
        }

        # only replace if it is the zone name or a known service (formerly proxy) subdomain and currently has a source IP
        if ( _should_replace( $dnsname, $zone, $replaceip ) && exists $sourceips_hr->{ $arecords_ar->[$i]->{'address'} } ) {
            my $new_addr = ( $ftpip && index( $dnsname, 'ftp.' ) == 0 ) ? $ftpip : $destip;
            push @replaced, {
                zone_name   => $zone,
                record_name => $dnsname,
                record_type => 'A',
                old_value   => $arecords_ar->[$i]->{'address'},
                new_value   => $new_addr,
            };
            $arecords_ar->[$i]->{'address'} = $new_addr;
        }
    }

    $zone_file_obj->replace_records($arecords_ar);

    return wantarray ? @replaced : scalar @replaced;
}

=head2 swap_zonefile_spf_ips(%OPTS)

Swap the IP addresses that match the provided source IP
addresses for the new IP and/or new ftp IP.

This function modifies the zone file object.

=over 2

=item Input is a hash with the following keys:

=over 3

=item zone_file_obj C<Cpanel::ZoneFile>

    A C<Cpanel::ZoneFile> to operate on

=item sourceips_hr C<HASHREF>

    A hashref with the source ips as the keys
    Example
    {
        '1.1.1.1' => 1,
        '2.2.2.2' => 2,
    }

    These IPs are expected to be public ips.
    Consider Cpanel::NAT::get_public_ip()

=item destip C<SCALAR>

    The new ip address that will replace all the
    source IPS in sourceips_hr that match
    the zone

    This IPs is expected to be a public ip.
    Consider Cpanel::NAT::get_public_ip()

=back

=item Output

In scalar context, returns the number of entries in the zone_file_obj that
were modified.

In list context, returns the entries in the zone_file_obj that were modified
along with their previous values.

=back

=cut

sub swap_zonefile_spf_ips {
    my (%OPTS) = @_;

    _generate_static_domains() if !$hr_STATICDOMAINS;

    my ( $zone_file_obj, $sourceips_hr, $destip ) = @OPTS{qw(zone_file_obj sourceips_hr destip )};

    my $domain = $zone_file_obj->{'zoneroot'};
    my $mainip = Cpanel::NAT::get_public_ip( Cpanel::DIp::MainIP::getmainserverip() );

    if ( !scalar keys %$sourceips_hr ) {
        my $sourceip = get_sourceip_from_zonefile_obj($zone_file_obj) or return 0;
        $sourceips_hr->{$sourceip} = 1;
    }

    my @replaced;
    my $txtrecords_ar = $zone_file_obj->find_records_cached( 'type' => 'TXT' );
    my $zone          = $zone_file_obj->{'zoneroot'};
  TXTRECORD:
    for my $i ( 0 .. $#{$txtrecords_ar} ) {
        next TXTRECORD if $txtrecords_ar->[$i]->{'txtdata'} !~ m/^v=spf1/;

        my @keys_list;
        push @keys_list, "+ip4:$destip" if ( $destip ne $mainip );
        push @keys_list, grep { !/:$mainip$/ && /:/ && !/:$destip$/ } split( / +?/, $txtrecords_ar->[$i]->{'txtdata'} );
        my $is_complete = ( $txtrecords_ar->[$i]->{'txtdata'} =~ / -all/ );
        my $new_value   = Cpanel::SPF::String::make_spf_string( \@keys_list, undef, $is_complete, $domain );

        # make_spf_string can't "see" the pending changes, so it still thinks the dedicated IP is there, even
        # if you're removing it.
      DELETE_ADDRESS:
        foreach my $src_ip ( keys %{$sourceips_hr} ) {
            next DELETE_ADDRESS if ( $src_ip eq $mainip );
            $new_value =~ s/\+?ip[46]:$src_ip //g;
        }

        push @replaced, {
            zone_name   => $zone,
            record_name => $txtrecords_ar->[$i]->{'name'},
            record_type => 'TXT',
            old_value   => $txtrecords_ar->[$i]->{'txtdata'},
            new_value   => $new_value,
        };

        $txtrecords_ar->[$i]->{'txtdata'} = $new_value;
        $txtrecords_ar->[$i]->{'char_str_list'}->[0] = $new_value;
    }

    $zone_file_obj->replace_records($txtrecords_ar);

    return wantarray ? @replaced : scalar @replaced;
}

sub _should_replace {
    my ( $dnsname, $zone, $replaceip ) = @_;

    if ( $replaceip eq 'all' ) {
        return 1;
    }
    elsif ( $replaceip eq 'basic' ) {
        my @pieces = split( /\./, $dnsname );
        if ( !defined $cpzones ) {
            my $proxies = Cpanel::Proxy::Tiny::get_known_proxy_subdomains( { include_disabled => 1 } );

            # we also need to check for the mail and ftp record which can be A records
            $cpzones = { map ( { $_ => 1 } keys %$proxies ), 'mail' => 1, 'ftp' => 1 };
        }

        # $dnsname and $zone both lack trailing dot, so don't add it when comparing
        return 1 if $dnsname eq $zone || $dnsname eq '@' || scalar @pieces > 2 && $cpzones->{ $pieces[0] };
        return;
    }
    print "Invalid replaceip value ($replaceip); assuming 'all' ...\n";
    return 1;
}

sub reset_static_domains {
    $hr_STATICDOMAINS = undef;
    return 1;
}

sub _generate_static_domains {
    $hr_STATICDOMAINS = {};
    my $reseller_nameservers = Cpanel::NameserverCfg::get_all_reseller_nameservers();
    foreach my $reseller ( keys %$reseller_nameservers ) {
        foreach my $ns ( @{ $reseller_nameservers->{$reseller} } ) {
            $hr_STATICDOMAINS->{ lc $ns } = 1;
        }
    }
    $hr_STATICDOMAINS->{ Cpanel::Hostname::gethostname() } = 1;
    return 1;
}

1;
