package Whostmgr::AccessHash;

# cpanel - Whostmgr/AccessHash.pm                  Copyright 2022 cPanel, L.L.C.
#                                                           All rights reserved.
# copyright@cpanel.net                                         http://cpanel.net
# This code is subject to the cPanel license. Unauthorized copying is prohibited

use strict;
use warnings;

use Whostmgr::ACLS              ();
use Cpanel::SafetyBits          ();
use Cpanel::SafeRun::Simple     ();
use Whostmgr::Resellers::Check  ();
use Cpanel::AccessIds::LoadFile ();
use Cpanel::Logger              ();
use Cpanel::PwCache             ();

sub get_access_hash {
    my $user = shift || $ENV{'REMOTE_USER'} || '';

    Whostmgr::ACLS::init_acls();    # Must call this at run time or garbage compiled in.
    if ( !Whostmgr::ACLS::hasroot() && $user ne ( $ENV{'REMOTE_USER'} || '' ) ) {
        return 0, 'You do not have access to load another user\'s accesshash';
    }
    if ( !Whostmgr::Resellers::Check::is_reseller($user) && $user ne 'root' ) {
        return 0, "User $user is not a reseller.";
    }

    my $homedir = Cpanel::PwCache::gethomedir($user);
    if ( -e $homedir . '/.accesshash' ) {
        my $accesshash = Cpanel::AccessIds::LoadFile::loadfile_as_user( $user, $homedir . '/.accesshash' );
        if ( !$accesshash ) {
            return 0, 'There was a problem loading the accesshash.';
        }
        return 1, 'OK', $accesshash;
    }
    else {
        return 0, "No accesshash exists for $user";
    }
}

sub generate_access_hash {
    my $user = shift || $ENV{'REMOTE_USER'} || '';
    Whostmgr::ACLS::init_acls();    # Must call this at run time or garbage compiled in.
    if ( !Whostmgr::ACLS::hasroot() && $user ne ( $ENV{'REMOTE_USER'} || '' ) ) {
        return 0, 'You do not have access to generate another user\'s accesshash';
    }
    if ( !Whostmgr::Resellers::Check::is_reseller($user) && $user ne 'root' ) {
        return 0, "User $user is not a reseller.";
    }

    my $homedir = Cpanel::PwCache::gethomedir($user);

    local $ENV{'REMOTE_USER'} = $user;
    Cpanel::SafeRun::Simple::saferun('/usr/local/cpanel/bin/mkaccesshash');

    Cpanel::SafetyBits::safe_chmod( 0600, $user, $homedir . '/.accesshash' );
    if ( -e $homedir . '/.accesshash' ) {
        my $accesshash = Cpanel::AccessIds::LoadFile::loadfile_as_user( $user, $homedir . '/.accesshash' );
        return 1, 'OK', $accesshash;
    }
    else {
        return 0, 'There was a problem generating the access hash.';
    }
}

sub get_remote_access_hash {
    my ( $host, $user, $pass, $generate ) = @_;
    $generate = 0 if !defined $generate;
    my $logger = Cpanel::Logger->new();
    if ( !$user ) {
        return 0, 'Whostmgr::AccessHash::get_remote_access_hash requires that a user is defined';
    }
    if ( !$pass ) {
        return 0, 'Whostmgr::AccessHash::get_remote_access_hash requires that a password is defined';
    }
    if ( !$host ) {
        return 0, 'Whostmgr::AccessHash::get_remote_access_hash requires that a host is defined';
    }
    require Cpanel::PublicSuffix;    # PPI USE OK -- laod before cPanel::PublicAPI so we provide our PublicSuffix module to HTTP::CookieJar
    eval { require cPanel::PublicAPI; };
    if ($@) {
        $logger->info( 'Failed to load cPanel::PublicAPI: ' . $@ );
        return 0, "Failed to load cPanel::PublicAPI";
    }
    my $pubapi = cPanel::PublicAPI->new(
        'usessl'          => 1,
        'ssl_verify_mode' => 0,
        'host'            => $host,
        'user'            => $user,
        'pass'            => $pass
    );
    my $res;
    eval { $res = $pubapi->whm_api( 'accesshash', { 'api.version' => 1, 'generate' => $generate } ); };
    if ($@) {
        return 0, "There was a communication error with the remote server: " . $pubapi->{'error'};
    }
    if ( !$res->{'metadata'}->{'result'} ) {
        return 0, "The remote api returned an error: " . $res->{'metadata'}->{'reason'};
    }
    return 1, 'OK', $res->{'data'}->{'accesshash'};
}

1;
