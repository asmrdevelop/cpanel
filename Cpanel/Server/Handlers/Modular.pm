package Cpanel::Server::Handlers::Modular;

# cpanel - Cpanel/Server/Handlers/Modular.pm       Copyright 2022 cPanel, L.L.C.
#                                                           All rights reserved.
# copyright@cpanel.net                                         http://cpanel.net
# This code is subject to the cPanel license. Unauthorized copying is prohibited

use strict;
use warnings;

=encoding utf-8

=head1 NAME

Cpanel::Server::Handlers::Modular - common module-loading logic

=head1 DESCRIPTION

This module implements a module-loading pattern that is useful
to multiple cpsrvd handlers.

=cut

#----------------------------------------------------------------------

use Try::Tiny;

use Cpanel::App        ();
use Cpanel::Exception  ();
use Cpanel::LoadModule ();

#----------------------------------------------------------------------

=head1 FUNCTIONS

=head2 $ns = load_and_authz_module( $SERVER_OBJ, $PARENT_NS, $MODULE )

This function loads and authorizes use of a given module:

=over

=item * Fetches the normalized appname from L<Cpanel::App>, then loads
the module C<$PARENT_NS::$appname::$MODULE>. (This name is the value that
the function ultimately returns.) If this module doesn’t exist,
a L<Cpanel::Exception::cpsrvd::NotFound> instance is thrown.

=item * Executes that module’s L<verify_access()> class method.
If that method returns falsy, an internal exception is thrown.

=back

The return (C<$ns>) is the full module name.

=cut

sub load_and_authz_module {
    my ( $server_obj, $namespace, $module ) = @_;

    # Sanity check on the module name.
    if ( !$module || $module =~ tr<a-zA-Z><>c ) {
        die Cpanel::Exception::create_raw('cpsrvd::NotFound');
    }

    my $service_ns = Cpanel::App::get_normalized_name();

    my $full_mod = $namespace . "::${service_ns}::$module";

    try {
        local $SIG{'__DIE__'} = 'DEFAULT';
        Cpanel::LoadModule::load_perl_module($full_mod);
    }
    catch {
        if ( $_->is_not_found() ) {
            die Cpanel::Exception::create('cpsrvd::NotFound');
        }

        local $@ = $_;
        die;
    };

    if ( !$full_mod->verify_access($server_obj) ) {

        # This will give an HTTP 500 error.
        die "${full_mod}::verify_access() must return 1 when the module is permitted and die otherwise.";
    }

    return $full_mod;
}

1;
