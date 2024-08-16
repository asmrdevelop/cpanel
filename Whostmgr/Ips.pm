package Whostmgr::Ips;

# cpanel - Whostmgr/Ips.pm                         Copyright 2022 cPanel, L.L.C.
#                                                           All rights reserved.
# copyright@cpanel.net                                         http://cpanel.net
# This code is subject to the cPanel license. Unauthorized copying is prohibited

use strict;
## no critic qw(TestingAndDebugging::RequireUseWarnings)
#
use Cpanel::Ips                     ();
use Cpanel::NAT::Object             ();
use Cpanel::LoadFile                ();
use Cpanel::Config::LoadWwwAcctConf ();
use Cpanel::DIp::MainIP             ();
use Cpanel::DIp::IsDedicated        ();
use Cpanel::IpPool                  ();
use Cpanel::IP::Configured          ();
use Cpanel::LoadModule              ();
use Cpanel::NAT                     ();
use Cpanel::SafeFile                ();
use Cpanel::SafeRun::Object         ();
use Cpanel::Services::Enabled       ();
use Cpanel::Services::Restart       ();
use Cpanel::StringFunc::Trim        ();
use Cpanel::SafeRun::Errors         ();
use Cpanel::Validate::IP::v4        ();
use Cpanel::Debug                   ();

use Try::Tiny;

=head1 NAME

Whostmgr::Ips - add and delete ips

=head1 DESCRIPTION

This module provides functions to add/delete ips and several network helpers.

=head2 Functions

=cut

our $TIME_BETWEEN_NSD_RESTARTS = 45;    # It takes about 20s to restart so we need to ensure we don't trample over restarts and fail

# 2**( 32 - cidr )
our %HOSTCOUNT = (
    '24' => 256,
    '25' => 128,
    '26' => 64,
    '27' => 32,
    '28' => 16,
    '29' => 8,
    '30' => 4,
);

# ip/mask returns the lowest IP still in the same netmask.

sub calculate_network {
    my ( $ip, $mask ) = @_;
    $mask or return undef;
    $ip   or return undef;

    require Socket;
    my $nip   = Socket::inet_aton($ip);
    my $nmask = Socket::inet_aton($mask);
    return Socket::inet_ntoa( $nip & $nmask );
}

# Returns something like eth0:196.168.1.0

sub make_adapter_network_key {
    my $ipcfg   = shift;
    my @iface   = split( /:/, $ipcfg->{'if'} );
    my $adapter = shift @iface;
    return join ':', $adapter, calculate_network( $ipcfg->{'ip'}, $ipcfg->{'mask'} );
}

# Case 34353: the Linux kernel stores IP addresses in a map-like structure
# keyed on a leader address for a particular interface+subnet combination.
# Downing the leader address downs all the aliases that it keys to.
#
# This function may be called with only the IP address.  If it is going to be
# called repeatedly, it's best to pass in the data structure returned by
# Cpanel::Ips::fetchifcfg as the second parameter.

sub is_a_leader_alias_with_dependents {
    my ( $ip, $ifref ) = @_;

    my $ips_in_subnet = {};
    my $subnet;

    $ifref ||= Cpanel::Ips::fetchifcfg();
    foreach my $ifc (@$ifref) {
        my $network = make_adapter_network_key($ifc);
        if ( $ifc->{'ip'} eq $ip ) {
            $subnet = $network;
        }
        if ( exists $ips_in_subnet->{$network} ) {
            push @{ $ips_in_subnet->{$network} }, $ifc->{'ip'};
        }
        else {
            $ips_in_subnet->{$network} = [ $ifc->{'ip'} ];
        }
    }

    # It's only a leader if there are 2 ips attached to the device in the same subnet.
    return 0 if ( !$subnet or !ref $ips_in_subnet->{$subnet} or scalar @{ $ips_in_subnet->{$subnet} } < 2 );

    # It's only a leader if it's the first item in the array: $ips_in_subnet->{$subnet}
    return $ip eq shift @{ $ips_in_subnet->{$subnet} } ? 1 : 0;
}

sub get_detailed_ip_cfg {
    my $ifref = _dedupe_iplist( Cpanel::Ips::fetchifcfg() );

    # List from /etc/ipaddrpool
    my $unalip      = Cpanel::DIp::IsDedicated::getunallocatedipslist() || [];
    my %unallocated = map { $_ => 1 } @$unalip;

    my $mainaddr          = Cpanel::DIp::MainIP::getmainserverip();
    my $envtype           = Cpanel::LoadFile::loadfile('/var/cpanel/envtype');
    my $is_restricted_vps = ( $envtype eq 'cpanel-vserver' ? 1 : 0 );

    my @IPS;
    foreach my $bound_ip (@$ifref) {
        my $ip      = $bound_ip->{'ip'};
        my $netmask = $bound_ip->{'mask'};
        my $used    = $unallocated{$ip} ? 0 : 1;
        push @IPS,
          {
            'ip'        => $ip,
            'mainaddr'  => $ip eq $mainaddr ? 1 : 0,
            'if'        => $bound_ip->{'if'},
            'active'    => 1,
            'used'      => $used,
            'removable' => ( $is_restricted_vps || $ip eq $mainaddr || $used || $bound_ip->{'if'} =~ /venet/ ) ? 0 : 1,
            'dedicated' => Cpanel::DIp::IsDedicated::isdedicatedip($ip)                                        ? 1 : 0,
            'netmask'   => $netmask,
            'network'   => calculate_network( $ip, $netmask ),
          };
    }

    return \@IPS;
}

sub _dedupe_iplist {
    my ($iplist_aref) = @_;
    my @iplist;
    my %seen;
    for my $ip_info (@$iplist_aref) {
        my $concat = sprintf( "%s|%s|%s", $ip_info->{'if'}, $ip_info->{'ip'}, $ip_info->{'mask'} );
        push( @iplist, $ip_info ) unless ( exists $seen{$concat} );
        $seen{$concat}++;
    }
    return \@iplist;
}

sub get_ethernet_dev {
    my $wwwacct_ref = Cpanel::Config::LoadWwwAcctConf::loadwwwacctconf();
    if ( $wwwacct_ref->{'ETHDEV'} ) {
        return Cpanel::StringFunc::Trim::ws_trim( $wwwacct_ref->{'ETHDEV'} );
    }

    my $ifref = Cpanel::Ips::fetchifcfg();
    return $ifref->[0]->{'if'};
}

sub valid_ethernet_dev {
    my $ethdev = shift;

    return 0 if !$ethdev;

    Cpanel::LoadModule::load_perl_module('Cpanel::Linux::RtNetlink');

    return grep { defined && $_ eq $ethdev } @{ Cpanel::Linux::RtNetlink::get_interfaces('AF_INET') };
}

sub get_routes {
    my @lines = Cpanel::SafeRun::Errors::saferunnoerror( '/sbin/ip', '-4', 'route', 'show' );
    my @routes;
    foreach my $line (@lines) {
        $line =~ s/default/0.0.0.0/g;
        if ( $line =~ m/^(\d{1,3}\.\d{1,3}\.\d{1,3}\.\d{1,3}|default)\s+via\s+(\d{1,3}\.\d{1,3}\.\d{1,3}\.\d{1,3})\s+/ ) {
            push @routes,
              {
                'destination' => $1,
                'gateway'     => $2
              };
        }
    }

    return @routes;
}

sub get_gateways {
    my @gateways;
    foreach my $route ( get_routes() ) {
        push @gateways, $route->{'gateway'};
    }
    return @gateways;
}

sub netmask_at_least_as_permissive_as_cidr {
    my ( $netmask, $cidr ) = @_;
    require Socket;
    my $n_mask            = unpack 'N', Socket::inet_aton($netmask);
    my $cidr_hosts_n_mask = 2**( 32 - $cidr ) - 1;
    return !( $n_mask & $cidr_hosts_n_mask );
}

sub cidr_to_netmask {
    my ($cidr) = @_;
    require Socket;
    my $nmask = ( 2**( 32 - $cidr ) - 1 ) ^ unpack 'N', Socket::inet_aton('255.255.255.255');
    return Socket::inet_ntoa( pack 'N', $nmask );
}

# subnet beginning will be determined based on the starting octet (a)
sub align_class_c_hosts_range_to_subnet {
    my ( $netmask, $oct_a_in_out, $oct_b_in_out ) = @_;
    return if $$oct_a_in_out > $$oct_b_in_out;

    my $oct_a = $$oct_a_in_out;
    my $oct_b = $$oct_b_in_out;
    require Socket;
    my $nmask = unpack 'N', Socket::inet_aton($netmask);
    my $hmask = $nmask ^ unpack 'N', Socket::inet_aton('255.255.255.255');

    my $block_end   = $oct_a | $hmask;
    my $block_start = $block_end - $hmask;

    return if $oct_b > $block_end;
    return if $oct_a < $block_start;

    # The first an last ips in the subnet will not be usable
    if ( $oct_a == $block_start ) {
        ++$oct_a;
    }
    if ( $oct_b == $block_end ) {
        --$oct_b;
    }

    $$oct_a_in_out = $oct_a;
    $$oct_b_in_out = $oct_b;

    return 1;
}

sub expand_ips {
    my ( $ip, $netmask, $ips_out, $errors_out ) = @_;

    return ( 0, "No IP was given." )      if !length $ip;
    return ( 0, "No netmask was given." ) if !length $netmask;

    if ( $ip =~ m/^127\./ ) {

        # http://www.iana.org/assignments/ipv4-address-space/
        # nothing in 127/8 should be allowed here
        return 0, 'Invalid IP address; loopback addresses not allowed.';
    }

    if ( $ip =~ m/^(\d{1,3})\.(\d{1,3})\.(\d{1,3})\.(\d{1,3})(.*)$/ ) {
        my (@ipquads) = ( $1, $2, $3, $4 );
        my $last = $5;
        if ( $ipquads[0] =~ m/^0+$/ ) {

            # don't allow ips that start with zeros, 0.x.x.x
            return 0, 'IP address entered does not appear to be in a valid format.';
        }
        my @newipquads;
        foreach my $quad (@ipquads) {
            if ( $quad > 255 ) {

                # catch out of range quads early on
                push @{$errors_out}, 'IP address entered does not appear to be in a valid format.';
            }
            if ( $quad =~ m/^0+$/ ) {

                # convert multiple zeros to just one
                $quad =~ s/^0+/0/g;
            }
            elsif ( $quad =~ m/^0+([1-9]+)$/ ) {

                # remove zeros from before a number 1-9
                $quad = $1;
            }
            push @newipquads, $quad;
        }
        $ip = join '.', @newipquads;

        # tack on any remaining cidr or range notation and let it carry on its way
        $ip .= $last;
    }
    else {
        return 0, "IP address entered ($ip) does not appear to be in a valid format.";
    }

    if ( $netmask !~ m/^\d+\.\d+\.\d+\.\d+$/ ) {
        return 0, "$netmask is not a vaild netmask.";
    }

    if ( $ip =~ /\// ) {

        # checking for cidr input
        my ( $temp_ip, $cidr ) = split( /\//, $ip );

        my ( $ipp1, $ipp2, $ipp3, $startip ) = split( /\./, $temp_ip );

        if ( $cidr < 24 || $cidr > 30 ) {
            return 0, 'Invalid Class C CIDR notation';
        }
        if ( !netmask_at_least_as_permissive_as_cidr( $netmask, $cidr ) ) {
            return 0, 'Netmask is more restrictive than specified CIDR record';
        }

        my $blockstart = $startip | ( $HOSTCOUNT{$cidr} - 1 );
        $blockstart -= $HOSTCOUNT{$cidr} - 1;
        my $endip = $blockstart + $HOSTCOUNT{$cidr} - 1;

        my $cidr_netmask = cidr_to_netmask($cidr);
        if ( !align_class_c_hosts_range_to_subnet( $cidr_netmask, \$startip, \$endip ) ) {

            # this really shouldn't ever happen
            return 0, 'CIDR range conflict';
        }

        for ( my $i = $startip; $i <= $endip; $i++ ) {
            push @{$ips_out}, "${ipp1}.${ipp2}.${ipp3}.$i";
        }
    }
    elsif ( $ip =~ /-/ ) {

        # checking for range input
        my ( $temp_ip, $endip ) = split( /-/, $ip );
        my ( $ipp1, $ipp2, $ipp3, $startip ) = split( /\./, $temp_ip );
        if ( $endip !~ /^(\d+)$/ ) {
            return 0, 'Multiple IP addressess must be in the format 192.168.0.1-254!';
        }
        if ( $endip > 255 || $startip < 0 ) {
            return 0, 'Invalid IP Address.  Addresses must NOT be less than 0 or greater than 255!';
        }
        if ( $endip < $startip ) {
            return 0, 'End IP address must be larger than start IP address';
        }
        if ( !align_class_c_hosts_range_to_subnet( $netmask, \$startip, \$endip ) ) {
            return 0, 'IP range conflicts with provided netmask.';
        }
        for ( my $i = $startip; $i <= $endip; $i++ ) {
            next if $i == 0;
            push @{$ips_out}, "${ipp1}.${ipp2}.${ipp3}.$i";
        }
    }
    else {
        if ( Cpanel::Validate::IP::v4::is_valid_ipv4($ip) ) {
            push @{$ips_out}, $ip;
        }
        else {
            return 0, "Invalid IP [$ip] Address!";
        }
    }

    return 1;
}

sub get_ifnum_max {
    my ($ethdev) = @_;

    my $ifnum = 0;

    foreach my $dev ( @{ Cpanel::Ips::fetchifcfg() } ) {
        my ($xnum) = $dev->{'if'} =~ m{\Q$ethdev\E:(\S+)};
        next if !$xnum;
        $xnum =~ s/^cp//;
        if ( $xnum > $ifnum ) {
            $ifnum = $xnum;
        }
    }

    return $ifnum;
}

sub _nsd_touch_file {
    return '/var/cpanel/usensd';
}

sub restart_nsd {

    # nsd isn't installed on this system.
    return () if ( !-e _nsd_touch_file() );

    Cpanel::LoadModule::load_perl_module('Cpanel::ServerTasks');
    Cpanel::ServerTasks::schedule_task( ['CpServicesTasks'], $TIME_BETWEEN_NSD_RESTARTS, "restartsrv nsd" );

    return ();
}

sub _etc_ips {
    return '/etc/ips';
}

sub add_to_etc_ips {
    my ( $ip, $inputnetmask, $broadcast ) = @_;

    my $ips_fh;
    my $ipl;
    try {
        $ipl = Cpanel::SafeFile::safeopen( $ips_fh, '+<', _etc_ips() );
    }
    catch {
        Cpanel::Debug::log_warn($_);
    };
    if ( !$ipl ) {
        return 0;
    }

    # See if the ip was already in the file already.
    my $found;
    while ( my $line = <$ips_fh> ) {
        $found = 1 if ( $line eq "$ip:$inputnetmask:$broadcast\n" );
    }

    # Put the new IP in the file if we didn't see it.
    print {$ips_fh} "$ip:$inputnetmask:$broadcast\n" if ( !$found );

    Cpanel::SafeFile::safeclose( $ips_fh, $ipl );
    return 1;
}

sub remove_from_etc_ips {
    my ($inputip) = @_;

    return 1 unless length $inputip;    # Nothing gets done when $inputip has no content.

    my $ips_fh;
    my $ips_file = _etc_ips();

    my $ipl;
    try {
        $ipl = Cpanel::SafeFile::safeopen( $ips_fh, '+<', $ips_file );
    }
    catch {
        Cpanel::Debug::log_warn($_);
    };
    if ( !$ipl ) {
        return 0, "Failed to open $ips_file for writing.";
    }

    my @IPL;
    my $removed_ip;
    while ( my $line = <$ips_fh> ) {
        chomp $line;
        next unless $line =~ m/:/;

        if ( ( split /:/, $line, 2 )[0] eq $inputip ) {
            $removed_ip = 1;
            next;
        }
        push @IPL, $line;
    }

    if ($removed_ip) {
        seek $ips_fh, 0, 0;
        print {$ips_fh} join( "\n", @IPL ) . "\n";
        truncate $ips_fh, tell $ips_fh;
    }

    Cpanel::SafeFile::safeclose( $ips_fh, $ipl );

    if ( !$removed_ip ) {
        return 0, 'Failed to remove IP address.';
    }

    return 1;
}

sub remove_ips_cpnat {
    my ($inputip) = @_;

    return 1 unless length $inputip;    # Nothing gets done when $inputip has no content.

    my $nat_obj = Cpanel::NAT::Object->new();

    # Couldn't read the file. There's nothing to delete.
    return 1 unless $nat_obj->{'file_read'};

    my $cpnat_file = $nat_obj->{'cpnat_file'};

    my $cpnat_fh;
    my $cpnat_safe = Cpanel::SafeFile::safeopen( $cpnat_fh, '+<', $cpnat_file );

    if ( !$cpnat_safe ) {
        return 0, 'Failed to open ' . $cpnat_file . ' for writing.';
    }

    my @IPL;
    my $removed_ip;
    while ( my $line = <$cpnat_fh> ) {
        chomp $line;
        next unless $line =~ m/\S/;

        if ( ( split /\s+/, $line, 2 )[0] eq $inputip ) {
            ++$removed_ip;
        }
        else {
            push @IPL, $line;
        }
    }

    if ($removed_ip) {
        seek $cpnat_fh, 0, 0;
        if (@IPL) {
            print {$cpnat_fh} join( "\n", @IPL ) . "\n";
        }
        truncate $cpnat_fh, tell $cpnat_fh;
    }

    Cpanel::SafeFile::safeclose( $cpnat_fh, $cpnat_safe );
    require Cpanel::NAT::Build;
    Cpanel::NAT::Build::update();

    return 1;
}

sub system_add_ip {
    my ( $ip, $prefix, $broadcast, $eth, $ethr ) = @_;

    # CPANEL-11853
    # Using the batch method seems to report erroneous errors.
    # Split this into two separate calls to avoid errors.
    my $addr_add_run = Cpanel::SafeRun::Object->new(
        'program' => '/sbin/ip',
        'args'    => [ '-family' => 'inet', 'addr', 'add' => "$ip/$prefix", 'broadcast' => $broadcast, "dev" => $eth, "label" => $ethr ],
    );

    my $route_add_run = Cpanel::SafeRun::Object->new(
        'program' => '/sbin/ip',
        'args'    => [ '-family' => 'inet', 'route', 'add' => $ip, 'dev' => $eth ],
    );

    my $output = _convert_saferun_output_to_text($addr_add_run);
    $output .= _convert_saferun_output_to_text($route_add_run);

    my $ok = !$addr_add_run->CHILD_ERROR() && !$route_add_run->CHILD_ERROR() ? 1 : 0;
    return ( $ok, $output );
}

sub system_del_ip {
    my ( $inputip, $ip_prefix, $ethdev ) = @_;
    my $run = Cpanel::SafeRun::Object->new(
        'program' => '/sbin/ip',
        'args'    => [ '-family' => 'inet', '-batch', '-' ],
        'stdin'   => "addr del $inputip/$ip_prefix dev $ethdev\nroute del $inputip dev $ethdev\n",
    );
    return _convert_saferun_output_to_text($run);
}

# Make Cpanel::SafeRun::Object act like legacy
# saferunallerrors
sub _convert_saferun_output_to_text {
    my @runs = @_;
    my $text = '';
    foreach my $run (@runs) {
        $text .= $run->stdout();
        if ( $run->CHILD_ERROR() ) {
            $text .= ": " if length $text;
            $text .= $run->autopsy() . ": " . $run->stderr();
        }
    }
    return $text;
}

sub addip {
    my ( $inputip, $inputnetmask, $exclude_list ) = @_;
    $inputip ||= '';         # Guard against undef.
    $inputip =~ s/\s+//g;    # Remove whitespace from the string.

    if ( 'ARRAY' ne ref $exclude_list ) {
        $exclude_list = [];
    }

    my @msgs;
    my @errors;
    my @ADDIPS;

    my ( $result, $why ) = expand_ips( $inputip, $inputnetmask, \@ADDIPS, \@errors );
    return ( $result, $why ) if !$result;

    # The keys for $cfg_ips is the list of IPs already on this system.
    my $cfg_ips = Cpanel::Ips::load_configured_ips();       # From /etc/ips
    my $mainip  = Cpanel::DIp::MainIP::getmainserverip();
    $cfg_ips->{$mainip} = 1;

    # i.e. eth0
    my $ethdev = get_ethernet_dev();

    if ( !valid_ethernet_dev($ethdev) ) {
        push @errors, "Invalid ethernet device ($ethdev)";
        return ( 0, "Could not locate the configured ethernet device ($ethdev). Please correct this in Basic WebHost Manager® Setup.", \@msgs, \@errors );
    }

    # The array of IPs that are known gateways.
    my @gateways = get_gateways();

    my $ips_added = 0;

    my $natd;
    my $publicips = [];
    if ( Cpanel::NAT::is_nat() ) {
        Cpanel::LoadModule::load_perl_module('Cpanel::NAT::Discovery');
        $natd      = Cpanel::NAT::Discovery->new();
        $publicips = Cpanel::NAT::get_all_public_ips();
    }

    foreach my $ip (@ADDIPS) {
        if ( exists $cfg_ips->{$ip} ) {
            push @errors, "Skipping $ip .. already added.";
            next;
        }
        if ( !Cpanel::Validate::IP::v4::is_valid_ipv4($ip) ) {
            push @errors, "$ip is not a vaild IP address.";
            next;
        }
        if ( grep { $_ eq $ip } @gateways ) {
            push @errors, "Skipping $ip .. gateway detected.";
            next;
        }
        if ( grep { $_ eq $ip } @$exclude_list ) {
            push @errors, "Skipping $ip .. excluded by user.";
            next;
        }
        if ( grep { $_ eq $ip } @$publicips ) {
            push @errors, "Skipping $ip .. already a public IP for a NAT IP.";
            next;
        }

        my %ip_info;
        my ( $result, $why ) = Cpanel::Ips::get_ip_info( $ip, $inputnetmask, \%ip_info );
        if ( !$result ) {
            $why .= '.';    # get_ip_info doesn't include a period. let's be consistent.
            push @errors, $why;

            # Make the failure explanation more clear if just this one IP was added.
            if ( scalar @ADDIPS == 1 ) {
                return ( $result, $why, \@msgs, \@errors );
            }

            # Otherwise chug on to the next IP.
            next;
        }

        my $broadcast = $ip_info{'broadcast'};
        my $network   = $ip_info{'network'};

        add_to_etc_ips( $ip, $inputnetmask, $broadcast );

        my $eth   = $ethdev;
        my $ifnum = get_ifnum_max($ethdev);

        $ips_added++;
        $ifnum++;
        my $ethr   = "$eth:cp$ifnum";
        my $prefix = Cpanel::Ips::convert_quad_to_prefix($inputnetmask);

        my ( $ok, $output ) = system_add_ip( $ip, $prefix, $broadcast, $eth, $ethr );

        if ( !$ok ) {
            push @errors, $output;
        }
        elsif ($output) {
            push @msgs, "Bringing up $ethr ($ip) ... $output";
        }
        else {
            push @msgs, "$ethr is now up. $ip/$inputnetmask broadcast $broadcast has been added.";
        }

        if ($natd) {
            eval { $natd->verify_route($ip) };

            # fatal error encountered, no need to try again
            if ($@) {
                push @errors, "Unable to map $ip to a NAT ip";
                $natd = undef;
            }
        }
    }

    if ( $natd && $ips_added ) {
        eval { $natd->write_cpnat_file( { append => 1 } ) };
        if ($@) {
            push @msgs, "Unable to update cpnat file ... $@";
        }
        Cpanel::NAT::reload();
        require Cpanel::NAT::Build;
        Cpanel::NAT::Build::update();
    }

    # We need to clear the cache before calling rebuild, since rebuild may use the cached data.
    Cpanel::IP::Configured::clear_configured_ips_cache();
    Cpanel::IpPool::rebuild();

    push @msgs, restart_nsd();

    if ( !$ips_added ) {
        if ( scalar(@ADDIPS) > 1 ) {
            if ( my $exclude_count = scalar @$exclude_list ) {
                return ( 0, "All requested IPs ($inputip, $exclude_count exclusion(s)) are already active.", \@msgs, \@errors );
            }
            else {
                return ( 0, "All requested IPs ($inputip) are already active.", \@msgs, \@errors );
            }
        }
        else {
            return ( 0, "$inputip is already an active IP.", \@msgs, \@errors );
        }
    }
    elsif ( scalar @errors > 0 ) {
        return ( 0, 'Error', \@msgs, \@errors );
    }
    else {
        return ( 1, 'Success', \@msgs, \@errors );
    }
}

sub delip {
    my ( $inputip, $ethernet_device, $skip_if_shutdown, $force ) = @_;

    # Validate $inputip is a valid IPv4 address.
    $inputip ||= '';
    $inputip =~ s/^\s+//g;
    $inputip =~ s/\s+$//g;
    if ( !Cpanel::Validate::IP::v4::is_valid_ipv4($inputip) ) {
        return 0, "The address '$inputip' is not a valid IPv4 address.";
    }

    if ( $inputip eq Cpanel::DIp::MainIP::getmainserverip() ) {
        return 0, "You cannot remove the main IP address ($inputip).";
    }

    my $ifref           = Cpanel::Ips::fetchifcfg();
    my %active          = map { $_->{'ip'} => $_->{'if'} } @$ifref;
    my $unallocated_ips = Cpanel::DIp::IsDedicated::getunallocatedipslist() || [];
    my $used            = 1;
    if ( !$active{$inputip} ) {
        $ethernet_device = '';    # If it's not in ifconfig, then the ethernet device doesn't matter!.
        $used            = 0;
    }
    elsif ( grep /^\Q${inputip}\E$/, @$unallocated_ips ) {
        $used = 0;
    }

    if ( $used && !$force ) {
        return 0, "You cannot remove an allocated IP address ($inputip).";
    }

    my @warnings;
    if ( !$skip_if_shutdown && !$ethernet_device ) {
        $ethernet_device = $active{$inputip};
        if ( !$ethernet_device ) {
            push @warnings, "Skipping shutdown of ethernet device $inputip is bound to. It does not appear to be active.";
            $skip_if_shutdown = 1;
        }
    }

    my ( $remove_etc_ips_ok, $remove_fail_reason ) = remove_from_etc_ips($inputip);
    if ( !$remove_etc_ips_ok ) {
        push @warnings, $remove_fail_reason;
    }

    my ( $remove_cpnat_ok, $remove_cpnat_fail_reason ) = remove_ips_cpnat($inputip);
    if ( !$remove_cpnat_ok ) {
        push @warnings, $remove_cpnat_fail_reason;
    }

    if ($skip_if_shutdown) {
        return 1, "$inputip has been removed.", \@warnings;
    }

    my ( $ethdev, $label ) = split( /:/, $ethernet_device );

    my $ip_prefix;
    foreach my $ip_ref (@$ifref) {
        if ( $ip_ref->{'ip'} eq $inputip ) {
            $ip_prefix = Cpanel::Ips::convert_quad_to_prefix( $ip_ref->{'mask'} );
            last;
        }
    }
    my $is_a_leader_alias_with_dependents = is_a_leader_alias_with_dependents( $inputip, $ifref );

    my $output = system_del_ip( $inputip, $ip_prefix, $ethdev );

    if ($is_a_leader_alias_with_dependents) {
        if ( promote_secondaries_enabled() ) {
            push @warnings, 'promote_secondaries is enabled, skipping ipaliases restart';
        }
        elsif ( !Cpanel::Services::Enabled::is_enabled('ipaliases') ) {
            push @warnings, 'Leader alias removed; remaining aliases in the subnet must be restarted manually.';
        }
        elsif ( Cpanel::Services::Restart::restartservice('ipaliases') ) {
            push @warnings, 'Removal of leader alias forced restart of remaining aliases in the subnet.';
        }
        else {
            push @warnings, 'Failed to restart remaining aliases in the subnet.';
        }
    }

    # We need to clear the cache before calling rebuild, since rebuild may use the cached data.
    Cpanel::IP::Configured::clear_configured_ips_cache();
    Cpanel::IpPool::rebuild();
    return 1, "$ethernet_device is now down, $inputip has been removed", \@warnings;
}

sub _promote_secondaries_file {
    return '/proc/sys/net/ipv4/conf/all/promote_secondaries';
}

sub promote_secondaries_enabled {
    my $secondaries = _promote_secondaries_file();
    if ( !-e $secondaries ) {

        # for systems where the kernel does not support this
        return 0;
    }

    my $promote_secondaries = '';
    open( my $promote_secondaries_fh, '<', $secondaries ) || do {
        Cpanel::Debug::log_warn("Could not open $secondaries for reading");
        return 0;
    };
    read( $promote_secondaries_fh, $promote_secondaries, 1 );
    close($promote_secondaries_fh);

    if ( $promote_secondaries eq '1' ) {
        return 1;
    }
    return 0;
}

__END__
=pod

=head1 AUTHOR

cPanel, L.L.C. - <http://cpanel.net/>

=cut

1;
