package Cpanel::Pkgacct::Components::AuthnLinks;

# cpanel - Cpanel/Pkgacct/Components/AuthnLinks.pm Copyright 2022 cPanel, L.L.C.
#                                                           All rights reserved.
# copyright@cpanel.net                                         http://cpanel.net
# This code is subject to the cPanel license. Unauthorized copying is prohibited

use parent 'Cpanel::Pkgacct::Component';

use strict;

use Cpanel::Security::Authn::User ();

sub perform {
    my ($self) = @_;

    my $user                = $self->get_user();
    my $authn_links_db_path = Cpanel::Security::Authn::User::get_user_db_directory($user);
    if ( $authn_links_db_path && -d $authn_links_db_path ) {
        $self->backup_dir_if_target_is_older_than_source( $authn_links_db_path, "authnlinks" );
    }

    return 1;
}

1;
