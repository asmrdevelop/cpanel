package Cpanel::ExitValues::tar;

# cpanel - Cpanel/ExitValues/tar.pm                Copyright 2022 cPanel, L.L.C.
#                                                           All rights reserved.
# copyright@cpanel.net                                         http://cpanel.net
# This code is subject to the cPanel license. Unauthorized copying is prohibited

=pod

=encoding utf-8

=head1 NAME

Cpanel::ExitValues::tar - exit values utility for the GNU “tar” utility

=head1 SYNOPSIS

    use Cpanel::ExitValues::tar ();

    my $exit_val = 1;

    if (!grep { $_ eq $exit_val } @Cpanel::ExitValues::tar::CPANEL_NONFATAL_ERROR_CODES) {
        my $pretty_err = Cpanel::ExitValues::tar->number_to_string($exit_val);
    }

=cut

use strict;

use parent qw(
  Cpanel::ExitValues
);

#These are error codes that cPanel deems not to be error conditions.
#
sub _CPANEL_NONFATAL_ERROR_CODES {
    return (1);
}

#cf. https://www.gnu.org/software/tar/manual/tar.html#SEC33
sub _numbers_to_strings {
    return (
        0 => 'Successful termination',
        1 => 'Some files differ',
        2 => 'Fatal error',
    );
}

1;
