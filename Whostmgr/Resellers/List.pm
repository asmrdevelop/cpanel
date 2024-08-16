package Whostmgr::Resellers::List;

# cpanel - Whostmgr/Resellers/List.pm              Copyright 2022 cPanel, L.L.C.
#                                                           All rights reserved.
# copyright@cpanel.net                                         http://cpanel.net
# This code is subject to the cPanel license. Unauthorized copying is prohibited

use strict;

use Cpanel::AcctUtils::Load    ();
use Cpanel::ConfigFiles        ();
use Cpanel::Debug              ();
use Whostmgr::Resellers::Parse ();

sub list {
    my %RES;
    Cpanel::AcctUtils::Load::loadaccountcache();
    open( my $fh, '<', $Cpanel::ConfigFiles::RESELLERS_FILE ) or do {
        Cpanel::Debug::log_warn("Unable to open $Cpanel::ConfigFiles::RESELLERS_FILE for reading: $!");
    };
    my $resellers = Whostmgr::Resellers::Parse::_parse_reseller_fh($fh);
    close $fh;

    %RES = map { $_ => 1 } keys %$resellers if $resellers;

    return \%RES;
}

1;
