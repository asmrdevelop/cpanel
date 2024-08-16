package Cpanel::Daemonizer::Simple;

# cpanel - Cpanel/Daemonizer/Simple.pm             Copyright 2022 cPanel, L.L.C.
#                                                           All rights reserved.
# copyright@cpanel.net                                         http://cpanel.net
# This code is subject to the cPanel license. Unauthorized copying is prohibited

use strict;
use warnings;

=encoding utf-8

=head1 NAME

Cpanel::Daemonizer::Simple - A simple utility method to allow scripts to run in the background

=head1 SYNOPSIS

    use Cpanel::Daemonizer::Simple;

    Cpanel::Daemonizer::Simple::daemonize();

=head1 DESCRIPTION

This module provides a basic utility method to allow scripts to run themselves in the background

=head1 FUNCTIONS

=head2 daemonize()

Make the current process run in the background

=over

=item Input

=over

None

=back

=item Output

=over

None

=back

=back

=cut

sub daemonize {
    require Cpanel::Sys::Setsid;
    require Cpanel::CloseFDs;
    require Cpanel::FileUtils::Open;
    require Cpanel::ConfigFiles;
    Cpanel::Sys::Setsid::full_daemonize();
    Cpanel::CloseFDs::fast_daemonclosefds();
    Cpanel::FileUtils::Open::sysopen_with_real_perms( \*STDERR, $Cpanel::ConfigFiles::CPANEL_ROOT . '/logs/error_log', 'O_WRONLY|O_APPEND|O_CREAT', 0600 );
    open( \*STDOUT, '>&', \*STDERR ) || die "Failed to redirect STDOUT to STDERR";
    return;
}

1;
