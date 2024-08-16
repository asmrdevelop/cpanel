package Cpanel::LoadModule::IfExists;

# cpanel - Cpanel/LoadModule/IfExists.pm           Copyright 2022 cPanel, L.L.C.
#                                                           All rights reserved.
# copyright@cpanel.net                                         http://cpanel.net
# This code is subject to the cPanel license. Unauthorized copying is prohibited

use cPstrict;

=encoding utf-8

=head1 NAME

Cpanel::LoadModule::IfExists

=head1 SYNOPSIS

    my $pkg = Cpanel::LoadModule::IfExists::load_if_exists('Some::Package');

    if ($pkg) {
        $pkg->run_class_method();
    }

=head1 DESCRIPTION

This module fits nicely into applications that expect to tolerate
nonexistence of a runtime-loaded module.

=cut

#----------------------------------------------------------------------

use Cpanel::LoadModule ();
use Cpanel::Try        ();

#----------------------------------------------------------------------

=head1 FUNCTIONS

=head2 $pkg_or_undef = load_if_exists( $PACKAGE )

Tries to load $PACKAGE. If the load succeeds, this returns $PACKAGE.
if the load fails because of nonexistence, this returns undef.
Any other failure triggers an exception.

=cut

sub load_if_exists ($pkg) {
    my $ns;

    Cpanel::Try::try(
        sub {
            $ns = Cpanel::LoadModule::load_perl_module($pkg);
        },
        'Cpanel::Exception::ModuleLoadError' => sub ($err) {
            if ( !$err->is_not_found() ) {
                local $@ = $err;
                die;
            }
        },
    );

    return $ns;
}

1;
