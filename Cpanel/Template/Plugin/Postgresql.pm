package Cpanel::Template::Plugin::Postgresql;

# cpanel - Cpanel/Template/Plugin/Postgresql.pm    Copyright 2022 cPanel, L.L.C.
#                                                           All rights reserved.
# copyright@cpanel.net                                         http://cpanel.net
# This code is subject to the cPanel license. Unauthorized copying is prohibited

use strict;

use base 'Cpanel::Template::Plugin::CpanelDB';

use Cpanel::GlobalCache ();

sub _PASSWORD_STRENGTH_APP { return 'postgres' }

*required_password_strength = __PACKAGE__->can('_required_password_strength');

sub is_configured {
    return Cpanel::GlobalCache::data( 'cpanel', 'has_postgres' );
}

1;
