package Cpanel::Rand::Path;

# cpanel - Cpanel/Rand/Path.pm                     Copyright 2022 cPanel, L.L.C.
#                                                           All rights reserved.
# copyright@cpanel.net                                         http://cpanel.net
# This code is subject to the cPanel license. Unauthorized copying is prohibited

=encoding utf-8

=head1 NAME

Cpanel::Rand::Path

=head1 SYNOPSIS

    my $tmp_file = Cpanel::Rand::Path::get_tmp_path('/path/to/base');

=cut

use strict;

use Cpanel::Rand::Get ();

sub get_tmp_path {
    my ($base) = @_;

    return join(
        '.',
        $base,
        'tmp',
        Cpanel::Rand::Get::getranddata(12),
        $$,
        time,
    );
}

1;
