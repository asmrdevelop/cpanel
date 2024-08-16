package Cpanel::Limits;

# cpanel - Cpanel/Limits.pm                        Copyright 2022 cPanel, L.L.C.
#                                                           All rights reserved.
# copyright@cpanel.net                                         http://cpanel.net
# This code is subject to the cPanel license. Unauthorized copying is prohibited

use strict;
use Cpanel::CachedDataStore         ();
use Cpanel::DataStore               ();
use IO::Handle                      ();
use Cpanel::Logger                  ();
use Whostmgr::Limits::PackageLimits ();
use Cpanel::Reseller                ();
use Cpanel::ResellerFunctions       ();
use Cpanel::SimpleSync::CORE        ();

my $logger = Cpanel::Logger->new();

# tested 5/3/10 -jnk
sub backup_reseller_config {
    my ( $reseller, $backupdir ) = @_;
    my $now = time();
    my $reseller_regex;

    # Quoted eval to make perl compiler happy - jnk
    eval ' $reseller_regex = qr/^\Q$reseller\E[\s:]+/; ';

    foreach my $resfile ( 'resellers', 'resellers-nameservers' ) {
        my $backup_file_mtime = ( stat( $backupdir . '/' . $resfile ) )[9];
        my $source_file_mtime = ( stat( '/var/cpanel/' . $resfile ) )[9];

        next if ( $source_file_mtime && $backup_file_mtime && $backup_file_mtime < $now && $source_file_mtime < $now && $backup_file_mtime > $source_file_mtime );    #already up to date
        if ($source_file_mtime) {
            if ( open( my $src_fh, '<', '/var/cpanel/' . $resfile ) && open( my $dest_fh, '>', $backupdir . '/' . $resfile ) ) {
                while ( readline($src_fh) ) {
                    if ( $_ =~ $reseller_regex ) {
                        print {$dest_fh} $_;
                    }
                }
                close($src_fh);
                close($dest_fh);

            }
        }
    }
}

sub backup_reseller_limits {
    my $reseller  = shift;
    my $backupdir = shift;
    return if ( !-d $backupdir );

    # Usage is safe as we own the dir and file
    my $reseller_limits_o = Cpanel::CachedDataStore::loaddatastore('/var/cpanel/reseller-limits.yaml');
    my $reseller_limits   = $reseller_limits_o->{'data'};
    return if ( !$reseller_limits->{$reseller} );

    ## TODO?: would probably be easier to just operate on $reseller_limits->{$reseller}
    foreach my $user ( keys %{$reseller_limits} ) {
        next if ( $user eq $reseller );
        delete $reseller_limits->{$user};
    }
    Cpanel::DataStore::store_ref( $backupdir . '/' . 'my_reseller-limits.yaml', $reseller_limits );

    my $package_limits = Whostmgr::Limits::PackageLimits->load_by_reseller($reseller);
    if ($package_limits) {
        $package_limits->save("$backupdir/my_package-limits.yaml");
    }
}

sub backup_reseller_belongings {
    my ( $reseller, $belonging_type, $backup_dir ) = @_;

    if ( !Cpanel::Reseller::isreseller($reseller) ) {
        return;
    }

    if ( !-d $backup_dir ) {
        $logger->warn("Unable to back up reseller $belonging_type: Back-up dir \"$backup_dir\" does not exist. ");
        return;
    }

    my $items_owned = ();
    if ( $belonging_type eq 'packages' ) {
        $items_owned = Cpanel::ResellerFunctions::getresellerpackages($reseller);
    }
    elsif ( $belonging_type eq 'features' ) {
        $items_owned = Cpanel::ResellerFunctions::getresellerfeatures($reseller);
    }
    else {
        $logger->warn("No backup performed for \"$belonging_type\": Invalid value \"$belonging_type\" specified. (Expecting \"packages\" or \"features\") ");
        return;
    }

    my $now = time();
    my ( $source_file, $backup_file, $source_file_mtime, $backup_file_mtime, $status, $message );

    foreach my $item ( @{$items_owned} ) {

        $source_file = "/var/cpanel/$belonging_type/$item";
        $backup_file = "$backup_dir/$item";

        $source_file_mtime = ( stat($source_file) )[9];
        $backup_file_mtime = ( stat($backup_file) )[9];

        # Skip those that are already up to date
        # (The same set of criteria is used to be consistent with those in backup_reseller_config.)
        next if ( $source_file_mtime
            && $backup_file_mtime
            && $backup_file_mtime > $source_file_mtime
            && $backup_file_mtime < $now
            && $source_file_mtime < $now );

        if ($source_file_mtime) {

            # Create backup file
            ( $status, $message ) = Cpanel::SimpleSync::CORE::syncfile( $source_file, $backup_file );
            if ( $status == 0 ) {
                $logger->warn("No file backup from \"$source_file\" to \"$backup_file\" ($message)");
            }
        }
    }
}

1;
