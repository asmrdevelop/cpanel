package Cpanel::PHP;

# cpanel - Cpanel/PHP.pm                           Copyright 2022 cPanel, L.L.C.
#                                                           All rights reserved.
# copyright@cpanel.net                                         http://cpanel.net
# This code is subject to the cPanel license. Unauthorized copying is prohibited

use strict;
use warnings;

our $VERSION = 2.0;

sub PHP_init { }

sub PHP_fetchpkgs {

    # This is no longer permitted for security reasons
    return ();
}

sub PHP_loadparkeddomains {
    require Cpanel::DomainLookup;
    my %PARKED = Cpanel::DomainLookup::getmultiparked();
    _convert_underscore_period_keys( \%PARKED );
    return _php_write_var( '_CPANEL["PARKED"]', \%PARKED );
}

sub PHP_loadsubdomains {
    require Cpanel::DomainLookup;
    my %SUBS = Cpanel::DomainLookup::listsubdomains();
    _convert_underscore_period_keys( \%SUBS );
    return _php_write_var( '_CPANEL["SUBDOMAINS"]', \%SUBS );
}

sub PHP_loaddocroots {
    require Cpanel::DomainLookup::DocRoot;
    return _php_write_var( '_CPANEL["DOCROOT"]', scalar Cpanel::DomainLookup::DocRoot::getdocroots() );
}

sub PHP_loadvars {    ## no critic qw(Subroutines::ProhibitExcessComplexity Subroutines::RequireArgUnpacking)
    my %WANTED   = map { /\w+/ ? ( $_ => undef ) : () } @_;
    my $want_all = scalar keys %WANTED == 0 ? 1 : 0;
    () = $Cpanel::CONF{''};    # force CONF init
    _php_write_var( '_CPANEL["CPDATA"]',   \%Cpanel::CPDATA )   if ( $want_all || exists $WANTED{'CPDATA'} );
    _php_write_var( '_CPANEL["CONF"]',     \%Cpanel::CONF )     if ( $want_all || exists $WANTED{'CONF'} );
    _php_write_var( '_CPANEL["USERDATA"]', \%Cpanel::USERDATA ) if ( $want_all || exists $WANTED{'USERDATA'} );
    if ( $want_all || exists $WANTED{'RESUSERS'} ) {
        require Cpanel::AdminBin;
        require Cpanel::Reseller;
        require Cpanel::Reseller::Override;
        my $resuserref = {};
        my $reseller   = ( $Cpanel::isreseller ? $Cpanel::user : '' );
        if ( !$reseller && Cpanel::Reseller::Override::is_overriding() ) { $reseller = Cpanel::Reseller::Override::is_overriding_from(); }    #TEMP_SESSION_SAFE
        if ($reseller) {
            if ( $reseller ne $Cpanel::user && !Cpanel::Reseller::hasresellerpriv( $Cpanel::user, 'all' ) ) {
                $Cpanel::AdminBin::safecaching = 1;
            }
            $resuserref                    = Cpanel::AdminBin::adminfetch( "reseller", [ '/etc/trueuserdomains', '/var/cpanel/resellers' ], "RESELLERSUSERS", 'storable', $reseller );
            $Cpanel::AdminBin::safecaching = 0;
        }
        _php_write_var( '_CPANEL["RESUSERS"]', $resuserref );
    }
    _php_write_var( '_CPANEL["RESPKGS"]',    [ PHP_fetchpkgs() ] )  if ( $want_all || exists $WANTED{'RESPKGS'} );
    _php_write_var( '_CPANEL["DOMAINS"]',    \@Cpanel::DOMAINS )    if ( $want_all || exists $WANTED{'DOMAINS'} );
    _php_write_var( '_CPANEL["ALLDOMAINS"]', \@Cpanel::ALLDOMAINS ) if ( $want_all || exists $WANTED{'ALLDOMAINS'} );
    _php_write_var( '_CPANEL["root"]',       $Cpanel::root )        if ( $want_all || exists $WANTED{'root'} );
    _php_write_var( '_CPANEL["flags"]',      $Cpanel::flags )       if ( $want_all || exists $WANTED{'flags'} );
    _php_write_var( '_CPANEL["httphost"]',   $Cpanel::httphost )    if ( $want_all || exists $WANTED{'httphost'} );
    _php_write_var( '_CPANEL["homedir"]',    $Cpanel::homedir )     if ( $want_all || exists $WANTED{'homedir'} );
    _php_write_var( '_CPANEL["abshomedir"]', $Cpanel::abshomedir )  if ( $want_all || exists $WANTED{'abshomedir'} );

    return 1;
}

#
# ** This function does not handle circular references.  It will loop forever. ** (see case 44008 for more info)
#
sub _php_write_var {
    return print '$' . $_[0] . ' = ' . _serialize( $_[1] ) . ";\n";
}

#
# ** This function does not handle circular references.  It will loop forever. ** (see case 44008 for more info)
#
sub _serialize {
    return
       !defined $_[0]        ? 'null'
      : ref $_[0] eq 'HASH'  ? _serialize_hash( $_[0] )
      : ref $_[0] eq 'ARRAY' ? _serialize_array( $_[0] )
      : ( tr/\'// ? "'" . escape_single_quotes( $_[0] ) . "'" : "'$_[0]'" );
}

sub _serialize_array {
    return 'array(' . join(
        ',',
        map { !defined $_ ? 'null' : ref $_ ? _serialize($_) : ( tr/\'// ? "'" . escape_single_quotes($_) . "'" : "'$_'" ) } @{ $_[0] }
    ) . ')';
}

sub _serialize_hash {

    # This code had to be commented below to prevent perltidy from making it all 1 line.
    # The fact this map is so complicated argues for a foreach loop.
    # TODO: This should be considered if this code is ever re-factored.
    return 'array(' . join(
        ',',
        map {    #
            ( tr/\'// ? "'" . escape_single_quotes($_) . "'" : "'$_'" )    #
              . '=>'                                                       #
              . (                                                          #
                !defined $_[0]->{$_} ? 'null'                              #
                : (                                                        #
                    ref $_[0]->{$_} ? _serialize( $_[0]->{$_} )            #
                    : (                                                    #
                        $_[0]->{$_} =~ tr/\'// ? "'" . escape_single_quotes( $_[0]->{$_} ) . "'"    #
                        : "'$_[0]->{$_}'"                                                           #
                    )                                                                               #
                )                                                                                   #
              )                                                                                     #
          }    #
          keys %{ $_[0] }
    ) . ')';
}

sub _convert_underscore_period_keys {
    my $hashref = shift;
    my $periodkey;
    foreach my $underscorekey ( grep { tr/_// } keys %{$hashref} ) {
        $periodkey = $underscorekey;
        $periodkey =~ tr/_/\./;
        $hashref->{$periodkey} = $hashref->{$underscorekey};
    }

    # Doing the delete at the end is faster here
    return delete @{$hashref}{ ( grep { tr/_// } keys %{$hashref} ) };
}

sub escape_single_quotes {
    $_[0] =~ s/\'/\\\'/g;
    return $_[0];
}

1;
