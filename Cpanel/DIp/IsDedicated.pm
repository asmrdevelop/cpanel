package Cpanel::DIp::IsDedicated;

# cpanel - Cpanel/DIp/IsDedicated.pm               Copyright 2022 cPanel, L.L.C.
#                                                           All rights reserved.
# copyright@cpanel.net                                         http://cpanel.net
# This code is subject to the cPanel license. Unauthorized copying is prohibited

use strict;
use warnings;

use Cpanel::ConfigFiles ();
use Cpanel::LoadFile    ();
use Cpanel::DIp::MainIP ();
use Cpanel::NAT         ();
use Cpanel::Reseller    ();

our $VERSION = 2.0;

my ( %RESELLERS_WITH_MAINIPS, %SHAREDIPSCACHE, %DEDICATEDIPCACHE );

=encoding utf-8

=head1 NAME

Cpanel::DIp::IsDedicated

=head1 SYNOPSIS

  use Cpanel::DIp::IsDedicated ();
  my $is_dedicated_ip = Cpanel::DIp::IsDedicated::isdedicatedip($ip_address);

=head1 DESCRIPTION

This module contains methods to tell if a specific IP address is dedicated and to list shared and IPs in a file.
A dedicated IP address is one that has been assigned to a specific cPanel user for their use. It differs from a shared IP address,
as the IP is expected to be used privately by that user. An IP that is not dedicated is assumed to be shared.

=head1 FUNCTIONS

=head2 isdedicatedip( $ip, $nowarn (optional) )

This function takes an IP address on the system and returns whether or not that IP address is dedicated to a cPanel user.

=head3 Arguments

=over 4

=item $ip    - SCALAR - The IP address in question to check if it is a dedicated IP or not

=item $nowarn    - SCALAR (OPTIONAL) - An optional boolean value indicating if the function should warn if an undef or empty IP address is specified.

=back

=head3 Returns

This function returns 1 or 0. A return of 1 indicates that the IP address specified is dedicated. A return of 0 indicates
that the function either failed or the IP isn't dedicated. An IP that is not dedicated is assumed to be shared.

=head3 Exceptions

None.

=cut

sub isdedicatedip {
    my $ip     = shift || '';
    my $nowarn = shift;
    if ($Cpanel::rootlogin) { return 0; }
    if ( !$ip && !$nowarn ) {
        require Carp;
        Carp::cluck('isdedicatedip() requires one argument (this probably means a domain is missing from httpd.conf)');
        return 0;
    }

    return $DEDICATEDIPCACHE{$ip} if exists $DEDICATEDIPCACHE{$ip};

    if ( !scalar keys %DEDICATEDIPCACHE ) {

        # when the mainip cache is purged the dedicated ip cache is also purged
        # cache the mainip at the first call
        my $mainip = Cpanel::DIp::MainIP::getmainip();
        $DEDICATEDIPCACHE{$mainip} = 0;

        # If our main IP mapped to a public IP via NAT then at ip is also not dedicated
        my $nat_public_ip = Cpanel::NAT::get_public_ip($mainip);
        $DEDICATEDIPCACHE{$nat_public_ip} = 0;

        return $DEDICATEDIPCACHE{$ip} if ( $ip eq $mainip or $ip eq $nat_public_ip );
    }

    if ( !scalar keys %RESELLERS_WITH_MAINIPS && opendir( my $dir_fh, $Cpanel::ConfigFiles::MAIN_IPS_DIR ) ) {
        %RESELLERS_WITH_MAINIPS = map { $_ => undef } grep( !m{^\.}, readdir($dir_fh) );
        closedir($dir_fh);

        # note that when the reseller cache is purged, the dedicatedip cache is also purged
        #	an alternate option, could be to cache the list of reseller already tested, but this will not avoid
        #	a call to getresellerslist, which is time consuming ( even when cached )
        foreach my $reseller ( Cpanel::Reseller::getresellerslist(), 'root' ) {
            my $ips_ref = getsharedipslist( $reseller, \%RESELLERS_WITH_MAINIPS );
            next if ref $ips_ref ne 'ARRAY';
            foreach my $sharedip (@$ips_ref) {
                $DEDICATEDIPCACHE{$sharedip} = 0;
                $DEDICATEDIPCACHE{ Cpanel::NAT::get_public_ip($sharedip) } = 0;
            }
        }
        return $DEDICATEDIPCACHE{$ip} if exists $DEDICATEDIPCACHE{$ip};
    }

    return ( $DEDICATEDIPCACHE{$ip} = 1 );
}

=head2 getsharedipslist( $reseller, $reseller_with_sharedips_hashref (optional) )

This function takes a reseller name and returns the shared IP addresses associated with that reseller.
The shared IP addresses are loaded from the reseller's $Cpanel::ConfigFiles::MAIN_IPS_DIR/$reseller file.

=head3 Arguments

=over 4

=item $reseller    - SCALAR - The name of the reseller to get the shared IP addresses for.

=item $reseller_with_sharedips_hashref    - HASHREF (optional) - An optional parameter that is used internally to allow the function to use the cache or not.

=back

=head3 Returns

This function returns either a list or arrayref of shared IP addresses associated with the specified reseller.

=head3 Exceptions

None.

=cut

sub getsharedipslist {
    my $reseller                        = shift || return;
    my $reseller_with_sharedips_hashref = shift;
    my $sharedips;

    #if we provided a hashref and it *doesn't* have the reseller, then we know there's no file
    my $mtime;
    if ( !$reseller_with_sharedips_hashref || exists $reseller_with_sharedips_hashref->{$reseller} ) {
        my $mainipsfile = "$Cpanel::ConfigFiles::MAIN_IPS_DIR/$reseller";
        $mtime = ( stat($mainipsfile) )[9];
        if ($mtime) {
            if ( exists $SHAREDIPSCACHE{$reseller} && $SHAREDIPSCACHE{$reseller}->{'mtime'} && $SHAREDIPSCACHE{$reseller}->{'mtime'} == $mtime ) {
                return wantarray ? @{ $SHAREDIPSCACHE{$reseller}->{'data'} } : $SHAREDIPSCACHE{$reseller}->{'data'};
            }
            $sharedips = getipsfromfilelist( $mainipsfile, 1 );    #skip exists check
        }
    }
    else {
        $Cpanel::Debug::level > 3 && print STDERR "DIp::getsharedipslist skipping $reseller as do not have a main ips file\n";
    }
    if ( !$sharedips || ref $sharedips ne 'ARRAY' ) {
        $sharedips = [ Cpanel::DIp::MainIP::getmainip() ];
    }
    $SHAREDIPSCACHE{$reseller} = { 'data' => $sharedips, 'mtime' => $mtime };
    return wantarray ? @{$sharedips} : $sharedips;
}

=head2 getipsfromfilelist( $file, $skip_exists_check (optional) )

This function returns a list or arrayref of IP addresses (IPv4 and IPv6) stored in a file.

=head3 Arguments

=over 4

=item $file    - SCALAR - The file path of the file to open and read IP addresses from.

=item $skip_exists_check    - SCALAR (optional) - An optional scalar boolean value that indicates if the passed in file should be checked for existence before loading.

=back

=head3 Returns

This function returns a list or arrayref (depending on calling context) of IP addresses contained in the specified file.

=head3 Exceptions

Anything Cpanel::LoadModule or Cpanel::LoadFile can throw.

=cut

sub getipsfromfilelist {
    my $file              = shift || return;
    my $skip_exists_check = shift;
    if ( !$skip_exists_check ) { return if ( !-e $file ); }
    my %ips;
    foreach my $line ( split( m{\n}, Cpanel::LoadFile::load($file) ) ) {
        if ( $line =~ m{ \A \s* (\d+ [.] \d+ [.] \d+ [.] \d+) \s* \z }xms ) {
            $ips{$1} = 0;
        }
        elsif ( $line =~ m{ \A \s* (\[ [\:\.\da-fA-F]+ \]) \s* \z }xms ) {
            ## IPv6 address, including surrounding brackets
            $ips{$1} = 0;
        }
    }
    my @ips = keys %ips;
    return wantarray ? @ips : \@ips;
}

=head2 getunallocatedipslist()

This function returns a list or IP addresses that have not be allocated as dedicated ips.

In scalar context it returns an arrayref of the list.

=cut

sub getunallocatedipslist {
    my $ips = getipsfromfilelist($Cpanel::ConfigFiles::IP_ADDRESS_POOL_FILE) or return;
    return if !$ips;
    return wantarray ? @{$ips} : $ips;
}

sub clearcache {
    %RESELLERS_WITH_MAINIPS = %SHAREDIPSCACHE = %DEDICATEDIPCACHE = ();
    return;
}

1;
