
# cpanel - Cpanel/Binaries/Debian/AptGet.pm        Copyright 2022 cPanel, L.L.C.
#                                                           All rights reserved.
# copyright@cpanel.net                                         http://cpanel.net
# This code is subject to the cPanel license. Unauthorized copying is prohibited

package Cpanel::Binaries::Debian::AptGet;

=head1 NAME

Cpanel::Binaries::Debian::AptGet

=head1 DESCRIPTION

Wrapper around the `apt-get binary.

=head1 SYNOPSIS

    my $bin = Cpanel::Binaries::Debian::AptGet->new();
    $bin->cmd( ... );
    ...

=head1 FUNCTIONS

=head2 bin_path()

Provide the path to apt-get binary.

=cut

use cPstrict;

use parent 'Cpanel::Binaries::Role::Debian';

=head2 bin_path

Returns the path to the binary on this system.

=cut

sub bin_path ($self) {
    return '/usr/bin/apt-get';
}

=head2 needs_lock

Allow exceptions to some calls that don't actually need exclusivity even if an (un)install is happening.

=cut

sub needs_lock ( $self, $action, @args ) {
    return 0 if grep { $action eq $_ } qw/ show check download changelog/;
    return 1;
}

1;
