package Whostmgr::Resellers::Ips;

# cpanel - Whostmgr/Resellers/Ips.pm               Copyright 2022 cPanel, L.L.C.
#                                                           All rights reserved.
# copyright@cpanel.net                                         http://cpanel.net
# This code is subject to the cPanel license. Unauthorized copying is prohibited

use strict;
use warnings;

use Cpanel::ConfigFiles     ();
use Cpanel::DIp::MainIP     ();
use Cpanel::DIp::Update     ();
use Cpanel::Debug           ();
use Cpanel::Ips::Fetch      ();
use Cpanel::Reseller        ();
use Cpanel::Reseller::Cache ();

sub get_reseller_ips {
    my ( $user, $out_ips_array_ref, $out_all_ips_allowed_ref ) = @_;

    # TODO:
    #if ( !length $user ) {
    #    return 0, 'get_reseller_ips requires a user.';
    #}

    $user =~ tr{/}{}d;

    if ( !Cpanel::Reseller::isreseller($user) ) {
        return 0, 'Specified user is not a reseller.';
    }

    my $ips_file = $Cpanel::ConfigFiles::DELEGATED_IPS_DIR . '/' . $user;
    my %ips;

    if ( !-e $Cpanel::ConfigFiles::DELEGATED_IPS_DIR || !-e $ips_file ) {
        my %configured_ips = Cpanel::Ips::Fetch::fetchipslist();
        foreach my $ip ( keys %configured_ips ) {
            $ips{$ip} = 1;
        }
        $$out_all_ips_allowed_ref = 1;
    }
    else {
        if ( open my $DIPS, '<', $ips_file ) {
            while (<$DIPS>) {
                next if ( !m/(\d+\.\d+\.\d+\.\d+)/ );
                $ips{$1} = 1;
            }
            close $DIPS;
        }
        else {
            Cpanel::Debug::log_warn("Unable to read reseller ips from “$ips_file”: $!");
            return 0, 'Failed to read reseller ips.';
        }
    }

    push @$out_ips_array_ref, ( keys %ips );
    return ( 1, 'OK' );
}

sub set_reseller_ips {
    my ( $user, $delegate, @ips ) = @_;

    if ( !length $user ) {
        return 0, 'set_reseller_ips requires a user to set the ips for.';
    }

    $user =~ tr{/}{}d;

    if ( !Cpanel::Reseller::isreseller($user) ) {
        return 0, "The specified user ($user) is not a reseller.";
    }

    my $ips_file = "$Cpanel::ConfigFiles::DELEGATED_IPS_DIR/$user";

    if ( !-d $Cpanel::ConfigFiles::DELEGATED_IPS_DIR ) {
        if ( !mkdir( $Cpanel::ConfigFiles::DELEGATED_IPS_DIR, 0700 ) ) {
            return ( 0, "An error prevented the directory $Cpanel::ConfigFiles::DELEGATED_IPS_DIR from being created: $!\n" );
        }
    }

    if ( !$delegate ) {
        unlink $ips_file;
    }
    elsif ( !_are_available_ips(@ips) ) {
        return 0, 'The list of supplied IP addresses contains inappropriate values.';
    }
    elsif ( open my $DIPS, '>', $ips_file ) {
        foreach my $ip (@ips) {
            print {$DIPS} "$ip\n";
        }
        close $DIPS;
    }
    else {
        return 0, "Failed to open IP address delegation file $ips_file: $!";
    }

    return 1, 'Successfully configured IP addresses delegation to reseller.';
}

sub set_reseller_mainip {
    my $user = shift;
    my $ip   = shift;

    if ( !length $user ) {
        return 0, 'set_reseller_mainip requires a user to set the main ip for.';
    }

    $user =~ tr{/}{}d;

    if ( !Cpanel::Reseller::isreseller($user) ) {
        return 0, 'Specified user is not a reseller.';
    }

    my $mainsrvip   = Cpanel::DIp::MainIP::getmainip();
    my $mainips_dir = $Cpanel::ConfigFiles::MAIN_IPS_DIR;
    my $mainip_file = "$mainips_dir/$user";

    if ( !-e $mainips_dir ) {
        mkdir $mainips_dir, 0755;
    }

    if ( $mainsrvip eq $ip && -e $mainip_file ) {
        unlink $mainip_file;
    }
    elsif ( !_are_available_ips($ip) ) {
        return 0, 'Supplied IP address is invalid.';
    }
    elsif ( open my $MIP, '>', $mainip_file ) {
        print $MIP $ip;
        close $MIP;
    }
    else {
        return 0, "Failed to open main IP address file ($mainip_file): $!";
    }

    Cpanel::Reseller::Cache::reset_cache($user);

    if ( $INC{'Cpanel/DIp/IsDedicated.pm'} ) {
        Cpanel::DIp::IsDedicated::clearcache();
    }

    # It is possible that the IP being assigned to the this reseller could
    # have been moved on top of or moved off of an IP used by another site.
    # In this case, this affects whether that other account has a dedicated
    # IP or not, and the domain ip files need to be updated to reflect that.
    my $err = Cpanel::DIp::Update::update_dedicated_ips_and_dependencies_or_warn();
    if ($err) {
        return 0, $err;
    }

    return 1, 'Successfully set main IP address of the reseller.';
}

sub get_reseller_mainip {
    my $reseller = shift || return;
    $reseller =~ s/\///g;
    my $mainip;

    my $reseller_mainip_file = "$Cpanel::ConfigFiles::MAIN_IPS_DIR/$reseller";

    if ( !-e $reseller_mainip_file ) {
        $mainip = Cpanel::DIp::MainIP::getmainip();
    }
    elsif ( open my $mip_fh, '<', $reseller_mainip_file ) {
        $mainip = <$mip_fh>;
        chomp $mainip;
        $mainip =~ s{(^\s+|\s+$)}{}g;
        close($mip_fh);
    }

    return $mainip;
}

sub _are_available_ips {
    my @ips            = @_;
    my %configured_ips = Cpanel::Ips::Fetch::fetchipslist();

    foreach my $ip (@ips) {
        return if ( !exists $configured_ips{$ip} );
    }

    return 1;
}

1;
