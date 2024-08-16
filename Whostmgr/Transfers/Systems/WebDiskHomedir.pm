package Whostmgr::Transfers::Systems::WebDiskHomedir;

# cpanel - Whostmgr/Transfers/Systems/WebDiskHomedir.pm
#                                                  Copyright 2022 cPanel, L.L.C.
#                                                           All rights reserved.
# copyright@cpanel.net                                         http://cpanel.net
# This code is subject to the cPanel license. Unauthorized copying is prohibited

use strict;

# RR Audit: JNK

use Cpanel::AccessIds::ReducedPrivileges ();
use Cpanel::WebDisk::Utils               ();

use base qw(
  Whostmgr::Transfers::Systems
);

sub get_summary {
    my ($self) = @_;
    return [ $self->_locale()->maketext('This rewrites web disk home directories to the correct location on the new server.') ];
}

sub get_restricted_available {
    return 1;
}

sub unrestricted_restore {
    my ($self) = @_;

    my $newuser      = $self->{'_utils'}->local_username();
    my $user_homedir = $self->homedir();

    return 1 if !$self->local_username_is_different_from_original_username();

    $self->start_action('Fixing homedir in Web Disk accounts');

    my ( $old_ok, $oldhomedirs_ref ) = $self->{'_archive_manager'}->get_old_homedirs();
    if ( ref $oldhomedirs_ref ) {
        my $red_privs = Cpanel::AccessIds::ReducedPrivileges->new($newuser);

        Cpanel::WebDisk::Utils::_change_webdisk_username( $oldhomedirs_ref->[0], $user_homedir );
    }

    return 1;
}

*restricted_restore = \&unrestricted_restore;

1;
