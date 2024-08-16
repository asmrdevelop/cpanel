package Cpanel::RemoteAPI::WHM::ToChild;

# cpanel - Cpanel/RemoteAPI/WHM/ToChild.pm         Copyright 2022 cPanel, L.L.C.
#                                                           All rights reserved.
# copyright@cpanel.net                                         http://cpanel.net
# This code is subject to the cPanel license. Unauthorized copying is prohibited

use cPstrict;

=encoding utf-8

=head1 NAME

Cpanel::RemoteAPI::WHM::ToChild

=head1 SYNOPSIS

See the parent class.

=head1 DESCRIPTION

This class extends L<Cpanel::RemoteAPI::WHM> with logic that
ensures that sent API calls self-identify as a parent node.

=cut

#----------------------------------------------------------------------

use parent 'Cpanel::RemoteAPI::WHM';

use Cpanel::APICommon::Persona ();    ## PPI NO PARSE -- mis-parse constant

#----------------------------------------------------------------------

=head1 METHODS

=head2 $result = I<OBJ>->request_whmapi1(...)

Same as in the parent class.

=cut

sub request_whmapi1 ( $self, $fn, $args_hr = undef ) {
    $args_hr ||= {};
    local $args_hr->{'api.persona'} = Cpanel::APICommon::Persona::PARENT;

    return $self->SUPER::request_whmapi1( $fn, $args_hr );
}

=head2 $result = I<OBJ>->request_cpanel_uapi(...)

Same as in the parent class.

=cut

sub request_cpanel_uapi ( $self, $cpusername, $module, $fn, $args_hr = undef ) {    ## no critic qw(ManyArgs) - mis-parse
    $args_hr ||= {};
    local $args_hr->{'api.persona'} = Cpanel::APICommon::Persona::PARENT;

    return $self->SUPER::request_cpanel_uapi( $cpusername, $module, $fn, $args_hr );
}

1;
