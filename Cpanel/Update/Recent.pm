package Cpanel::Update::Recent;

# cpanel - Cpanel/Update/Recent.pm                 Copyright 2022 cPanel, L.L.C.
#                                                           All rights reserved.
# copyright@cpanel.net                                         http://cpanel.net
# This code is subject to the cPanel license. Unauthorized copying is prohibited

use cPstrict;

=encoding utf-8

=head1 NAME

Cpanel::Update::Recent

=head1 SYNOPSIS

    if ( Cpanel::Update::Recent::upgraded_within_last_days() ) {
        ...
    }

    if ( Cpanel::Update::Recent::upgraded_within_last_days(10) ) {
        ...
    }

    if ( Cpanel::Update::Recent::installed_with_last_days() ) {
        ...
    }

    if ( Cpanel::Update::Recent::installed_with_last_days(10) ) {
        ...
    }


=head1 DESCRIPTION

Logic for determining whether the system was “recently” updated
or installed.

=head1 FUNCTIONS

=cut

use Cwd ();

use constant SECONDS_PER_DAY => 86_400;

use constant INSTALL_TIME_FILE => "/var/log/cpanel-install.log";
use constant UPDATE_FLAG_FILE  => "/var/cpanel/updatelogs/last";

=head2 upgraded_within_last_days( DAYS = 10 )

Returns a boolean to indicate whether the system
was upgraded within the last DAYS days.

=cut

sub upgraded_within_last_days ( $days = 10 ) {

    return unless -l UPDATE_FLAG_FILE;

    my $last_log_file = Cwd::abs_path(UPDATE_FLAG_FILE);
    return unless defined $last_log_file;

    my $update_mtime = ( stat($last_log_file) )[9] // 0;

    return unless $update_mtime;

    my $period_in_seconds = SECONDS_PER_DAY() * $days;

    my $now                  = _now();
    my $seconds_since_update = ( $now - $update_mtime );

    return $seconds_since_update < $period_in_seconds;
}

=head2 installed_with_last_days( DAYS = 10 )

Returns a boolean to indicate whether the system
was installed within the last DAYS days.

=cut

sub installed_with_last_days ( $days = 10 ) {

    my $now = _now();

    # Checking the install log file is what we do in Cpanel::Update::Gatherer;
    # however it may not be the most reliable as the admin may reinstall or
    # delete the file.
    #
    # If we don't have the install log file we will assume we haven't
    # installed in the last 10 days.
    my $install_mtime = ( stat(INSTALL_TIME_FILE) )[9] // 0;

    return unless $install_mtime;

    my $period_in_seconds = SECONDS_PER_DAY() * $days;

    my $seconds_since_install = ( $now - $install_mtime );
    return $seconds_since_install < $period_in_seconds;
}

sub _now { return scalar time() }    # for tests

1;
