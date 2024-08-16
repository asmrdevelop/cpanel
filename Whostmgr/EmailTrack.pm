package Whostmgr::EmailTrack;

# cpanel - Whostmgr/EmailTrack.pm                  Copyright 2022 cPanel, L.L.C.
#                                                           All rights reserved.
# copyright@cpanel.net                                         http://cpanel.net
# This code is subject to the cPanel license. Unauthorized copying is prohibited

use strict;
use Cpanel::EximStats::ConnectDB   ();
use Whostmgr::AcctInfo::Owner      ();
use Whostmgr::ACLS                 ();
use Cpanel::Exception              ();
use Cpanel::DeliveryReporter       ();
use Cpanel::Config::LoadUserOwners ();
use Try::Tiny;

sub search {
    _exec_emailtrack( 'query', @_ );
}

sub stats {
    _exec_emailtrack( 'stats', @_ );
}

sub user_stats {
    _exec_emailtrack( 'user_stats', @_ );
}

sub _exec_emailtrack {
    my ( $cmd, $argref ) = @_;
    my $user = $argref->{'user'};
    if (   $user
        && $user ne $ENV{'REMOTE_USER'}
        && !Whostmgr::ACLS::hasroot()
        && !Whostmgr::AcctInfo::Owner::checkowner( $ENV{'REMOTE_USER'}, $user ) ) {
        return ( 0, "Access Denied to Account $user" );
    }

    if ( !Whostmgr::ACLS::hasroot() ) {
        my $ownermap_ref = Cpanel::Config::LoadUserOwners::loadtrueuserowners();
        $user = $ownermap_ref->{ $ENV{'REMOTE_USER'} };
        if ( !grep { $_ eq $ENV{'REMOTE_USER'} } @{$user} ) {
            push @{$user}, $ENV{'REMOTE_USER'};    #always include self
        }
    }

    my $dbh               = Cpanel::EximStats::ConnectDB::dbconnect();
    my $delivery_reporter = Cpanel::DeliveryReporter->new( 'dbh' => $dbh, ( $user ? ( 'user' => $user ) : () ) );

    my $err;
    my @output;
    try {
        @output = $delivery_reporter->$cmd( %{$argref} );
    }
    catch {
        $err = $_;
    };

    if ($err) {
        return ( 0, 'Error from delivery reporter: ' . Cpanel::Exception::get_string($err) );
    }

    return ( '1', 'OK', @output );
}
1;
