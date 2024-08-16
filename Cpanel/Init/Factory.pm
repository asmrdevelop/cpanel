package Cpanel::Init::Factory;

# cpanel - Cpanel/Init/Factory.pm                  Copyright 2022 cPanel, L.L.C.
#                                                           All rights reserved.
# copyright@cpanel.net                                         http://cpanel.net
# This code is subject to the cPanel license. Unauthorized copying is prohibited

use Moo;
use cPstrict;

use Cpanel::Init::Utils ();
use Cpanel::OS          ();

has 'name_space' => ( is => 'ro', init_arg => 'name_space' );

sub factory ($self) {
    my $module_name = ucfirst( Cpanel::OS::service_manager() );

    my $package = $self->name_space . '::' . $module_name;

    Cpanel::Init::Utils::load_subclass($package);

    # Return the new object.
    return $package->new;
}

1;
