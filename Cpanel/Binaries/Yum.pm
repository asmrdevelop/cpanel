package Cpanel::Binaries::Yum;

# cpanel - Cpanel/Binaries/Yum.pm      Copyright 2022 cPanel, L.L.C.
#                                                           All rights reserved.
# copyright@cpanel.net                                         http://cpanel.net
# This code is subject to the cPanel license. Unauthorized copying is prohibited

=head1 NAME

Cpanel::Binaries::Yum

=head1 DESCRIPTION

Wrapper around `yum`.

=head1 SYNOPSIS

    my $bin = Cpanel::Binaries::Yum->new();
    $bin->cmd( 'showpkg', 'package1' );
    ...

=cut

use cPstrict;

use parent 'Cpanel::Binaries::Role::Cmd';

=head1 METHODS

=head2 bin_path($self)

Provides the path to the binary our parent SafeRunner should use.

=cut

sub bin_path ($self) {
    return '/usr/bin/yum';
}

=head2 locks_to_wait_for($self)

Returns a list of lock path we should wait for before running a command.

=cut

sub locks_to_wait_for { return qw{/var/lib/rpm/.rpm.lock /var/run/yum.pid} }

=head2 lock_to_hold($self)

Name of the lock to hold if we need a lock to run the command.

=cut

sub lock_to_hold { return 'rpmdb' }

=head2 needs_lock ( $self, $action, @args )

Check if the current command needs to use a lock.
Returns a boolean.

=cut

sub needs_lock ( $self, $action, @args ) {
    return 0 if grep { $action eq $_ } qw/version repolist repo-pkgs provides list info history/;

    return 1;
}

1;
