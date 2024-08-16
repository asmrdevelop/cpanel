package Cpanel::GeoIPfree;

# cpanel - Cpanel/GeoIPfree.pm                     Copyright 2022 cPanel, L.L.C.
#                                                           All rights reserved.
# copyright@cpanel.net                                         http://cpanel.net
# This code is subject to the cPanel license. Unauthorized copying is prohibited

#----------------------------------------------------------------------
# This wrapper class aroung CPAN Geo::IPfree just uses to cPanel's
# own download of the IPv4/country db file. If that file has no size
# (i.e., not there or empty), then warn(), and use Geo::IPfree's default.
#----------------------------------------------------------------------

use strict;

use parent qw(Geo::IPfree);

use Try::Tiny;

use Cpanel::ConfigFiles      ();
use Cpanel::FileUtils::Write ();
use Cpanel::JSON             ();

our $DAT_FILE_PATH        = "$Cpanel::ConfigFiles::CPANEL_ROOT/var/IpToCountry.dat";
our $JSON_INDEX_FILE_PATH = "$Cpanel::ConfigFiles::CPANEL_ROOT/var/IpToCountry.index.json";

sub LoadDB {
    my ( $self, $path ) = @_;

    if ( !-s $DAT_FILE_PATH ) {
        warn __PACKAGE__ . " DB file ($DAT_FILE_PATH) is empty or nonexistent! Falling back to Geo::IPfree default.";
        return $self->SUPER::LoadDB($path);
    }

    my $json_mtime = ( stat($JSON_INDEX_FILE_PATH) )[9];
    my $dat_mtime  = ( stat($DAT_FILE_PATH) )[9];

    if ( $json_mtime && $json_mtime > $dat_mtime ) {
        if ( $self->_load_json_index_cache() ) {
            return $self->{'handler'};
        }
    }

    $self->SUPER::LoadDB($DAT_FILE_PATH);

    if ( $> == 0 ) {
        $self->_save_json_index_cache();
    }

    return $self->{'handler'};
}

sub get_ips_by_country {
    my ($self) = @_;

    my %ranges;
    my $buffer = '';
    seek( $self->{handler}, $self->{start}, 0 );
    my $ip_prev = '255.255.255.255';
    while ( read( $self->{handler}, $buffer, 7 ) ) {
        my $country = substr( $buffer, 0, 2 );
        my $range   = Geo::IPfree::baseX2dec( substr( $buffer, 2 ) );
        my $ip      = Geo::IPfree::nb2ip($range);
        push @{ $ranges{$country} }, "$ip-$ip_prev";
        $ip_prev = Geo::IPfree::nb2ip( $range - 1 );
    }

    return \%ranges;

}

sub _save_json_index_cache {
    my ($self) = @_;
    my $written = 0;

    try {
        my %copy = %$self;
        $copy{'mtime'} = ( stat( $self->{'handler'} ) )[9];
        delete $copy{'handler'};
        Cpanel::FileUtils::Write::overwrite( $JSON_INDEX_FILE_PATH, Cpanel::JSON::Dump( \%copy ), 0644 );
        $written = 1;
    }
    catch {
        warn __PACKAGE__ . " Failed to save json cache ($JSON_INDEX_FILE_PATH): $_";
    };
    return $written;
}

sub _load_json_index_cache {
    my ($self) = @_;
    my $loaded = 0;
    try {
        my $ref = Cpanel::JSON::LoadFile($JSON_INDEX_FILE_PATH);
        if ( $ref->{'dbfile'} eq $DAT_FILE_PATH && $ref->{'mtime'} == ( stat($DAT_FILE_PATH) )[9] ) {
            @$self{ keys %$ref } = values %$ref;
            open( $self->{'handler'}, '<', $self->{'dbfile'} ) || die "Failed to open $DAT_FILE_PATH: $!";
            $loaded = 1;
        }
    }
    catch {
        warn __PACKAGE__ . " Failed to load json cache ($JSON_INDEX_FILE_PATH): $_";
    };

    return $loaded;
}
1;
