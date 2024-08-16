package Cpanel::Exception::Market::CustomerServiceRequired;

# cpanel - Cpanel/Exception/Market/CustomerServiceRequired.pm
#                                                  Copyright 2022 cPanel, L.L.C.
#                                                           All rights reserved.
# copyright@cpanel.net                                         http://cpanel.net
# This code is subject to the cPanel license. Unauthorized copying is prohibited

=head1 NAME

Cpanel::Exception::Market::CustomerServiceRequired - A generic Market exception.

=head1 SYNOPSIS

    die Cpanel::Exception::External::create( 'Market::CustomerServiceRequired', {
        provider => 'some_provider',
        order_id => $order_id,
    });

=head1 DESCRIPTION

This exception class represents an error emitted by a market provider where the
only resolution is to contact their customer support department.

=cut

use strict;
use warnings;

use parent qw( Cpanel::Exception::Market );

use Cpanel::Market ();

use Cpanel::LocaleString ();

sub _default_phrase {
    my ($self) = @_;

    my $disp_name = Cpanel::Market::get_provider_display_name( $self->get('provider') );

    return Cpanel::LocaleString->new(
        'There is an issue with your order. Please contact “[_1]” and request support for order ID “[_2]”.',
        $disp_name,
        $self->get('order_id'),
    );
}

1;
