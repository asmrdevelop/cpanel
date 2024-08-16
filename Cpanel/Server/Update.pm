package Cpanel::Server::Update;

# cpanel - Cpanel/Server/Update.pm                 Copyright 2022 cPanel, L.L.C.
#                                                           All rights reserved.
# copyright@cpanel.net                                         http://cpanel.net
# This code is subject to the cPanel license. Unauthorized copying is prohibited

use strict;

# This code is here to assure that cpsrvd restarts do not cause clustering on when
# the license server is called home. If $now is not passed in then we set it to the
# value of cpanel.lisc's mtime since the assumption is that that was the last update.
# Once we have a time, we randomize it to +- 2 hours to assure license server
# connections do not cluster around a certain time period (i.e. a popular upcp time of day).
# Because we randomize this number daily and call home between 22 to 26 hours from
# the last update, this will assure that on average the license server connections
# even out over time.

# Because this logic is shared between cpsrvd and cpsrvd dormant and is used in 4
# places at time of coding, it was deemed safer to centralize and properly test it.

sub next_update {
    my $now = shift;

    if ( !$now ) {
        $now = ( stat('/usr/local/cpanel/cpanel.lisc') )[9] or return 0;
    }

    return $now - 2 * 60 * 60 + int( rand( 4 * 60 * 60 ) );
}

1;
