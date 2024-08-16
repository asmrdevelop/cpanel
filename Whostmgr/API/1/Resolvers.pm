package Whostmgr::API::1::Resolvers;

# cpanel - Whostmgr/API/1/Resolvers.pm             Copyright 2022 cPanel, L.L.C.
#                                                           All rights reserved.
# copyright@cpanel.net                                         http://cpanel.net
# This code is subject to the cPanel license. Unauthorized copying is prohibited

use strict;
use warnings;

use Whostmgr::Resolvers ();

use constant NEEDS_ROLE => {
    setresolvers => undef,
};

sub setresolvers {
    my ( $args, $metadata ) = @_;
    my @nslist;
    for ( 1 .. 3 ) {
        if ( $args->{ 'nameserver' . $_ } ) {
            push @nslist, $args->{ 'nameserver' . $_ };
        }
    }
    my ( $status, $statusmsg, $msgref, $warnref ) = Whostmgr::Resolvers::setupresolvers(@nslist);

    $metadata->{'result'} = $status ? 1 : 0;
    $metadata->{'reason'} = $statusmsg;
    if ( $warnref && scalar @$warnref ) {
        chomp @$warnref;
        $metadata->{'output'}->{'warnings'} = join "\n", @$warnref;
    }
    if ( $msgref && scalar @$msgref ) {
        chomp @$msgref;
        $metadata->{'output'}->{'messages'} = join "\n", @$msgref;
    }
    return;
}

1;
