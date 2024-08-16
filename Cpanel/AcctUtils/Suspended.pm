package Cpanel::AcctUtils::Suspended;

# cpanel - Cpanel/AcctUtils/Suspended.pm           Copyright 2022 cPanel, L.L.C.
#                                                           All rights reserved.
# copyright@cpanel.net                                         http://cpanel.net
# This code is subject to the cPanel license. Unauthorized copying is prohibited

use strict;
use warnings;

=encoding utf-8

=head1 NAME

Cpanel::AcctUtils::Suspended - Determine if a cpanel user is suspended

=head1 SYNOPSIS

    use Cpanel::AcctUtils::Suspended;

    if ( Cpanel::AcctUtils::Suspended::is_suspended('bob') ) {
        ...
    }

=head1 DESCRIPTION

Determine if a cpanel user is suspended

=cut

=head2 is_suspended

Determine if a cpanel user is suspended

=head3 Input

$user - The user to determine the suspended status of

=head3 Output

C<SCALAR>

    true or false

=cut

# $user = $_[0]
sub is_suspended {
    return -e "/var/cpanel/suspended/$_[0]";
}

1;
