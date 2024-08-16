package Cpanel::LinkedNode::QuotaBalancer::Run::State;

# cpanel - Cpanel/LinkedNode/QuotaBalancer/Run/State.pm
#                                                  Copyright 2022 cPanel, L.L.C.
#                                                           All rights reserved.
# copyright@cpanel.net                                         http://cpanel.net
# This code is subject to the cPanel license. Unauthorized copying is prohibited

use cPstrict;

=encoding utf-8

=head1 NAME

Cpanel::LinkedNode::QuotaBalancer::Run

=head1 DESCRIPTION

This module represents the externally-visible state of a quota-balancer run.

=head1 ACCESSORS

=head2 $promise = I<OBJ>->get_promise()

Returns a promise that resolves when the quota-balancer is done.
This promise never rejects.

=cut

use Class::XSAccessor (
    constructor => 'new',
    getters     => {
        'get_promise' => 'promise',
    },
);

1;
