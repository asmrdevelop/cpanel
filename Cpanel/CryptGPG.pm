package Cpanel::CryptGPG;

# cpanel - Cpanel/CryptGPG.pm                      Copyright 2022 cPanel, L.L.C.
#                                                           All rights reserved.
# copyright@cpanel.net                                         http://cpanel.net
# This code is subject to the cPanel license. Unauthorized copying is prohibited

use strict;
use Cpanel::ExtPerlMod ();
use Cpanel::Logger     ();

our $VERSION = '1.0';

sub CryptGPG_init { }

sub new {
    my $self = shift;
    $self = {};
    bless $self;
    return $self;
}

sub keydb {
    my $self = shift;
    my $id   = shift;
    my %OPTS;
    $OPTS{'id'} = $id;
    my $opref = Cpanel::ExtPerlMod::func( 'Cpanel::CryptGPG_ExtPerlMod::keydb', \%OPTS, 1 );
    if ( !$opref || ref $opref ne 'ARRAY' ) {
        Cpanel::Logger::cplog( "Unable to read key database from CryptGPG_ExtPerlMod", 'info', __PACKAGE__ );
        return ();
    }
    else {
        return @{$opref};
    }
}

sub delkey {
    my $self = shift;
    my $key  = shift;
    my %OPTS;
    $OPTS{'key'} = $key;
    return int Cpanel::ExtPerlMod::func( 'Cpanel::CryptGPG_ExtPerlMod::delkey', \%OPTS );
}

1;
