package Cpanel::Expect::Shell::Detect;

# cpanel - Cpanel/Expect/Shell/Detect.pm                 Copyright 2022 cPanel, L.L.C.
#                                                           All rights reserved.
# copyright@cpanel.net                                         http://cpanel.net
# This code is subject to the cPanel license. Unauthorized copying is prohibited

use cPstrict;

=encoding utf-8

=head1 NAME

Cpanel::Expect::Shell::Detect

=head1 DESCRIPTION

This module contains backend logic for L<Cpanel::Expect::Shell>
to detect the currently-active shell.

=cut

#----------------------------------------------------------------------

=head1 FUNCTIONS

=head2 via_proc_exe( $COMMAND_RUNNER_CR )

Passes a command (as a string) to $COMMAND_RUNNER_CR. This command
detects the shell via F</proc>’s C<exe> symlink.

$COMMAND_RUNNER_CR must return the output of the passed command,
in the same way as C<readpipe()>.

=cut

sub via_proc_exe ($cr) {

    # Use perl rather than readlink because we can know with greater
    # certainty that some perl interpreter lives at /usr/bin/perl.
    my @cmd = (
        '/usr/bin/perl',
        '-Mstrict',
        '-w',
        '-e',
        q<'print readlink "/proc/$ARGV[0]/exe"'>,
        '$$',
    );

    my $payload = $cr->("@cmd");

    if ( defined $payload ) {
        $payload =~ s<.*/><>;
    }

    return $payload;
}

=head2 via_proc_cmdline( $COMMAND_RUNNER_CR )

Like C<via_proc_exe()>, but the passed command detects the shell via
F</proc>’s C<cmdline>.

This also returns the invocation name (e.g., F<./bin/bash>), which may
or may not contain path information before the shell name.

=cut

sub via_proc_cmdline ($cr) {

    # Use perl rather than cat because we can know with greater
    # certainty that some perl interpreter lives at /usr/bin/perl.
    my @cmd = (
        '/usr/bin/perl',
        '-Mstrict',
        '-w',
        '-e',
        sprintf(
            q<'%s'>,
            join(
                q<; >,
                'open my $f, "<", "/proc/$ARGV[0]/cmdline" or die "open: $!"',
                'local $/',
                'print <$f>',
            )
        ),
        '$$',
    );

    my $s       = $cr->("@cmd");
    my @cmdline = split( /\0/, $s );
    return $cmdline[0];
}

1;
