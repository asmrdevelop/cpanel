package Whostmgr::Resellers::Parse;

# cpanel - Whostmgr/Resellers/Parse.pm             Copyright 2022 cPanel, L.L.C.
#                                                           All rights reserved.
# copyright@cpanel.net                                         http://cpanel.net
# This code is subject to the cPanel license. Unauthorized copying is prohibited

use strict;

use Cpanel::AcctUtils::Account ();

sub _parse_reseller_fh {
    my ($fh) = @_;

    return unless $fh;

    my $reseller_acl = {};

    foreach my $line ( readline($fh) ) {
        chomp($line);
        my ( $reseller, $acllist ) = split( /:/, $line, 2 );
        next if ( !defined($reseller) || $reseller eq '' );
        next if ( !Cpanel::AcctUtils::Account::accountexists($reseller) );

        # we could also split on \s*,\s* ? ( preserve old logic )
        $reseller_acl->{$reseller} = [ grep( !/^\s*$/, split( /\,/, $acllist || '' ) ) ];
    }

    return $reseller_acl;
}

1;
