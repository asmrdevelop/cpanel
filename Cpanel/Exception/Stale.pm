package Cpanel::Exception::Stale;

# cpanel - Cpanel/Exception/Stale.pm               Copyright 2022 cPanel, L.L.C.
#                                                           All rights reserved.
# copyright@cpanel.net                                         http://cpanel.net
# This code is subject to the cPanel license. Unauthorized copying is prohibited

use strict;
use warnings;

=encoding utf-8

=head1 NAME

Cpanel::Exception::Stale - “Your request is stale”.

=head1 SYNOPSIS

    die Cpanel::Exception::create('Stale', 'Get with the times!');  ## no extract maketext

=head1 DESCRIPTION

This class represents a rejection of inputs that happens because
some element of the inputs is I<no longer> valid.

A typical use case would be a DNS zone edit where the submitted serial
number does not match the zone’s current serial number.

This class extends L<Cpanel::Exception::InvalidParameter>. It neither
provides a default message nor recognizes any parameters.

=cut

#----------------------------------------------------------------------

use parent qw( Cpanel::Exception::InvalidParameter );

1;
