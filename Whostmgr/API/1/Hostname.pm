package Whostmgr::API::1::Hostname;

# cpanel - Whostmgr/API/1/Hostname.pm              Copyright 2022 cPanel, L.L.C.
#                                                           All rights reserved.
# copyright@cpanel.net                                         http://cpanel.net
# This code is subject to the cPanel license. Unauthorized copying is prohibited

use strict;
use warnings;

use constant NEEDS_ROLE => {
    sethostname => undef,
};

sub sethostname {
    my ( $args, $metadata ) = @_;
    my $hostname = $args->{'hostname'};
    require Whostmgr::Hostname;
    my ( $status, $statusmsg, $warnref, $msgref ) = Whostmgr::Hostname::sethostname($hostname);

    $metadata->{'result'} = $status ? 1 : 0;
    $metadata->{'reason'} = $statusmsg;
    if ( ( ref $warnref eq 'ARRAY' ) and scalar @$warnref ) {
        chomp @$warnref;
        $metadata->{'output'}->{'warnings'} = join "\n", @$warnref;
    }
    if ( ( ref $msgref eq 'ARRAY' ) && scalar @$msgref ) {
        chomp @$msgref;
        $metadata->{'output'}->{'messages'} = join "\n", @$msgref;
    }
    return;
}

1;
