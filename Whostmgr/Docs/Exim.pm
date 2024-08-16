package Whostmgr::Docs::Exim;

# cpanel - Whostmgr/Docs/Exim.pm                   Copyright 2022 cPanel, L.L.C.
#                                                           All rights reserved.
# copyright@cpanel.net                                         http://cpanel.net
# This code is subject to the cPanel license. Unauthorized copying is prohibited

use strict;
my $cfg_docs;

use Cpanel::YAML::Syck ();

sub fetch_key {
    my $ref = shift;
    $cfg_docs ||= YAML::Syck::LoadFile('/usr/local/cpanel/share/doc/exim/main_config.yaml');
    return $cfg_docs->{ $ref->{'key'} } || '';
}

1;
