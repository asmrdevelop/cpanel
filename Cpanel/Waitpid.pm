package Cpanel::Waitpid;

# cpanel - Cpanel/Waitpid.pm                       Copyright 2022 cPanel, L.L.C.
#                                                           All rights reserved.
# copyright@cpanel.net                                         http://cpanel.net
# This code is subject to the cPanel license. Unauthorized copying is prohibited

use strict;
use warnings;

#XXX DEPRECATED
#
#This module is no longer needed because waitpid() in modern perls
#is signal-safe. If you do use it, please consider putting “local $?”
#beforehand so that the change to $? won’t pollute global space, leading to
#difficult-to-debug breakages like CPANEL-18244.

sub sigsafe_blocking_waitpid {
    my ($pid) = @_;

    until ( ( my $child = waitpid( $pid, 0 ) ) == $pid ) {
        last if $child == -1;
    }
    return $? >> 8;
}

1;
