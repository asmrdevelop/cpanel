package Cpanel::Services::Command;

# cpanel - Cpanel/Services/Command.pm                Copyright 2022 cPanel L.L.C.
#                                                           All rights reserved.
# copyright@cpanel.net                                         http://cpanel.net
# This code is subject to the cPanel license. Unauthorized copying is prohibited

use strict;
use warnings;

=encoding utf-8

=head1 NAME

Cpanel::Services::Command - Utilities for processing service command lines

=head2 should_ignore_this_command($command)

Check a command string to see if should be used to validate is a service
is online or offline.

=cut

sub should_ignore_this_command {
    my ($command) = @_;

    # ignore tailwatchd subprocesses
    return 1 if index( $command, 'tailwatchd - ' ) > -1 && $command =~ m{\btailwatchd - [A-Za-z]};

    # ignore other dovecot processes
    return 1 if index( $command, 'dovecot/' ) > -1 && $command =~ m{\bdovecot/(?:anvil|log|pop|config|lmtp|imap|auth)\b};

    # Exclude false matches
    if ( index( $command, 'start' ) > -1 || index( $command, 'stop' ) > -1 ) {
        return 1 if $command =~ m{^(?:start|stop)\S+};
        return 1 if $command =~ m{/(?:start|stop)\S+};
    }
    return 1 if index( $command, 'checkstatus' ) > -1;
    return 1 if index( $command, 'restartsrv' ) > -1;
    return 1 if index( $command, 'chkservd' ) > -1;
    return 1 if index( $command, 'rpm ' ) > -1;

    return 1 if index( $command, 'systemctl ' ) > -1;

    # ignore perl scripts but DON'T ignore spamd
    if ( index( $command, 'perl' ) > -1 && $command !~ m{/3rdparty(?:/perl/[0-9]+)?/bin/spamd} ) {
        return 1 if $command =~ m/perl\s+.*\/scripts/;
        return 1 if $command =~ m/perl\s+.*\/usr\/local\/cpanel/;
    }

    # Be nice with dev's editors
    return 1 if index( $command, 'vi ' ) > -1;
    return 1 if index( $command, 'nano ' ) > -1;
    return 1 if index( $command, 'vim ' ) > -1;
    return 1 if index( $command, 'emacs ' ) > -1;

    return 0;
}
1;
