package Cpanel::Services::Env;

# cpanel - Cpanel/Services/Env.pm                  Copyright 2022 cPanel, L.L.C.
#                                                           All rights reserved.
# copyright@cpanel.net                                         http://cpanel.net
# This code is subject to the cPanel license. Unauthorized copying is prohibited

use strict;
use warnings;

=encoding utf-8

=head1 NAME

Cpanel::Services::Env

=head1 SYNOPSIS

    setup_env_for_starting_a_daemon();

=head1 DESCRIPTION

Logic for controlling the environment for services.

=cut

use Cpanel::Timezones ();

=head1 FUNCTIONS

=head2 setup_env_for_starting_a_daemon()

Tidies up the environment variables and does C<chdir()> to F</>.

=cut

sub setup_env_for_starting_a_daemon {
    require Cpanel::Env;
    Cpanel::Env::clean_env( 'keep' => [ 'CPANEL', 'WHM50', 'WHMLITE', 'MYSQLCCHK', 'USERNAME', 'PATH', 'LANG', 'LANGUAGE', 'LC_MESSAGES' ] );

    delete $ENV{'TMP'};
    delete $ENV{'TEMP'};

    $ENV{'HOME'}       = '/root';
    $ENV{'USER'}       = 'root';
    $ENV{'RESTARTSRV'} = 1;
    $ENV{'TZ'}         = Cpanel::Timezones::calculate_TZ_env();

    chdir('/') || die "Failed to chdir() to “/” because of an error: $!";    # For security reasons we want to make sure
                                                                             # that this script is not called from a users's
                                                                             # directory as root by an unsuspecting sysadmin.

    return;
}

1;
