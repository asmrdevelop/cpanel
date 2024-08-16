package Cpanel::Binaries::Gpg;

# cpanel - Cpanel/Binaries/Gpg.pm                  Copyright 2022 cPanel, L.L.C.
#                                                           All rights reserved.
# copyright@cpanel.net                                         http://cpanel.net
# This code is subject to the cPanel license. Unauthorized copying is prohibited

=head1 NAME

Cpanel::Binaries::Gpg

=head1 DESCRIPTION

Wrapper around `gpg`.

=head1 SYNOPSIS

    my $bin = Cpanel::Binaries::Gpg->new();
    my $answer = $bin->cmd( ... );
    say $answer->{output} if $answer->{status};
    ...

=cut

use cPstrict;

use parent 'Cpanel::Binaries::Role::Cmd';

=head1 METHODS

=head2 bin_path($self)

Provides the path to the binary our parent SafeRunner should use.

=cut

# Key fingerprint = 83D9 FE12 C401 AE53 434F  4889 CB0C 590A 361C D137
# cPanel Build Service (Official cPanel Signing Key) <release-team@cpanel.net>

use constant CPANEL_FINGERPRINT => q[83D9 FE12 C401 AE53 434F 4889 CB0C 590A 361C D137];

sub bin_path ($self) {
    return '/usr/bin/gpg';
}

=head2 is_file_signed_by_cpanel ( $self, $file )

Check if the file is signed by cPanel.

=cut

sub is_file_signed_by_cpanel ( $self, $file ) {

    my $answer = $self->cmd( '--verify', $file );

    # do not check status, if the key is not installed we cannot validate it
    return unless defined $answer->{output};

    my $key = CPANEL_FINGERPRINT;
    $key =~ s{\s}{}g;

    return $answer->{output} =~ qr{using RSA key \Q$key\E$}mi;
}

1;
