package Whostmgr::API::1::Data::Columns;

# cpanel - Whostmgr/API/1/Data/Columns.pm          Copyright 2022 cPanel, L.L.C.
#                                                           All rights reserved.
# copyright@cpanel.net                                         http://cpanel.net
# This code is subject to the cPanel license. Unauthorized copying is prohibited

use strict;
use warnings;

use Cpanel::Args::Columns::Util ();
use Cpanel::Locale::Lazy        ();

#Called via whostmgr/bin/xml-api.pl
#
#Expects:
#   - $args     Hash ref of key names to match and keep.  If $args->{'enable'} does not exist it will return to prevent duplicate filtering
#   - $records  Array ref of hashes usually from an API call
#   - $metadata Hash ref of current state of the API process.
#
#Returns:
#   - Nothing
#   - Modifies $records to remove all keys that do not match a value found in $args
#   - Removes $args->{'enable'} after the first time filter is run to prevent duplicate filtering.
#
sub apply {
    my ( $args, $records, $metadata ) = @_;

    #Expect 'enable' to be passed truthy - useful in case we hit this code multiple times
    return 1 if !$args->{'enable'};

    #We remove it so we don't double column filter
    delete $args->{'enable'};

    my @white_list_keys = values %$args;

    my $message_sr;
    my @invalid_columns = qw();

    Cpanel::Args::Columns::Util::apply( \@white_list_keys, $records, \$message_sr, \@invalid_columns );

    $metadata->{'columns'}{'invalid_msg'} = defined $message_sr ? $message_sr : Cpanel::Locale::Lazy::lh()->maketext("None");
    $metadata->{'columns'}{'invalid'}     = \@invalid_columns if @invalid_columns;

    return;
}

1;
