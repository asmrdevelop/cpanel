package Cpanel::Args::Columns;

# cpanel - Cpanel/Args/Columns.pm                  Copyright 2022 cPanel, L.L.C.
#                                                           All rights reserved.
# copyright@cpanel.net                                         http://cpanel.net
# This code is subject to the cPanel license. Unauthorized copying is prohibited

use strict;

use parent qw(
  Cpanel::Args::Meta
);

use Cpanel::Args::Columns::Util ();

use constant _required_args => ();

#
#Expects:
#   - $self
#   - $columns_ar  Array ref of columns to keep
#   - $records_ar  Array ref of hashes usually from an API call
#   - $message_sr  Scalar ref of message in case we should report anything
#
#Returns:
#   - Modifies $records_ar to remove all keys that do not match a value found in $self->{"_columns"}
#
sub apply {
    my ( $self, $columns_ar, $records_ar, $message_sr, $invalid_columns_ar ) = @_;
    Cpanel::Args::Columns::Util::apply( $columns_ar, $records_ar, $message_sr, $invalid_columns_ar );

    return;
}

1;
