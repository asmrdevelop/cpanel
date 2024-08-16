package Cpanel::Config::CpUser::Write;

# cpanel - Cpanel/Config/CpUser/Write.pm           Copyright 2022 cPanel, L.L.C.
#                                                           All rights reserved.
# copyright@cpanel.net                                         http://cpanel.net
# This code is subject to the cPanel license. Unauthorized copying is prohibited

use cPstrict;

=encoding utf-8

=head1 NAME

Cpanel::Config::CpUser::Write

=head1 DESCRIPTION

This module holds logic for writing cpuser files.

=cut

#----------------------------------------------------------------------

use Cpanel::Config::CpUser      ();
use Cpanel::Config::FlushConfig ();

#----------------------------------------------------------------------

=head1 FUNCTIONS

=head2 $str = serialize( \%CPUSER_DATA )

Returns a string representation of %CPUSER_DATA suitable for writing
to a cpuser file.

=cut

sub serialize ($cpuser_data) {
    die 'Pass data through clean_cpuser_hash() first!' if grep { ref } values %$cpuser_data;

    return ${
        Cpanel::Config::FlushConfig::serialize(
            $cpuser_data,
            do_sort   => 1,
            delimiter => '=',
            'header'  => $Cpanel::Config::CpUser::header,
        )
    };
}

1;
