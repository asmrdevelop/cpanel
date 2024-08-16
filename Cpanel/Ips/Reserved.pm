package Cpanel::Ips::Reserved;

# cpanel - Cpanel/Ips/Reserved.pm                  Copyright 2022 cPanel, L.L.C.
#                                                           All rights reserved.
# copyright@cpanel.net                                         http://cpanel.net
# This code is subject to the cPanel license. Unauthorized copying is prohibited

=encoding utf-8

=head1 NAME

Cpanel::Ips::Reserved - Utilities for reserving IP addresses

=head1 SYNOPSIS

    use Cpanel::Ips::Reserved ();

    my $reserved_ips_hr = Cpanel::Ips::Reserved::load_reserved_ips();
    my $reserved_apache_ips_hr = Cpanel::Ips::Reserved::load_apache_reserved_ips();

    my $reserved_ip_reasons_hr = Cpanel::Ips::Reserved::load_reserved_ip_reasons();

=head1 DESCRIPTION

This module contains functions for looking up reserved ips.

=cut

use strict;
use warnings;

our $SYSTEM_CONF_DIR = '/etc';

=head2 load_reserved_ips()

Returns a hash (or hashref in scalar context) of
ips addresses that are reserved as the keys.  The
values are always 1

=cut

sub load_reserved_ips {
    return _load_ips_file('reservedips');
}

=head2 load_reserved_ip_reasons()

Returns a hash (or hashref in scalar context) of
ips addresses that are reserved as the keys.  The
values are reasons they are reserved.

=cut

sub load_reserved_ip_reasons {
    my %reasons;
    if ( open my $fh, '<', "$SYSTEM_CONF_DIR/reservedipreasons" ) {
        while ( my $line = readline $fh ) {
            chomp $line;
            next if $line !~ tr{=}{};
            my ( $ip, $reason ) = split /=/, $line;
            $reasons{$ip} = $reason;
        }

        close $fh;
    }

    return wantarray ? %reasons : \%reasons;
}

=head2 load_apache_reserved_ips()

Returns a hash (or hashref in scalar context) of
ips addresses that are reserved in apache as the keys.  The
values are always 1

=cut

sub load_apache_reserved_ips {
    return _load_ips_file('apache_reservedips');
}

sub _load_ips_file {
    my ($file) = @_;
    my %ips;
    if ( open my $ips_fh, '<', "$SYSTEM_CONF_DIR/$file" ) {
        while ( my $line = readline $ips_fh ) {
            chomp $line;
            if ( $line =~ m{\A\d+\.\d+\.\d+\.\d+\z} ) {
                $ips{$line} = 1;
            }
        }
        close $ips_fh;
    }
    return wantarray ? %ips : \%ips;
}

1;
