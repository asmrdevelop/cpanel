package Cpanel::Binaries::Debian::AptMark;

# cpanel - Cpanel/Binaries/Debian/AptMark.pm       Copyright 2022 cPanel, L.L.C.
#                                                           All rights reserved.
# copyright@cpanel.net                                         http://cpanel.net
# This code is subject to the cPanel license. Unauthorized copying is prohibited

=head1 NAME

Cpanel::Binaries::Debian::AptMark

=head1 DESCRIPTION

Wrapper around `apt-mark`

=head1 SYNOPSIS

    my $bin = Cpanel::Binaries::Debian::Apt::Mark->new();

    my $list = $bin->showhold();

    $bin->hold( 'a-package') or die;
    $bin->unhold( 'a-package') or die;

    ...

=cut

use cPstrict;

use parent 'Cpanel::Binaries::Role::Debian';

=head1 METHODS

=head2 bin_path($self)

Provides the path to the binary our parent SafeRunner should use.

=cut

sub bin_path { return q[/usr/bin/apt-mark] }

=head2 $bin->showhold()

Returns ARRAYREF of packages marked as hold.
If none are found, returns empty ARRAYREF.

=cut

sub showhold ($self) {
    my $run = $self->cmd('showhold');
    return [] if $run->{'status'};

    my @results = split( "\n", $run->{'output'} );
    return \@results;
}

=head2 $bin->hold( $pkg )

Mark a package as hold.
Return a boolean: true on success.

=cut

sub hold ( $self, $pkg ) {
    my $run = $self->cmd( 'hold', $pkg );
    return 0 if $run->{'status'};

    return 1;
}

=head2 $bin->unhold( $pkg )

Mark a package as unhold.
Return a boolean: true on success.

=cut

sub unhold ( $self, $pkg ) {
    my $run = $self->cmd( 'unhold', $pkg );
    return 0 if $run->{'status'};

    return 1;
}

1;
