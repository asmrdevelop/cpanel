package Cpanel::ClamScan;

# cpanel - Cpanel/ClamScan.pm                      Copyright 2022 cPanel, L.L.C.
#                                                           All rights reserved.
# copyright@cpanel.net                                         http://cpanel.net
# This code is subject to the cPanel license. Unauthorized copying is prohibited

#Passes, but not for production
#use strict;
use Carp             ();
use Cpanel::Binaries ();

our $VERSION = '1.0';

sub ClamScan_init {
    return (1);
}

sub ClamScan_scan {
    my ($file) = @_;

    my $clamdscan = Cpanel::Binaries::path("clamdscan");
    return if !-x $clamdscan;

    if ( my $pid = open( my $clam_fh, "-|" ) ) {
        $_ = <$clam_fh>;
    }
    elsif ( defined $pid ) {
        exec( $clamdscan, "--stdout", "--no-summary", $file );
        warn "exec: $!";
        exit 127;
    }
    else {
        warn "fork: $!";
        return;
    }

    chomp();
    my @RES    = split( /:/, $_ );
    my $result = $RES[$#RES];
    $result =~ s/^\s*//g;

    if (   $result =~ /connect to clamd/i
        || $result =~ /Connection refused/i
        || $result =~ /parse the configuration file/i
        || $result =~ /parse configuration file/i
        || $result =~ /Servname not supported for ai_socktype/i ) {
        $result = '';
    }
    return ($result);
}

1;
