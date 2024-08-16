package Cpanel::DIp::Group;

# cpanel - Cpanel/DIp/Group.pm                     Copyright 2022 cPanel, L.L.C.
#                                                           All rights reserved.
# copyright@cpanel.net                                         http://cpanel.net
# This code is subject to the cPanel license. Unauthorized copying is prohibited

use strict;
use warnings;

use Cpanel::ConfigFiles      ();
use Cpanel::DIp::MainIP      ();
use Cpanel::DIp::IsDedicated ();
use Cpanel::ConfigFiles      ();

=encoding utf-8

=head1 NAME

Cpanel::DIp::Group - Fetching IP Assignments for groups of IPs

=head1 SYNOPSIS

    use Cpanel::DIp::Group;

    my $available_ips = Cpanel::DIp::Group::get_available_ips($reseller);

    my $delegated_ips = Cpanel::DIp::Group::getdelegatedipslist($reseller);

    my $reserved_ips = Cpanel::DIp::Group::getreservedipslist();

=head2 get_available_ips($reseller)

Returns a list of available IPs for a given reseller or root

=over 2

=item Input

=over 3

=item $reseller C<SCALAR>

    The reseller to get the available IPs for.

=back

=item Output

=over 3

Returns a list of available IPs.  When called
in scalar context it returns an array ref, when called
in array context it returns an array.

=back

=back

=cut

sub get_available_ips {
    my $reseller = shift || $ENV{'REMOTE_USER'} || 'root';
    my $iphash   = _get_resellersips_hash($reseller);

    my @iplist = grep { $iphash->{$_}->{'free'} } keys %{$iphash};

    return wantarray ? @iplist : \@iplist;
}

# $Cpanel::ConfigFiles::DELEGATED_IPS_DIR/$reseller

=head2 getdelegatedipslist($reseller)

Returns a list of delegated IPs for a given reseller or root

=over 2

=item Input

=over 3

=item $reseller C<SCALAR>

    The reseller to get the delegated IPs for.

=back

=item Output

=over 3

Returns a list of delegated IPs.  When called
in scalar context it returns an array ref, when called
in array context it returns an array.

=back

=back

=cut

sub getdelegatedipslist {
    my $reseller         = shift || return;
    my $delegatedipsfile = "$Cpanel::ConfigFiles::DELEGATED_IPS_DIR/$reseller";
    my $delegatedips     = Cpanel::DIp::IsDedicated::getipsfromfilelist($delegatedipsfile);
    return if !$delegatedips;
    return wantarray ? @{$delegatedips} : $delegatedips;
}

=head2 getdelegatedipslist()

Returns a list of reserved IPs for the server

=over 2

=item Input

None

=item Output

=over 3

Returns a list of reserved IPs.  When called
in scalar context it returns an array ref, when called
in array context it returns an array.

=back

=back

=cut

sub getreservedipslist {
    my $reservedips = Cpanel::DIp::IsDedicated::getipsfromfilelist($Cpanel::ConfigFiles::RESERVED_IPS_FILE);
    return if !$reservedips;
    return wantarray ? @{$reservedips} : $reservedips;
}

# Currently called from Cpanel::DIp for legacy reasons
sub _get_resellersips_hash {
    my $reseller = shift || return;
    my %resellerips;
    my $delegated = getdelegatedipslist($reseller);
    my $shared    = Cpanel::DIp::IsDedicated::getsharedipslist($reseller);

    #my $reserved  = getreservedipslist($reseller); -- reserved ips are already not built into the ip pool
    my $unused = Cpanel::DIp::IsDedicated::getunallocatedipslist();
    my $mainip = Cpanel::DIp::MainIP::getmainip();

    if ( defined $delegated ) {

        # Using delegated IPs
        if ( defined $unused ) {
            my %unused_lookup = map { $_ => 1 } @{$unused};

            foreach my $ip ( @{$delegated} ) {
                $resellerips{$ip}{'delegated'}{$reseller} = 1;
                $resellerips{$ip}{'free'} = $unused_lookup{$ip} || 0;
            }
        }
        else {
            foreach my $ip ( @{$delegated} ) {
                $resellerips{$ip}{'delegated'}{$reseller} = 1;
                $resellerips{$ip}{'free'} = 0;
            }
        }
    }
    else {

        # Not using delegated, so add main shared IP to shared
        $resellerips{$mainip}{'shared'}{'_main'} = 1;

        # Using all available IPs
        if ( defined $unused ) {
            foreach my $ip ( @{$unused} ) {
                $resellerips{$ip}{'free'} = 1;
            }
        }
    }

    if ( defined $shared ) {

        # Shared IPs configured
        foreach my $ip ( @{$shared} ) {
            if ( $ip eq $mainip ) {
                $resellerips{$ip}{'shared'}{'_main'} = 1;
            }
            $resellerips{$ip}{'shared'}{$reseller} = 1;
            $resellerips{$ip}{'free'} = 0;
        }
    }
    else {
        $resellerips{$mainip}{'shared'}{'_main'} = 1;
        $resellerips{$mainip}{'free'} = 0;
    }

    return wantarray ? %resellerips : \%resellerips;
}

1;
