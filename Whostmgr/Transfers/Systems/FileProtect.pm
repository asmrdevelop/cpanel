package Whostmgr::Transfers::Systems::FileProtect;

# cpanel - Whostmgr/Transfers/Systems/FileProtect.pm
#                                                  Copyright 2022 cPanel, L.L.C.
#                                                           All rights reserved.
# copyright@cpanel.net                                         http://cpanel.net
# This code is subject to the cPanel license. Unauthorized copying is prohibited

use strict;
use warnings;

# RR Audit: JNK

use Cpanel::FileProtect::Sync ();

use base qw(
  Whostmgr::Transfers::Systems
);

sub get_phase {
    return 100;
}

sub get_summary {
    my ($self) = @_;
    return [ $self->_locale()->maketext('This configures the account for [asis,cPanel FileProtect].') ];
}

sub get_restricted_available {
    return 1;
}

sub restricted_restore {
    my ($self) = @_;

    my $newuser = $self->newuser();
    for my $warning ( Cpanel::FileProtect::Sync::sync_user_homedir($newuser) ) {
        $self->warn( $warning->to_string() );
    }

    return 1;
}

*unrestricted_restore = \&restricted_restore;

1;
