package Whostmgr::API::1::Data::Utils;

# cpanel - Whostmgr/API/1/Data/Utils.pm            Copyright 2022 cPanel, L.L.C.
#                                                           All rights reserved.
# copyright@cpanel.net                                         http://cpanel.net
# This code is subject to the cPanel license. Unauthorized copying is prohibited

use strict;

# This is a pretty rudimentary way to drill down into a nested data structure.
# The idea is to separate steps with periods (.).  Hash keys are the literal
# names.  Array indices use standard bracket notation ([n]).

my @RESERVED_IDS = qw(enable verbose filter filtered);

sub evaluate_fieldspec {
    my ( $fieldspec, $record_ref ) = @_;
    my @steps   = split( /\./, $fieldspec );
    my $current = $record_ref;
    foreach my $step (@steps) {
        if ( $step =~ m/^\[(\d+)\]$/ ) {
            return if 'ARRAY' ne ref $current;
            $current = $current->[$1];
        }
        else {
            return if 'HASH' ne ref $current;
            $current = $current->{$step};
        }
    }

    return $current;
}

sub fieldspec_is_valid {
    return ( length $_[0] && $_[0] =~ m/^[a-z0-9_]+(\.([a-z0-9_]+|\[\d+\]))*$/i ) ? 1 : 0;
}

sub id_is_valid {
    return 0 if !length $_[0];
    return 0 if grep { $_[0] eq $_ } @RESERVED_IDS;
    return ( $_[0] =~ m/^[a-z][a-z0-9_]*$/i ) ? 1 : 0;
}

1;
