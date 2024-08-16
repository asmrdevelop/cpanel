package Cpanel::Async::RemoteAPI::WHM::ToChild;

# cpanel - Cpanel/Async/RemoteAPI/WHM/ToChild.pm   Copyright 2022 cPanel, L.L.C.
#                                                           All rights reserved.
# copyright@cpanel.net                                         http://cpanel.net
# This code is subject to the cPanel license. Unauthorized copying is prohibited

use cPstrict;

=encoding utf-8

=head1 NAME

Cpanel::Async::RemoteAPI::WHM::ToChild

=head1 SYNOPSIS

See the parent class.

=head1 DESCRIPTION

This class extends L<Cpanel::Async::RemoteAPI::WHM> with logic that
ensures that sent API calls self-identify as a parent node.

=cut

#----------------------------------------------------------------------

use parent 'Cpanel::Async::RemoteAPI::WHM';

use Cpanel::APICommon::Persona ();    ## PPI NO PARSE -- mis-parse constant

#----------------------------------------------------------------------

=head1 METHODS

=head2 promise(...) = I<OBJ>->request_whmapi1(...)

Same as in the parent class.

=cut

sub request_whmapi1 ( $self, $funcname, $args_hr = undef ) {
    my %args_copy = $args_hr ? %$args_hr : ();

    $args_copy{'api.persona'} = Cpanel::APICommon::Persona::PARENT;

    return $self->SUPER::request_whmapi1( $funcname, \%args_copy );
}

=head2 promise(...) = I<OBJ>->request_cpanel_uapi(...)

Same as in the parent class.

=cut

sub request_cpanel_uapi ( $self, $cpusername, $module, $fn, $args_hr = undef ) {    ## no critic qw(ManyArgs) - mis-parse
    my %args_copy = $args_hr ? %$args_hr : ();

    $args_copy{'api.persona'} = Cpanel::APICommon::Persona::PARENT;

    return $self->SUPER::request_cpanel_uapi( $cpusername, $module, $fn, \%args_copy );
}

1;
