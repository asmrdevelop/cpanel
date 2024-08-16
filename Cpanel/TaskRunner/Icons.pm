package Cpanel::TaskRunner::Icons;

# cpanel - Cpanel/TaskRunner/Icons.pm              Copyright 2022 cPanel, L.L.C.
#                                                           All rights reserved.
# copyright@cpanel.net                                         http://cpanel.net
# This code is subject to the cPanel license. Unauthorized copying is prohibited

use cPstrict;

=encoding utf-8

=head1 NAME

Cpanel::TaskRunner::Icons

=head1 SYNOPSIS

    my $stripped = Cpanel::TaskRunner::Icons::strip_icon( $message );

=head1 DESCRIPTION

This module contains normalized logic for icons in L<Cpanel::TaskRunner>’s
output.

=cut

#----------------------------------------------------------------------

=head1 GLOBAL VARIABLES

=head2 %ICON

Contains:

=over

=item * C<start_step> - The icon to use at the start of a step.

=item * C<warning> - The icon to use to indicate a warning.

=item * C<error> - The icon to use to indicate an error.

=back

=cut

our %ICON;

BEGIN {
    %ICON = (
        start_step => '•',
        warning    => '⚠',
        error      => '⛔',
    );
}

#----------------------------------------------------------------------

=head1 FUNCTIONS

=head2 $stripped = strip_icon( $MESSAGE )

Trims any leading icon from this module (plus its trailing whitespace)
from the start of the given $MESSAGE. Returns the result.

=cut

sub strip_icon ($message) {
    state $icons_re = join '|', values %ICON;

    return $message =~ s<\A(?:$icons_re)\s+><>r;
}

1;
