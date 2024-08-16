package Cpanel::Pkgacct::Components::Integration;

# cpanel - Cpanel/Pkgacct/Components/Integration.pm
#                                                  Copyright 2022 cPanel, L.L.C.
#                                                           All rights reserved.
# copyright@cpanel.net                                         http://cpanel.net
# This code is subject to the cPanel license. Unauthorized copying is prohibited

#----------------------------------------------------------------------
# NOTE: This module must “mirror” Whostmgr::Transfers::Systems::Integration.
#----------------------------------------------------------------------

use parent 'Cpanel::Pkgacct::Component';

use strict;
use Cpanel::Integration::Config ();

sub perform {
    my ($self) = @_;

    my $user = $self->get_user();

    my $links_dir = Cpanel::Integration::Config::links_dir_for_user($user);
    if ( $links_dir && -d $links_dir ) {
        $self->backup_dir_if_target_is_older_than_source( $links_dir, "integration/links" );
    }

    return 1;
}

1;
