package Cpanel::Server::ModularApp::cpanel;

# cpanel - Cpanel/Server/ModularApp/cpanel.pm      Copyright 2022 cPanel, L.L.C.
#                                                           All rights reserved.
# copyright@cpanel.net                                         http://cpanel.net
# This code is subject to the cPanel license. Unauthorized copying is prohibited

use cPstrict;

=encoding utf-8

=head1 NAME

Cpanel::Server::ModularApp::cpanel

=head1 DESCRIPTION

This module implements L<Cpanel::Server::ModularApp>’s C<_can_access()>
method for cPanel applications.

It exposes its own subclass interface which corresponds with access
control mechanisms appropriate to cPanel.

Application classes that require more specific access control logic can
wrap this module’s C<_can_access()> method with their own, e.g.:

    sub _can_access ($self, $server_obj) {

        return $self->SUPER::_can_access($server_obj) && do {

            # … whatever additional access control logic is needed
        };
    }

=cut

use parent qw(
  Cpanel::Server::ModularApp
);

use Cpanel::Exception       ();
use Cpanel::Features::Check ();

sub _can_access ( $self, $server_obj ) {
    my $auth = $server_obj->auth();

    if ( !$self->_ALLOW_DEMO_MODE() ) {
        if ( $auth->get_demo() ) {
            die Cpanel::Exception::create( 'cpsrvd::Forbidden', 'This resource is unavailable in demo mode.' );
        }
    }

    for my $feature ( $self->_ACCEPTED_FEATURES() ) {
        return 1 if $feature eq 'any' || Cpanel::Features::Check::check_feature_for_user(
            $auth->get_user(),
            $feature,
            $auth->get_featurelist(),
            $auth->get_features_from_cpdata(),
        );
    }

    return 0;
}

######################################################################

=head1 SUBCLASS INTERFACE

=head2 I<OBJ>->_ACCEPTED_FEATURES()

Optional, returns the list of features that allow a cPanel user to run the
module.  It’s empty by default, which disallows access for all cPanel users.

Include C<any> as a value to allow all cPanel users.

This is only relevant if the base class’s C<verify_access()> is used;
if the application overrides this method, then this method is irrelevant.

=cut

use constant _ACCEPTED_FEATURES => ();

#----------------------------------------------------------------------

=head2 I<OBJ>->_ALLOW_DEMO_MODE()

Whether to allow a demo-mode cPanel user to use the module.
Defaults to off.

=cut

use constant _ALLOW_DEMO_MODE => 0;

1;
