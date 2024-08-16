package Whostmgr::NVData;

# cpanel - Whostmgr/NVData.pm                      Copyright 2022 cPanel, L.L.C.
#                                                           All rights reserved.
# copyright@cpanel.net                                         http://cpanel.net
# This code is subject to the cPanel license. Unauthorized copying is prohibited

use strict;
use warnings;

use Whostmgr::ACLS          ();
use Cpanel::CachedDataStore ();
use Cpanel::LoadModule      ();
use Cpanel::Imports;

my $nvdata_base_dir = '/var/cpanel/whm/nvdata';

sub set {
    my ( $key, $value, $stor ) = @_;

    my $safeuser = $ENV{'REMOTE_USER'} || 'root';
    $safeuser =~ s/\///g;
    $stor     =~ s/\///g if ($stor);

    if ( $stor && !Whostmgr::ACLS::hasroot() ) {
        $stor = '';    # case 75113: only root may set stor
    }

    my $nvdatadir = $nvdata_base_dir . ( length $stor ? '/' . $safeuser : '' );
    if ( !-e $nvdatadir ) {
        Cpanel::LoadModule::load_perl_module('Cpanel::SafeDir::MK');
        Cpanel::SafeDir::MK::safemkdir( $nvdatadir, '0700' );
    }
    my $nvfile = $nvdatadir . '/' . ( length $stor ? $stor : $safeuser ) . '.yaml';

    my $nvdata_ref;

    # Usage is safe as we own /var/cpanel and the dir
    $nvdata_ref = Cpanel::CachedDataStore::fetch_ref($nvfile) || {};
    $nvdata_ref->{$key} = $value;

    # Usage is safe as we own /var/cpanel and the dir
    return Cpanel::CachedDataStore::store_ref( $nvfile, $nvdata_ref );
}

sub get_ref {
    my ($stor) = @_;

    my $safeuser = $ENV{'REMOTE_USER'} || 'root';
    $safeuser =~ s/\///g;
    $stor     =~ s/\///g if ($stor);

    if ( $stor && !Whostmgr::ACLS::hasroot() ) {
        $stor = '';    # case 75113: only root may set stor
    }

    my $nvdatadir = $nvdata_base_dir . ( length $stor ? '/' . $safeuser : '' );
    my $nvfile    = $nvdatadir . '/' . ( length $stor ? $stor           : $safeuser ) . '.yaml';
    if ( !-e $nvfile ) { return; }

    # Usage is safe as we own /var/cpanel and the dir
    return ( scalar Cpanel::CachedDataStore::fetch_ref($nvfile) || {} );
}

sub get {
    my ( $key, $stor ) = @_;
    my $ref = get_ref($stor);

    if ($ref) {
        return $ref->{$key};
    }
    else {
        return;
    }
}

sub get_many {
    my ( $keys, $stor ) = @_;
    my $ref = get_ref($stor);

    my %pairs;
    for my $key (@$keys) {
        if ( !$ref ) {
            $pairs{$key} = { value => undef, success => 0, reason => locale()->maketext('The system could not load the [asis,Personalization] datastore.') };
        }
        else {
            # Note: By design, nonexistence of a field is still a success too
            $pairs{$key} = { value => $ref->{$key}, success => 1, reason => 'OK' };
        }
    }

    return \%pairs;
}
1;
