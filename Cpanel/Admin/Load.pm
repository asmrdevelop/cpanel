package Cpanel::Admin::Load;

# cpanel - Cpanel/Admin/Load.pm                    Copyright 2022 cPanel, L.L.C.
#                                                           All rights reserved.
# copyright@cpanel.net                                         http://cpanel.net
# This code is subject to the cPanel license. Unauthorized copying is prohibited

use strict;
use warnings;

=encoding utf-8

=head1 NAME

Cpanel::Admin::Load - Loader for admin modules

=head1 SYNOPSIS

    my $perl_namespace = Cpanel::Admin::Load::load_if_exists('Cpanel', 'the_module');

=head1 DESCRIPTION

This module contains loader logic for cpsrvd admin modules.

=cut

#----------------------------------------------------------------------

use Cpanel::Autodie     ();
use Cpanel::ConfigFiles ();
use Cpanel::LoadModule  ();

our $_NS_RELPATH = 'Cpanel/Admin/Modules';

#----------------------------------------------------------------------

=head1 FUNCTIONS

=head2 $perl_ns = load_if_exists( $ADMIN_NS, $MODULE_NAME )

Attempts to load an admin module of the given $ADMIN_NS and $MODULE_NAME.
If no such module exists, this returns the empty string.

Currently the only supported $ADMIN_NS is C<Cpanel>. $MODULE_NAME
is, e.g., C<apitokens>.

=cut

sub load_if_exists {
    my ( $namespace, $module ) = @_;

    my ( $load, $base_path );

    my $ns_is_cpanel = ( $namespace eq 'Cpanel' );

    if ($ns_is_cpanel) {
        $base_path = "$Cpanel::ConfigFiles::CPANEL_ROOT/$_NS_RELPATH";

    }
    else {
        $base_path = "$Cpanel::ConfigFiles::CUSTOM_PERL_MODULES_DIR/$_NS_RELPATH";
    }

    # There’s no need to cache these lookups for now
    # since we don’t currently execute multiple batch calls per process.

    if ( Cpanel::Autodie::exists("$base_path/$namespace/$module.pm") ) {
        my $perl_ns = "Cpanel::Admin::Modules::${namespace}::$module";

        if ($ns_is_cpanel) {
            $load = Cpanel::LoadModule::load_perl_module($perl_ns);
        }
        else {
            require Cpanel::LoadModule::Custom;
            $load = Cpanel::LoadModule::Custom::load_perl_module($perl_ns);
        }
    }

    $load ||= q<>;

    return $load;
}

1;
