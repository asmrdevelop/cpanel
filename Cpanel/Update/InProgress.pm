package Cpanel::Update::InProgress;

# cpanel - Cpanel/Update/InProgress.pm             Copyright 2022 cPanel, L.L.C.
#                                                           All rights reserved.
# copyright@cpanel.net                                         http://cpanel.net
# This code is subject to the cPanel license. Unauthorized copying is prohibited

use strict;
use warnings;

=encoding utf-8

=head1 NAME

Cpanel::Update::InProgress - touch file for in-progress cP/WHM update

=head1 DISCUSSION

See L<Cpanel::Config::TouchFileBase>’s documentation for usage examples.
Note that this module won’t C<set_on()>; you can only C<set_off()> and
check C<is_on()>. This is because this module’s file comes from
the software distribution rather than the code base.

=cut

use parent qw( Cpanel::Config::TouchFileBase );

#overridden in tests
our $_PATH = '/usr/local/cpanel/upgrade_in_progress.txt';

sub _TOUCH_FILE { return $_PATH }

sub set_on { die 'Refuse to create!' }

sub is_on {
    my ($class) = @_;

    require Cpanel::Logger;
    return 0 if Cpanel::Logger->is_sandbox();
    return $class->SUPER::is_on();
}

1;
