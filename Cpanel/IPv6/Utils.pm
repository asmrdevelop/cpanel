package Cpanel::IPv6::Utils;

# cpanel - Cpanel/IPv6/Utils.pm                    Copyright 2022 cPanel, L.L.C.
#                                                           All rights reserved.
# copyright@cpanel.net                                         http://cpanel.net
# This code is subject to the cPanel license. Unauthorized copying is prohibited

use strict;
## no critic qw(TestingAndDebugging::RequireUseWarnings)
use File::Path                      ();
use Cpanel::Debug                   ();
use Cpanel::CachedDataStore         ();
use Cpanel::CPAN::Net::IP           ();
use Cpanel::Config::LoadCpUserFile  ();
use Cpanel::Config::LoadWwwAcctConf ();
use Cpanel::LoadModule              ();
use Cpanel::Ips::V6                 ();
use Cpanel::Locale                  ();
use Cpanel::LoadModule              ();
use Cpanel::EtcCpanel               ();
use Cpanel::Linux::RtNetlink        ();
use Cpanel::IPv6::Has               ();
use Cpanel::IPv6::Address           ();
use Cpanel::IPv6::Addrlabel         ();
use Cpanel::IPv6::User              ();
use Cpanel::IPv6::Normalize         ();
use Cpanel::OSSys::Env              ();
use Cpanel::OS                      ();

BEGIN {
    push( @INC, '/usr/local/cpanel' );
}

*get_user_ipv6_address      = *Cpanel::IPv6::User::get_user_ipv6_address;
*extract_ipv6_from_userdata = *Cpanel::IPv6::User::extract_ipv6_from_userdata;
*normalize_ipv6_address     = *Cpanel::IPv6::Normalize::normalize_ipv6_address;

our $base_ipv6_cfg_dir    = $Cpanel::EtcCpanel::ETC_CPANEL_DIR . '/ipv6/';
our $ipv6_readme_file     = $base_ipv6_cfg_dir . 'README.txt';
our $ipv6_config_file     = $base_ipv6_cfg_dir . 'ipv6.conf';
our $range_data_file_path = $base_ipv6_cfg_dir . 'range_allocation_data';
our $named_dir            = Cpanel::OS::dns_named_basedir() . '/';

my $locale;

#
# Test if the system has support for IPv6
#
*system_has_ipv6 = *Cpanel::IPv6::Has::system_has_ipv6;

sub shared_ipv6_key {
    return 'SHARED';
}

sub ips_are_equal {
    my ( $ip1, $ip2 ) = @_;

    $locale ||= Cpanel::Locale->get_handle();

    my $ret;
    if ( !$ip1 || !$ip2 ) {
        return ( 0, $locale->maketext( "Missing IP address value (first value is “[_1]”, second value is “[_2]”).", $ip1, $ip2 ) );
    }
    ( $ret, $ip1 ) = Cpanel::IPv6::Normalize::normalize_ipv6_address($ip1);
    if ( $ret != 1 ) {
        return ( 0, $locale->maketext( "“[_1]” is an invalid IPv6 address.", $ip1 ) );
    }
    ( $ret, $ip2 ) = Cpanel::IPv6::Normalize::normalize_ipv6_address($ip2);
    if ( $ret != 1 ) {
        return ( 0, $locale->maketext( "“[_1]” is an invalid IPv6 address.", $ip2 ) );
    }
    if ( $ip1 eq $ip2 ) {
        return 1;
    }
    else {
        return 0;
    }
}

sub update_named_config {
    my ( $user, $ipv6, $action ) = @_;

    Cpanel::LoadModule::load_perl_module('Cpanel::IPv6::DNSUtil');

    $locale ||= Cpanel::Locale->get_handle();

    if ( $action eq 'enable' ) {
        my ( $ret, $msg ) = Cpanel::IPv6::DNSUtil::enable_ipv6_in_named_conf();
        if ( $ret != 1 ) {
            return ( 0, $locale->maketext( "Could not enable IPv6 support in named.conf: [_1]", $msg ) );
        }
    }

    # get list of user's domains
    my $user_domains = get_user_domains($user);

    # loop through all domains on "user" account
    foreach my $domain ( @{$user_domains} ) {

        # Ensure the zone file exists before trying to operate on it
        next if !-f $named_dir . $domain . '.db';

        if ( $action eq 'enable' ) {
            my ( $ret, $msg ) = Cpanel::IPv6::DNSUtil::add_aaaa_records_to_domain( $user, $domain, $ipv6, 1 );
            if ( $ret != 1 ) {
                return ( 0, $locale->maketext( "The system could not add the [asis,AAAA] record to “[_1]”: [_2]", $domain, $msg ) );
            }
        }
        else {
            my ( $ret, $msg ) = Cpanel::IPv6::DNSUtil::remove_aaaa_records_for_domain( $user, $domain );
            if ( $ret != 1 ) {
                return ( 0, $locale->maketext( "The system could not remove the [asis,AAAA] records from “[_1]”: [_2]", $domain, $msg ) );
            }
        }
    }
    return ( 1, $locale->maketext("All DNS records updated OK") );
}

sub get_user_domains {
    my ($user)    = @_;
    my $cpuser_hr = Cpanel::Config::LoadCpUserFile::load($user);
    my @domains   = ( $cpuser_hr->{'DOMAIN'} );
    push( @domains, @{ $cpuser_hr->{'DOMAINS'} } );
    return \@domains;
}

sub get_bound_ipv6_addresses {
    return Cpanel::Linux::RtNetlink::get_addresses_by_interface('AF_INET6');
}

sub is_ipv6_address_bound {
    my ($address) = @_;

    # Drop any prefix
    $address =~ s/\/\d+//;

    my $ret;
    ( $ret, $address ) = Cpanel::IPv6::Normalize::normalize_ipv6_address($address);
    if ( $ret == 1 ) {

        my $addies = get_bound_ipv6_addresses();
        foreach my $device ( sort { $a cmp $b } keys %{$addies} ) {
            foreach my $id_num ( sort { $a <=> $b } keys %{ $addies->{$device} } ) {

                # print "Checking $address vs $addies->{$device}{$id_num}{'ip'} <br>\n";
                my ( $ret, $normalized_ip ) = Cpanel::IPv6::Normalize::normalize_ipv6_address( $addies->{$device}{$id_num}{'ip'} );
                if ( $ret == 1 ) {
                    if ( $address eq $normalized_ip ) {
                        return 1;
                    }
                }
            }
        }
    }
    return 0;
}

#
# Test if a label already exists for a given ip address
#
sub does_ipv6_address_have_label {
    my ( $address, $bits ) = @_;

    # the ip addrlabel list returns all addresses in short format appended by the prefix
    my $prefix = Cpanel::CPAN::Net::IP::ip_compress_address( $address, 6 ) . "/$bits";
    my ( $success, $address_labels ) = Cpanel::IPv6::Addrlabel::list();
    return ( defined $address_labels->{$prefix} ) ? 1 : 0;
}

sub add_or_delete_ipv6_address {
    my ( $action, $range_name, $range_ref, $address ) = @_;

    $locale ||= Cpanel::Locale->get_handle();
    my $ret;
    if ( $action ne 'add' && $action ne 'delete' ) {
        return ( 0, $locale->maketext("Invalid action called, should be either “add“ or “delete“") );
    }

    # Check for VZ server since we can't bind/unbind IPs from within guest in most cases.
    if ( Cpanel::OSSys::Env::get_envtype() =~ m/virtuozzo/i ) {
        return ( 1, 'OK' );
    }

    # Separate the address from the bits, as Cpanel::CPAN::Net::IP does not accept something like 2620:0:28a0:2004:227:eff:2:f004/64
    my $bits;
    if ( $address =~ m/^(.*)\/(\d+)$/ ) {
        $address = $1;
        $bits    = $2;
    }
    if ( !$bits ) {
        $bits = 128;
    }

    ( $ret, $address ) = Cpanel::IPv6::Normalize::normalize_ipv6_address($address);
    if ( $ret != 1 ) {
        return ( 0, $address );    # $address is our error message
    }

    my $wwwacct_ref = Cpanel::Config::LoadWwwAcctConf::loadwwwacctconf();
    my $ethdev      = $wwwacct_ref->{'ETHDEV'} || 'eth0';

    if ( $action eq 'add' ) {
        if ( is_ipv6_address_bound($address) ) {
            return ( 1, $locale->maketext( "Address “[_1]” is already bound.", $address ) );
        }

        # Test if the ip address + bits combo already has a label

        if ( !does_ipv6_address_have_label( $range_ref->{'first'}, $bits ) ) {

            # Giving the address a high label like 99 will bump it down in
            # priority so it will not be selected as the source address
            my ( $success, $error ) = Cpanel::IPv6::Addrlabel::add( $range_ref->{'first'} . "/$bits", 99 );
            if ( !$success ) {
                return ( 0, $error );
            }
        }

        my ( $success, $error ) = Cpanel::IPv6::Address::add( $address . "/$bits", $ethdev );
        if ( !$success ) {
            return ( 0, $error );
        }

        if ( !is_ipv6_address_bound($address) ) {
            return ( 0, $locale->maketext( "IPv6 address “[_1]” failed to bind to the system.", $address ) );
        }
        return ( 1, $locale->maketext( "IPv6 address “[_1]” bound successfully.", $address ) );
    }
    elsif ( $action eq 'delete' ) {
        if ( !is_ipv6_address_bound($address) ) {
            return ( 1, $locale->maketext( "Address “[_1]” is not bound.", $address ) );
        }

        # Test if the ip address + bits combo already has a label

        my ($exitcode) = system( '/sbin/ip', '-6', 'addr', 'delete', $address . "/$bits", 'dev', $ethdev );
        if ( $exitcode != 0 ) {
            return ( 0, $locale->maketext( "Failed to delete “[_1]” from “[_2]”: [asis,/sbin/ip] exited with status “[_3]”.", $address, $ethdev, $exitcode ) );
        }

        # If we have successfully deleted the address, then delete its label
        if ( does_ipv6_address_have_label( $range_ref->{'first'}, $bits ) ) {

            # verify that we have no more usage in this range, otherwise we leave the label in place #
            my $ip_address = Cpanel::CPAN::Net::IP->new( $range_ref->{'first'} . "/$bits" );

            # overlaps can return undef, so we'll want to check both it being valid and that it doesn't overlap #
            if ( !grep { my $r = $ip_address->overlaps( Cpanel::CPAN::Net::IP->new($_) ); $r && $r != $Cpanel::CPAN::Net::IP::IP_NO_OVERLAP } Cpanel::Ips::V6::fetchipv6list() ) {
                my ( $success, $error ) = Cpanel::IPv6::Addrlabel::remove( $range_ref->{'first'} . "/$bits", 99 );
                if ( !$success ) {
                    return ( 0, $error );
                }
            }
        }
        if ( is_ipv6_address_bound($address) ) {
            return ( 0, $locale->maketext( "Failed to unbind “[_1]”.", $address ) );
        }
        return ( 1, $locale->maketext( "IPv6 address “[_1]” unbound from the system successfully.", $address ) );
    }
}

#
# Assign a range to a user
#
sub set_users_range {
    my ( $user, $range_name ) = @_;

    $locale ||= Cpanel::Locale->get_handle();

    # Get all of our ranges
    my ( $ret, $range_ref ) = load_range_config();
    return ( $ret, $range_ref ) unless $ret;

    my $range = $range_ref->{$range_name};
    return ( 0, $locale->maketext( "Range does not exist: [_1]", $range_name ) ) unless ( ref $range eq 'HASH' );

    # A range must be enabled to receive a user
    return ( 0, $locale->maketext( "Range is not enabled: [_1]", $range_name ) ) unless $range->{'enabled'};

    # push our user into the list while enforcing uniqueness
    # no multiple listings for the user in the array
    my %users = map { $_ => 1 } @{ $range->{'range_users'} };
    $users{$user} = 1;
    $range->{'range_users'} = [ keys %users ];

    return save_range($range_ref);
}

#
# Remove user from a specific range
#
sub remove_user_from_single_range {
    my ( $user, $range_name ) = @_;
    my ( $ret,  $range_ref )  = load_range_config();
    return ( $ret, $range_ref ) unless $ret;
    my @new_users_list;
    foreach my $r_user ( @{ $range_ref->{$range_name}{'range_users'} } ) {
        if ( $r_user ne $user ) { push( @new_users_list, $r_user ); }
    }
    @{ $range_ref->{$range_name}{'range_users'} } = @new_users_list;
    return save_range($range_ref);
}

#
# Remove the user from any/all ranges
#
sub remove_users_range {
    my ($user) = @_;

    # Get all of our ranges
    my ( $ret, $range_ref ) = load_range_config();
    return ( $ret, $range_ref ) unless $ret;

    foreach my $range ( values %{$range_ref} ) {

        # Remove the user from the range users if present
        my %users = map { $_ => 1 } @{ $range->{'range_users'} };
        if ( delete $users{$user} ) {
            $range->{'range_users'} = [ keys %users ];
        }
    }

    return save_range($range_ref);
}

#
# Rename all instances of a user in any/all ranges
#
sub rename_user_in_all_ranges {
    my ( $old_user, $new_user ) = @_;

    my $rename_happened = 0;

    # Get all of our ranges
    my ( $ret, $range_ref ) = load_range_config();
    return ( $ret, $range_ref ) unless $ret;

    foreach my $range ( values %{$range_ref} ) {

        # Remove the user from the range users if present
        my %users = map { $_ => 1 } @{ $range->{'range_users'} };
        if ( delete $users{$old_user} ) {
            $rename_happened        = 1;
            $users{$new_user}       = 1;
            $range->{'range_users'} = [ keys %users ];
        }
    }

    # Only touch the file if the user was actually in an IPv6 range
    if ($rename_happened) {
        return save_range($range_ref);
    }
    else {
        return ( 1, $locale->maketext('OK') );
    }
}

#
# Detect if a range exists
#
sub validate_range_name {
    my ($range) = @_;

    my ( $ret, $range_ref ) = load_range_config();
    return 0 unless $ret;
    return 0 unless ( ref $range_ref eq 'HASH' );
    return 0 unless ( ref $range_ref->{$range} eq 'HASH' );
    return 1;
}

# We get the IP and remove it from the available IPs, either reclaimed or increment the most recently used counter
sub get_next_available_ipv6_from_range {
    my ( $range_name, $range_config ) = @_;

    # sanity checks #
    return ( 0, 0, $locale->maketext("No range name supplied") ) unless $range_name;

    my $range_ref = $range_config->{$range_name};
    return ( 0, 0, $locale->maketext( "Invalid range name: [_1]", $range_name ), undef )
      if !$range_ref || ref $range_ref ne ref {};

    my $ret;
    $locale ||= Cpanel::Locale->get_handle();

    # If we have a most recent IP set, use that
    my $start;
    my $first = 0;
    if ( $range_ref->{'mostrecent'} ) {
        $start = $range_ref->{'mostrecent'};

        # Otherwise, this might be the first time, so let's start at the top
    }
    elsif ( $range_ref->{'first'} ) {
        $start = $range_ref->{'first'};
        $first = 1;

        # Or maybe the config was bad and we don't really have anything useful
    }
    else {
        return ( 0, 0, $locale->maketext( "The system could not determine the most recent address for “[_1]”.", $range_name ), undef );
    }

    # Used for comparison to the disabled ranges
    my $ip_range = Cpanel::CPAN::Net::IP->new( $range_ref->{'first'} . ' - ' . $range_ref->{'last'} );

    # Find all the disabled ranges that overlap this range
    # Get the disabled ranges, create net::ip ranges out of them,
    # filter out all the invalid ranges, and find only the ones that overlap
    my @disabled_ranges =
      grep { $ip_range->overlaps($_) }
      grep { $_ }
      map  { Cpanel::CPAN::Net::IP->new( $_->{'first'} . ' - ' . $_->{'last'} ) }
      grep { !$_->{'enabled'} } values %{$range_config};

    # Don't allocate the shared IP, if set.
    my $shared_range = $range_config->{ Cpanel::IPv6::Utils::shared_ipv6_key() };
    push @disabled_ranges, Cpanel::CPAN::Net::IP->new( $shared_range->{'first'} ) if $shared_range;

    # If we have reclaimed IPs available, use it first; no need to increment
    if ( exists $range_ref->{'reclaimed'} and ref $range_ref->{'reclaimed'} eq 'ARRAY' ) {

        my $reclaimed_ip = _find_non_reserved_ip_in_reclaimed( $range_ref->{'reclaimed'}, \@disabled_ranges );
        if ( defined $reclaimed_ip ) {

            # Remove reclaimed IP from list and carry on
            ( $ret, my $msg ) = remove_ip_from_reclaimed_list( $reclaimed_ip, $range_name );
            if ( !$ret ) {
                return ( 0, 0, $msg, undef );
            }
            else {
                return ( 1, 1, $reclaimed_ip, $ip_range->prefixlen() );
            }
        }
    }

    # Start with the next ip after the previously used ip
    # If this is the first IP used in the range, we are starting there and not incrementing 'mostrecent'
    my $next_ip;
    if ($first) {
        $next_ip = Cpanel::CPAN::Net::IP->new($start);
    }
    else {
        $next_ip = _increment_ipv6( Cpanel::CPAN::Net::IP->new($start) );
    }

    # Keep looping as long as we are in our ip range
    while ( $ip_range->overlaps($next_ip) ) {

        # See if it is in a disabled range
        my @overlapped_ranges = grep { $_->overlaps($next_ip) } @disabled_ranges;

        # If we did not step into a disabled range, then we're good
        return ( 1, 0, $next_ip->ip(), $ip_range->prefixlen() ) unless @overlapped_ranges;

        # If we stepped in one, got to the end of that range, plus one
        $next_ip = _increment_ipv6( Cpanel::CPAN::Net::IP->new( $overlapped_ranges[0]->last_ip() ) );

    }
    return ( 0, 0, $locale->maketext( "There are no more available IP addresses in the range: [_1]", $range_name ), undef );

}

sub _find_non_reserved_ip_in_reclaimed {
    my ( $reclaimed_ref, $disabled_ranges_ref ) = @_;

    # Loop through all the IP's in the reclaimed array & find one that is not in a forbidden range
    # A forbidden range could have been added after after an IP was used & later unassigned
    # (Like if they later decided that they didn't want certian IP's to be used.)
    for my $reclaimed_ip (@$reclaimed_ref) {

        # Skip it if we are in a disabled range
        my $ip_obj = Cpanel::CPAN::Net::IP->new($reclaimed_ip);
        next if scalar grep { $_->overlaps($ip_obj) } @$disabled_ranges_ref;

        return $reclaimed_ip;
    }
    return;
}

# input: IPv6 address
# output: 0|1, array ref of ranges that IP was found in

sub get_ranges_by_ip {
    my ($ip) = @_;
    my @ranges;

    $locale ||= Cpanel::Locale->get_handle();

    my $ip_obj = Cpanel::CPAN::Net::IP->new( $ip, 6 ) || return ( 0, $locale->maketext("Invalid IP address") );

    my ( $ret, $range_config ) = load_range_config();

    foreach my $range_name ( keys %{$range_config} ) {
        my $first        = $range_config->{$range_name}{'first'};
        my $last         = $range_config->{$range_name}{'last'};
        my $range_string = "$first - $last";
        my $ip_range     = Cpanel::CPAN::Net::IP->new( $range_string, 6 );

        if ( $ip_range and $ip_range->prefixlen() ) {
            $range_config->{$range_name}{'CIDR'} = $ip_range->short() . '/' . $ip_range->prefixlen();

            if ( my $range_obj = Cpanel::CPAN::Net::IP->new( $range_config->{$range_name}{'CIDR'} ) ) {
                my $overlap_result = $range_obj->overlaps($ip_obj);
                if ($overlap_result) {
                    push( @ranges, $range_name );
                }
            }
        }
    }
    return ( 1, \@ranges );
}

sub add_ip_to_reclaimed_list {
    my ( $ip, $range_name ) = @_;

    $locale ||= Cpanel::Locale->get_handle();

    my ( $ret, $range_config ) = load_range_config();
    if ( !$range_config->{$range_name} ) { return ( 0, $locale->maketext( "Invalid range: [_1]", $range_name ) ); }

    # Check to be sure the IP we want to reclaim is really within the range given
    my $ip_obj = Cpanel::CPAN::Net::IP->new( $ip, 6 ) || return ( 0, $locale->maketext("Invalid IP address") );

    my $range_string = "$range_config->{$range_name}{'first'} - $range_config->{$range_name}{'last'}";
    my $ip_range     = Cpanel::CPAN::Net::IP->new( $range_string, 6 );
    if ( $ip_range and $ip_range->prefixlen() ) {
        my $ip_range_with_prefix = $ip_range->short() . '/' . $ip_range->prefixlen();
        if ( my $range_obj = Cpanel::CPAN::Net::IP->new($ip_range_with_prefix) ) {
            my $overlap_result = $range_obj->overlaps($ip_obj);
            if ($overlap_result) {
                push( @{ $range_config->{$range_name}{'reclaimed'} }, $ip );
                ( $ret, my $msg ) = save_range($range_config);
                return ( $ret, $msg );
            }
        }
    }

    return ( 0, $locale->maketext( "Invalid IP address for range: “[_1]” is not in range “[_2]”.", $ip, $range_name ) );
}

sub remove_ip_from_reclaimed_list {
    my ( $ip, $range_name ) = @_;
    $locale ||= Cpanel::Locale->get_handle();
    if ( !$ip ) { return ( 0, $locale->maketext("No IP given") ); }
    my ( $ret, $range_config ) = load_range_config();
    if ( !$range_config->{$range_name} ) { return ( 0, $locale->maketext( "Invalid range: [_1]", $range_name ) ); }

    my $removed = 0;

    # build reclaimed_list but leave out the one we are reclaiming to remove it
    my @new_reclaimed_list;
    foreach my $reclaimed_ip ( @{ $range_config->{$range_name}{'reclaimed'} } ) {
        if ( $reclaimed_ip eq $ip ) {
            $removed = 1;
            next;
        }
        else {
            push( @new_reclaimed_list, $reclaimed_ip );
        }
    }
    if ( !$removed ) {
        return ( 0, $locale->maketext( "Could not find the given address in the reclaimed pool for “[_1]”.", $range_name ) );
    }

    $range_config->{$range_name}{'reclaimed'} = \@new_reclaimed_list;
    ( $ret, my $msg ) = save_range($range_config);
    return ( $ret, $msg );
}

# Get list of rangess by username
sub get_ranges_by_user {
    my ($user) = @_;
    $locale ||= Cpanel::Locale->get_handle();
    my ( $ret, $ip ) = get_user_ipv6_address($user);
    return ( $ret, $locale->maketext( "The system could not determine the IPv6 address by username: [_1]", $ip ) ) if !$ret;
    ( $ret, my $range_ref ) = get_ranges_by_ip($ip);
    return ( $ret, $range_ref );
}

sub get_range_for_user_from_range_config {
    my ($user) = @_;

    $locale ||= Cpanel::Locale->get_handle();

    my ( $ret, $range_config ) = load_range_config();

    if ( !$ret ) {
        return ( $ret, $range_config );
    }

    foreach my $range_name ( keys %{$range_config} ) {
        if ( grep ( /^${user}$/, @{ $range_config->{$range_name}{'range_users'} } ) ) {
            return ( 1, $range_name );
        }
    }
    return ( 0, $locale->maketext("The system could not find a range with the user in it.") );

}

# Takes the name of a range as an argument, returns hash ref of range data if found
sub get_range_data {
    my ($range_name) = @_;

    $locale ||= Cpanel::Locale->get_handle();

    if ( !$range_name ) {
        return ( 0, $locale->maketext("Invalid range name argument.") );
    }

    my ( $ret, $range_config ) = load_range_config();

    if ( !$ret ) {
        return ( $ret, $range_config );
    }

    if ( exists( $range_config->{$range_name} ) ) {
        return ( 1, $range_config->{$range_name} );
    }
    else {
        return ( 0, $locale->maketext('No such range found') );
    }
}

#
# Increment an ipv6 address
#
sub _increment_ipv6 {
    my ($ip) = @_;

    return $ip->binadd( Cpanel::CPAN::Net::IP->new('::1') );
}

# save_range works as a way to add or overwrite (edit without deletion) range data
sub save_range {
    my ($range_ref) = @_;

    $locale ||= Cpanel::Locale->get_handle();

    # Ensure that our ip config directory exists
    my ( $ret, $msg ) = _validate_ipv6_dir();
    return ( $ret, $msg ) unless $ret;

    my $existing_range_ref;

    # Load current config and substitute old values with any new ones
    # But only do this if there is an existing range data file
    if ( -f $range_data_file_path ) {
        ( my $ret, $existing_range_ref ) = load_range_config();
        return ( $ret, $existing_range_ref ) unless $ret;
    }

    # Merge any new data into the existing records
    foreach my $range_name ( keys %{$range_ref} ) {
        foreach my $key ( keys %{ $range_ref->{$range_name} } ) {
            if ( $key eq 'range_users' ) {
                delete $existing_range_ref->{$range_name}{'range_users'} if exists( $range_ref->{$range_name}{'range_users'} );
                foreach my $range_user ( @{ $range_ref->{$range_name}{'range_users'} } ) {
                    $range_user =~ s/\s+//g;
                    push( @{ $existing_range_ref->{$range_name}{'range_users'} }, $range_user );
                }
            }
            else {
                $existing_range_ref->{$range_name}{$key} = $range_ref->{$range_name}{$key};
            }
        }

        # If we've gone through all of the range_name keys and still don't have range_users, add a placeholder
        if ( !$existing_range_ref->{$range_name}{'range_users'} ) {
            $existing_range_ref->{$range_name}{'range_users'} = [];
        }
    }

    # Save our new range config
    if ( Cpanel::CachedDataStore::store_ref( $range_data_file_path, $existing_range_ref ) ) {
        return ( 1, $locale->maketext('Range saved') );
    }
    else {
        return ( 0, $locale->maketext( "Could not write to “[_1]” : [_2]", $range_data_file_path, $! ) );
    }
}

sub load_range_config {
    my ( $ret, $msg ) = _validate_ipv6_dir();
    return ( $ret, $msg ) unless $ret;

    # get shared IPv6 address and its CIDR #
    my $wwwacct_ref = Cpanel::Config::LoadWwwAcctConf::loadwwwacctconf();
    my ( $shared_ipv6, $shared_ipv6_cidr );
    if ( $wwwacct_ref->{'ADDR6'} ) {
        $locale ||= Cpanel::Locale->get_handle();
        die $locale->maketext( "The system’s shared IPv6 address is not in the correct format: [_1].", $wwwacct_ref->{'ADDR6'} )
          if !Cpanel::Ips::V6::validate_ipv6( $wwwacct_ref->{'ADDR6'} );
        $shared_ipv6      = $wwwacct_ref->{'ADDR6'};
        $shared_ipv6_cidr = 128;                       # The shared IPv6 address is always a single address, and thus the range is always /128.
    }

    my $shared_ipv6_key  = shared_ipv6_key();
    my $shared_structure = sub {
        return {
            'owner'       => 'root',
            'name'        => $shared_ipv6_key,
            'first'       => $shared_ipv6,
            'last'        => $shared_ipv6,
            'CIDR'        => "$shared_ipv6/$shared_ipv6_cidr",
            'range_users' => [],
            'mostrecent'  => undef,
            'note'        => undef,
            'enabled'     => 1
        };
    };

    if ( !-f $range_data_file_path ) {
        return ( 1, { $shared_ipv6_key => &{$shared_structure}() } ) if $shared_ipv6;
        return ( 1, {} );
    }

    my $range_data_ref = Cpanel::CachedDataStore::load_ref( $range_data_file_path, undef );
    if ($range_data_ref) {
        Cpanel::LoadModule::load_perl_module('Clone');

        # Make a deep copy to prevent hashed references in $range_data_ref from pointing to the same memory location as other instances of it
        my $ranges = Clone::clone($range_data_ref);
        if ($shared_ipv6) {
            $ranges->{$shared_ipv6_key} ||= &{$shared_structure}();

            # always make sure the IP is up to date #
            $ranges->{$shared_ipv6_key}->{'first'} = $shared_ipv6;
            $ranges->{$shared_ipv6_key}->{'last'}  = $shared_ipv6;
            $ranges->{$shared_ipv6_key}->{'CIDR'}  = "$shared_ipv6/$shared_ipv6_cidr";
        }
        else {

            # the shared IPv6 address info will be saved in the datastore, we need to remove it #
            delete $ranges->{$shared_ipv6_key} if $ranges->{$shared_ipv6_key} && !@{ $ranges->{$shared_ipv6_key}->{'range_users'} };
        }
        return ( 1, $ranges );
    }
    else {
        # If there is a file but it's not loading, assume it's got bad data in it and rename it out of the way so we can move on
        my $rename_range_data_file_to = $range_data_file_path . '-' . time . '-' . int( rand(10000000) ) . '.cpbackup';
        Cpanel::Debug::log_warn("The system failed to read a valid value the from IPv6 range file, $range_data_file_path. The system will rename the file to '$rename_range_data_file_to' and continue with no IPv6 range data.");
        rename( $range_data_file_path, $rename_range_data_file_to )
          or die Cpanel::Debug::log_die("The system failed to rename the invalid '$range_data_file_path' IPv6 range file to '$rename_range_data_file_to': $!");
        return ( 1, { $shared_ipv6_key => &{$shared_structure}() } ) if $shared_ipv6;
        return ( 1, {} );
    }
}

#
# Verify that the ipv6 directory exists & create it if need be
#
sub _validate_ipv6_dir {

    $locale ||= Cpanel::Locale->get_handle();

    # Create /etc/cpanel first it doesn't exist. Using a separate function to create this directory
    # since it's being modified (created, edited) by other features as well (i.e. EA4).
    my ( $ret, $reason ) = Cpanel::EtcCpanel::make_etc_cpanel_dir();
    unless ($ret) {
        return ( 0, $locale->maketext( "Could not create “[_1]”: [_2]", $Cpanel::EtcCpanel::ETC_CPANEL_DIR, $reason ) );
    }

    # If the base directory for IPv6 does not exist, create it
    if ( !-d $base_ipv6_cfg_dir ) {

        # Recursively create our path
        File::Path::make_path($base_ipv6_cfg_dir);

        # make_path has a flaky way to get the error, testing again for the
        # directories is the true test
        return ( 0, $locale->maketext( "Could not create “[_1]”", $base_ipv6_cfg_dir ) ) unless -d $base_ipv6_cfg_dir;
    }

    # The directory should now exist, now ensure that the readme exists
    return _create_readme_file();
}

#
# Create a readme file in our ipv6 directory if it does not already exist
#
sub _create_readme_file {

    $locale ||= Cpanel::Locale->get_handle();

    # If the file exists already, nothing to do
    return ( 1, $locale->maketext('OK') ) if -f $ipv6_readme_file;

    # Readme file content
    my $content = <<README;
The files in this directory may change drastically to better fit goals of the feature.

    *  Do not modify these files in any way.
    *  Additionally, do not write any code or scripts that depend on the contents of these files.
README

    open my $fh, '>', $ipv6_readme_file or return ( 0, $locale->maketext( "The system was unable to create “[_1]”.", $ipv6_readme_file ) );
    print {$fh} $content;
    close $fh;

    return ( 1, $locale->maketext('OK') );
}

# Determine if a range overlaps an existing enabled range.
# If $options->{'smallest'} is set, only considers the smallest enclosing range.
# Return the overlapped range if it does and undef otherwise.
sub range_overlaps_existing {
    my ( $ip_range, $include_shared, $range_ref, $options ) = @_;
    $range_ref //= load_range_config();
    $options   //= {};

    my $smallest = {
        len => 0,
    };
    foreach my $range ( keys %{$range_ref} ) {
        my $name = $range_ref->{$range}{'name'} // '';
        next if !$include_shared && $name eq shared_ipv6_key();

        my $exist_range = Cpanel::CPAN::Net::IP->new( $range_ref->{$range}{'first'} . ' - ' . $range_ref->{$range}{'last'} );
        if ( $ip_range->overlaps($exist_range) ) {
            if ( $options->{'smallest'} && $exist_range->prefixlen > $smallest->{len} ) {
                $smallest = {
                    len     => $exist_range->prefixlen,
                    range   => $range,
                    enabled => $range_ref->{$range}{'enabled'},
                };
            }
            elsif ( !$options->{'smallest'} && $range_ref->{$range}{'enabled'} ) {
                return $range;
            }
        }
    }
    return $smallest->{'range'} if $smallest->{'enabled'};
    return;
}

1;
