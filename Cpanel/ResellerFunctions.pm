package Cpanel::ResellerFunctions;

# cpanel - Cpanel/ResellerFunctions.pm             Copyright 2022 cPanel, L.L.C.
#                                                           All rights reserved.
# copyright@cpanel.net                                         http://cpanel.net
# This code is subject to the cPanel license. Unauthorized copying is prohibited

use strict;
use Cpanel::ConfigFiles ();
use Cpanel::Reseller    ();
use Cpanel::Debug       ();

#Aliases
our $packagesdir;
our $featuresdir;
our $resellersnameservers;
*featuresdir          = \$Cpanel::ConfigFiles::FEATURES_DIR;
*packagesdir          = \$Cpanel::ConfigFiles::PACKAGES_DIR;
*resellersnameservers = \$Cpanel::ConfigFiles::RESELLERS_NAMESERVERS_FILE;

sub getresellersaclhash { goto &Cpanel::Reseller::getresellersaclhash; }
sub isreseller          { goto &Cpanel::Reseller::isreseller; }

sub getreselleraclhash {
    my $reseller      = shift || return;
    my $resellers_ref = Cpanel::Reseller::getresellersaclhash();
    if ( exists $resellers_ref->{$reseller} ) {
        return wantarray ? keys %{ $resellers_ref->{$reseller} } : [ keys %{ $resellers_ref->{$reseller} } ];
    }
    return;
}

## commenting out unused function definition to avoid warnings
#sub getresellerslist    { goto &Cpanel::Reseller::getresellerslist;    }

sub getresellerslist {
    my $resellers_ref = Cpanel::Reseller::getresellersaclhash();
    my @resellers     = sort keys %{$resellers_ref};
    return wantarray ? @resellers : \@resellers;
}

sub getresellerfeatures {
    my $reseller = shift;
    return if !$reseller;

    my @features;
    if ( opendir my $features_dh, $featuresdir ) {
        while ( my $feature = readdir $features_dh ) {
            next if ( $feature !~ m/^\Q${reseller}\E_/ );
            next if ( !-f $featuresdir . '/' . $feature || -z _ );
            push @features, $feature;
        }
        closedir $features_dh;
    }
    else {
        Cpanel::Debug::log_warn("Unable to open feature directory \"$featuresdir\" ($!) ");
        return;
    }
    return wantarray ? @features : \@features;
}

sub getresellerpackages {
    my $reseller = shift;
    return if !$reseller;

    my @packages;
    if ( opendir my $packages_dh, $packagesdir ) {
        while ( my $package = readdir $packages_dh ) {
            next if ( $package !~ m/^\Q${reseller}\E_/ );
            next if ( !-f $packagesdir . '/' . $package || -z _ );
            push @packages, $package;
        }
        closedir $packages_dh;
    }
    else {
        return;
    }
    return wantarray ? @packages : \@packages;
}

sub _cleanresellers {
    my $resellers_ref = Cpanel::Reseller::getresellersaclhash(1);
    return if !$resellers_ref;
    if ( open my $resellers_fh, '>', $Cpanel::ConfigFiles::RESELLERS_FILE ) {
        foreach my $reseller ( sort keys %{$resellers_ref} ) {
            print {$resellers_fh} $reseller . ':' . join( ',', keys %{ $resellers_ref->{$reseller} } ) . "\n";
        }
        close $resellers_fh;
    }
    else {
        return;
    }
    return $resellers_ref;
}

sub _fixdupes {
    my $file = shift;
    return if ( !$file || !-e $file );
    my %lines;
    if ( open my $file_fh, '<', $file ) {
        while ( my $line = readline $file_fh ) {
            $lines{$line} = 1;
        }
        close $file_fh;
    }
    if ( scalar keys %lines ) {
        if ( open my $file_fh, '>', $file ) {
            foreach my $line ( sort keys %lines ) {
                print {$file_fh} $line;
            }
            close $file_fh;
        }
    }
}

1;
