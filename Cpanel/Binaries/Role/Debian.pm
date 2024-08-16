package Cpanel::Binaries::Role::Debian;

# cpanel - Cpanel/Binaries/Role/Debian.pm          Copyright 2022 cPanel, L.L.C.
#                                                           All rights reserved.
# copyright@cpanel.net                                         http://cpanel.net
# This code is subject to the cPanel license. Unauthorized copying is prohibited

=head1 NAME

Cpanel::Binaries::Role::Debian

=head1 DESCRIPTION

Abstract class for debian binaries

=cut

use cPstrict;

use parent 'Cpanel::Binaries::Role::Cmd';

sub _setup_envs ($self) {
    my $env = $self->SUPER::_setup_envs;

    $env->{'DEBIAN_FRONTEND'} = 'noninteractive';
    $env->{'DEBIAN_PRIORITY'} = 'critical';

    return $env;
}

=head2 locks_to_wait_for

Returns the debian related lock files which other system binaries might be holding.

=cut

sub locks_to_wait_for {
    return qw{
      /var/lib/dpkg/lock
      /var/lib/dpkg/lock-frontend
      /var/cache/apt/archives/lock
      /var/lib/apt/lists/lock
      /run/unattended-upgrades.lock
    };
}

=head2 lock_to_hold

we use an easylock file to prevent other cpanel procs from breaking when we run at the same time.

=cut

sub lock_to_hold { return 'apt' }

1;
