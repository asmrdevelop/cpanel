package Cpanel::Api2::Columns;

# cpanel - Cpanel/Api2/Columns.pm                  Copyright 2022 cPanel, L.L.C.
#                                                           All rights reserved.
# copyright@cpanel.net                                         http://cpanel.net
# This code is subject to the cPanel license. Unauthorized copying is prohibited

use strict;
use warnings;

use Cpanel::Args::Columns::Util ();

#Modifies $rDATA to remove all keys that do not match a value found in
# one of the $rCFG->{'api2_columns_*'} values.  Will also set
# Status->invalid_columns_str to string alerting of unmatched columns
#
#Expects:
#   - $rCFG   Hash ref containing keys like qr/\Aapi2_columns_.+/
#   - $rDATA  Array ref of hashes usually from an API call
#   - $status Hash ref of status we use to pass message to API caller
#
#Returns are redundant but consistent with preexisting Cpanel::Api2::* modules:
#   - scalar context: altered $rDATA
#   - list context:   a list of the altered @$rDATA
#
sub apply {
    my ( $rCFG, $rDATA, $status ) = @_;

    my @white_list_keys = map { rindex( $_, 'api2_columns_', 0 ) == 0 ? $rCFG->{$_} : () } keys %$rCFG;
    my $message_sr;
    my @invalid_columns = qw();

    Cpanel::Args::Columns::Util::apply( \@white_list_keys, $rDATA, \$message_sr, \@invalid_columns );

    $status->{'invalid_columns_str'} = $message_sr       if $message_sr;
    $status->{'invalid_columns'}     = \@invalid_columns if @invalid_columns;
    return wantarray ? @$rDATA : $rDATA;
}

1;
