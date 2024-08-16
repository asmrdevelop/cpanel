package Whostmgr::Resellers::Kill;

# cpanel - Whostmgr/Resellers/Kill.pm              Copyright 2022 cPanel, L.L.C.
#                                                           All rights reserved.
# copyright@cpanel.net                                         http://cpanel.net
# This code is subject to the cPanel license. Unauthorized copying is prohibited

use strict;
## no critic qw(TestingAndDebugging::RequireUseWarnings)

use Cpanel::CachedDataStore    ();
use Cpanel::AcctUtils::Account ();
use Whostmgr::Accounts::Remove ();
use Whostmgr::AcctInfo         ();

sub kill_owned_accts {
    my $reseller     = shift;
    my $killreseller = shift;
    my $showstatus   = shift;

    my %KILLACCT;
    my %ACCTS = Whostmgr::AcctInfo::getaccts($reseller);
    if ($killreseller) {
        $ACCTS{$reseller} = 1;
    }
    foreach my $acct ( keys %ACCTS ) {
        next if ( !Cpanel::AcctUtils::Account::accountexists($acct) );

        my ( $result, $reason, $output ) = Whostmgr::Accounts::Remove::_removeaccount(
            'user'    => $acct,
            'keepdns' => 0,
        );

        if ($result) {
            if ($showstatus) { print "<p>Account Removal Status: ok ($reason)</p>" }
        }
        else {
            if ($showstatus) { print "<p>Account Removal Status: failed ($reason)</p>" }
        }
        if ( $showstatus && $output ) { print "<blockquote>$output</blockquote>\n" }

        Cpanel::CachedDataStore::clear_cache();

        $KILLACCT{$acct} = { 'status' => $result, 'statusmsg' => $reason, 'rawout' => $output };
    }
    return \%KILLACCT;
}

1;
