package Cpanel::Exception::Market::OrderNotFound;

# cpanel - Cpanel/Exception/Market/OrderNotFound.pm
#                                                  Copyright 2022 cPanel, L.L.C.
#                                                           All rights reserved.
# copyright@cpanel.net                                         http://cpanel.net
# This code is subject to the cPanel license. Unauthorized copying is prohibited

#----------------------------------------------------------------------
# This exception class represents an indication that an operation on an
# order failed because the store indicated that the user doesn’t have access
# to an order with the given ID.
#
# For example, if you:
#   1) log in to cPStore as “jfk123”,
#   2) place an order with ID “abq4f8”,
#   3) then try to check out while logged in to cPStore as “lbj234”
#
# … then throwing an instance of this class would be the appropriate
# way to indicate the failure that cPStore should report.
#----------------------------------------------------------------------

use strict;
use warnings;

use parent qw( Cpanel::Exception::Market );

use Cpanel::Market ();

use Cpanel::LocaleString ();

#Three arguments required:
#
#   - provider (string, e.g., 'cPStore')
#   - order_id (string)
#
sub _default_phrase {
    my ($self) = @_;

    my $disp_name = Cpanel::Market::get_provider_display_name( $self->get('provider') );

    return Cpanel::LocaleString->new(
        '“[_1]” indicated that you do not have an order with the [asis,ID] “[_2]”. Verify that you logged in to “[_1]” as the appropriate user.',
        $disp_name,
        $self->get('order_id'),
    );
}

1;
