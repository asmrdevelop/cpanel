package Cpanel::Binaries::Debian::AptFile;

# cpanel - Cpanel/Binaries/Debian/AptFile.pm       Copyright 2022 cPanel, L.L.C.
#                                                           All rights reserved.
# copyright@cpanel.net                                         http://cpanel.net
# This code is subject to the cPanel license. Unauthorized copying is prohibited

=head1 NAME

Cpanel::Binaries::Debian::AptFile

=head1 DESCRIPTION

Wrapper around `apt-file`.
Useful when you want something like yum or DNF's repoquery.

=head1 SYNOPSIS

    my $bin = Cpanel::Binaries::Debian::AptFile->new();
    my $packages_ar = $bin->what_provides( '/etc/ssh/ssh_config' );
    ...

=cut

use cPstrict;

use parent 'Cpanel::Binaries::Role::Debian';

=head1 METHODS

=head2 bin_path($self)

Provides the path to the binary our parent SafeRunner should use.

=cut

sub bin_path { return q[/usr/bin/apt-file] }

=head2 what_provides($search_term, %opts)

Returns ARRAYREF of package info HASHREFs corresponding to the matching
packages. If none are found, returns empty ARRAYREF.

NOTE: If you seek to look for a "partial" match, please pass in the
"allow_partial_matches" option.
option.

=cut

sub what_provides ( $self, $search_term, %opts ) {
    my @args = ('find');
    push @args, '--fixed-string' unless $opts{'allow_partial_matches'};
    my $run = $self->cmd( @args, $search_term );
    return [] if $run->{'status'};
    my @results = map { substr( $_, 0, index( $_, ": " ) ); } split( "\n", $run->{'output'} );
    return \@results;
}

1;
