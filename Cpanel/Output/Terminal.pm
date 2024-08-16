package Cpanel::Output::Terminal;

# cpanel - Cpanel/Output/Terminal.pm               Copyright 2022 cPanel, L.L.C.
#                                                           All rights reserved.
# copyright@cpanel.net                                         http://cpanel.net
# This code is subject to the cPanel license. Unauthorized copying is prohibited

use strict;
use warnings;

=encoding utf-8

=head1 NAME

Cpanel::Output::Terminal - standards for terminal output

=head1 DESCRIPTION

This module contains logic that’s useful in all terminal-output contexts
for cPanel & WHM.

=head1 CONSTANTS

=over

=item * C<COLOR_SUCCESS> - A color string to give to L<Term::ANSIColor> to
colorize a string to indicate success.

=item * C<COLOR_WARN> - ^^ Same, but for warnings rather than successes.

=item * C<COLOR_ERROR> - ^^ Same, but for errors.

=back

=cut

#----------------------------------------------------------------------

use constant {
    COLOR_SUCCESS => 'bold green',
    COLOR_WARN    => 'bold bright_yellow on_grey6',
    COLOR_ERROR   => 'bold bright_red on_grey6',
};

1;
