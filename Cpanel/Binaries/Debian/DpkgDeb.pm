package Cpanel::Binaries::Debian::DpkgDeb;

# cpanel - Cpanel/Binaries/Debian/DpkgDeb.pm     Copyright 2022 cPanel, L.L.C.
#                                                           All rights reserved.
# copyright@cpanel.net                                         http://cpanel.net
# This code is subject to the cPanel license. Unauthorized copying is prohibited

=head1 NAME

Cpanel::Binaries::Debian::DpkgDeb

=head1 DESCRIPTION

Interface to common dpkg-deb commands.


=head1 SYNOPSIS

    my $dpkg_query = Cpanel::Binaries::Deiban::DpkgDeb->new;
    $dpkg_query->query('/path/to/file.deb');
    ...

=cut

use cPstrict;

use parent 'Cpanel::Binaries::Role::Debian';

=head1 METHODS

=head2 bin_path($self)

Provides the binary our parent SafeRunner should use.

=cut

sub bin_path ($self) {

    return '/usr/bin/dpkg-deb';
}

=head2 needs_lock

This binary does not need a lock.

=cut

sub needs_lock ( $self, $action, @args ) {
    return 0;
}

=head2 query($file)

Extracts information about a deb file and returns the raw output.

=cut

sub query ( $self, $file ) {
    my $answer = $self->cmd( "--info", $file );

    # Yes we're ignoring the exit code here. What will we do it if it's non-zero?
    return $answer->{'output'} // '';
}

1;
