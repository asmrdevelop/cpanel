package Cpanel::Reseller;

# cpanel - Cpanel/Reseller.pm                      Copyright 2022 cPanel, L.L.C.
#                                                           All rights reserved.
# copyright@cpanel.net                                         http://cpanel.net
# This code is subject to the cPanel license. Unauthorized copying is prohibited

use strict;

use Try::Tiny;

use Cpanel::LoadFile    ();
use Cpanel::Autodie     ();
use Cpanel::Debug       ();
use Cpanel::ConfigFiles ();

#######################################################
# Must be our so Cpanel::Reseller::Cache can reset this
# (the reset has been moved to a new module Cpanel::Reseller::Cache
# in order to avoid including the AskDnsAdmin module)
#######################################################
our %RESELLER_PRIV_CACHE;
our %RESELLER_EXISTS_CACHE;
#######################################################

our $reseller_cache_fully_loaded;    # exposed for testing.
our $is_dnsadmin;

sub isreseller {
    my $user = shift;
    return 1 if ( !defined $user || $user eq 'cpanel' || $user eq 'root' || $user eq '' );    #must be first or caches may overwrite see case 53421
    return 0 if ( $reseller_cache_fully_loaded && !exists $RESELLER_PRIV_CACHE{$user} );

    _load_one_reseller($user) unless ( exists $RESELLER_PRIV_CACHE{$user} || exists $RESELLER_EXISTS_CACHE{$user} );
    if ( exists $RESELLER_PRIV_CACHE{$user} || exists $RESELLER_EXISTS_CACHE{$user} ) {
        return ( ( $RESELLER_EXISTS_CACHE{$user} || scalar keys %{ $RESELLER_PRIV_CACHE{$user} } ) ? 1 : 0 );
    }
    return 0;
}

# This function ignores dynamic ACLs altogether.
sub hasresellerpriv {
    my ( $reseller, $priv ) = @_;

    if ( !$reseller || !$priv ) {
        return 0;
    }
    elsif ( $reseller eq 'root' ) {
        return 1;
    }

    if ( exists $RESELLER_EXISTS_CACHE{$reseller} && !$RESELLER_EXISTS_CACHE{$reseller} ) {
        return 0;
    }

    _load_one_reseller($reseller) unless ( exists $RESELLER_PRIV_CACHE{$reseller} && ref $RESELLER_PRIV_CACHE{$reseller} );

    if ( exists $RESELLER_PRIV_CACHE{$reseller} && ref $RESELLER_PRIV_CACHE{$reseller} ) {
        return 1 if exists $RESELLER_PRIV_CACHE{$reseller}->{'all'};
        return ( exists $RESELLER_PRIV_CACHE{$reseller}->{$priv} ? 1 : 0 );
    }

    return 0;
}

sub _load_one_reseller {
    my ($reseller) = @_;
    my $quotedreseller = $reseller . ':';

    my $res_fh;
    try {
        Cpanel::Autodie::open( $res_fh, '<', $Cpanel::ConfigFiles::RESELLERS_FILE );
    }
    catch {
        Cpanel::Debug::log_warn( $_->to_string() );
    };

    if ( fileno $res_fh ) {
        my $line;
        while ( $line = readline $res_fh ) {
            if ( index( $line, $quotedreseller ) == 0 ) {    # $line =~ /^$quotedreseller/ ) {
                close $res_fh;

                # Normalize possibly manually entered privileges
                chomp $line;
                $line =~ tr{ \t}{}d;
                $RESELLER_PRIV_CACHE{$reseller} = { map { $_ => 1 } split( m{,}, ( split( m{:}, $line, 2 ) )[1] ) };
                delete $RESELLER_PRIV_CACHE{$reseller}{''};
                return ( $RESELLER_EXISTS_CACHE{$reseller} = 1 );
            }
        }
        close $res_fh;
        return 1;
    }

    return ( $RESELLER_EXISTS_CACHE{$reseller} = 0 );
}

sub get_one_reseller_privs {
    my $reseller = shift;
    return _load_one_reseller($reseller) ? $RESELLER_PRIV_CACHE{$reseller} || {} : {};
}

#XXX FIXME: This should NOT return a reference to this module's
#internal %RESELLER_PRIV_CACHE variable; instead, it should return a clone.
#TODO: Make the clone happen in 11.50 or afterward. We'll need to audit first
#to ensure that nothing depends on this unhealthful behavior.
#
sub getresellersaclhash {
    if ( !-e $Cpanel::ConfigFiles::RESELLERS_FILE ) {
        return wantarray ? () : {};
    }

    if ($reseller_cache_fully_loaded) {
        return wantarray ? %RESELLER_PRIV_CACHE : \%RESELLER_PRIV_CACHE;
    }

    %RESELLER_PRIV_CACHE = ();
    my $data = Cpanel::LoadFile::load_if_exists($Cpanel::ConfigFiles::RESELLERS_FILE);
    foreach my $line ( split( m{\n}, $data ) ) {
        $line =~ tr{ \t}{}d;
        my ( $reseller, $acl ) = split m{:}, $line, 2;
        next if ( !length $reseller || index( $reseller, '#' ) == 0 || !defined $acl );
        $RESELLER_PRIV_CACHE{$reseller} = { map { $_ => 1 } split m{,}, $acl };
    }
    $reseller_cache_fully_loaded = 1;
    @RESELLER_EXISTS_CACHE{ keys %RESELLER_PRIV_CACHE } = (1) x scalar keys %RESELLER_PRIV_CACHE;

    return wantarray ? %RESELLER_PRIV_CACHE : \%RESELLER_PRIV_CACHE;
}

sub getresellerslist {
    return wantarray ? ( sort keys %{ getresellersaclhash() } ) : [ sort keys %{ getresellersaclhash() } ];
}

1;
