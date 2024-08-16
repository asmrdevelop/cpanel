package Cpanel::Binaries::Dnf;

# cpanel - Cpanel/Binaries/Dnf.pm                   Copyright 2022 cPanel, L.L.C.
#                                                            All rights Reserved.
# copyright@cpanel.net                                          http://cpanel.net
# This code is subject to the cPanel license.  Unauthorized copying is prohibited

=head1 NAME

Cpanel::Binaries::Dnf

=head1 DESCRIPTION

Wrapper around `dnf`.

=head1 SYNOPSIS

    my $bin = Cpanel::Binaries::Dnf->new();
    $bin->cmd( 'showpkg', 'package1' );
    ...

=cut

use cPstrict;

# sharing locks with Yum as yum is a shim on top of dnf...
use parent 'Cpanel::Binaries::Yum';

=head1 METHODS

=head2 bin_path($self)

Provides the path to the binary our parent SafeRunner should use.

=cut

sub bin_path ($self) {
    return '/usr/bin/dnf';
}

sub locks_to_wait_for {
    return (
        __PACKAGE__->SUPER::locks_to_wait_for(),
        qw{ /var/lib/dnf/rpmdb_lock.pid }
    );
}

1;
