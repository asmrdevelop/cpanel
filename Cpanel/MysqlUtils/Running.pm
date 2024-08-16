package Cpanel::MysqlUtils::Running;

# cpanel - Cpanel/MysqlUtils/Running.pm            Copyright 2022 cPanel, L.L.C.
#                                                           All rights reserved.
# copyright@cpanel.net                                         http://cpanel.net
# This code is subject to the cPanel license. Unauthorized copying is prohibited

use strict;
use warnings;

use Try::Tiny;

=encoding utf-8

=head1 NAME

Cpanel::MysqlUtils::Running - Determine if mysql is running.

=head1 SYNOPSIS

    use Cpanel::MysqlUtils::Running;

    my $is_running = Cpanel::MysqlUtils::Running::is_mysql_running();

=cut

=head2 is_mysql_running()

Determine if mysql is running right now.  This function is not cached.
If you need a cached result use Cpanel::MysqlRun::running() instead.

=over 2

=item Output

=over 3

Returns 0 if it’s not running.

Warns and returns 0 if we failed to determine if it’s running.

B<TODO:> Ideally we would throw an exception in this case. For new code,
please consider making a new function that doesn’t confuse the
“not-running” and “dunno” states.

Returns 1 if it is running.

=back

=back

=cut

sub is_mysql_running {

    require Cpanel::MysqlUtils::MyCnf::Basic;
    require Cpanel::MysqlUtils::Unprivileged;

    my $host = Cpanel::MysqlUtils::MyCnf::Basic::getmydbhost('root') || 'localhost';
    my $port = Cpanel::MysqlUtils::MyCnf::Basic::getmydbport('root');
    my $version;

    try {
        $version = Cpanel::MysqlUtils::Unprivileged::get_version_from_host( $host, $port );
    }
    catch {
        warn "Failed to determine MySQL state; we proceed as though the server were down. $_";
    };

    return $version ? 1 : 0;
}

my $_SLEEP_INTERVAL = 0.2;

=head2 wait_for_mysql_to_come_online($timeout_in_seconds)

Waits for mysql to come online up to $timeout_in_seconds
If the timeout is not specified, the default is 10 seconds.

=cut

sub wait_for_mysql_to_come_online {
    my ($timeout_in_seconds) = @_;
    $timeout_in_seconds ||= 10;

    require Cpanel::TimeHiRes;
    my $max_wait_time_in_sleep_interval = $timeout_in_seconds * ( 1 / $_SLEEP_INTERVAL );
    for ( 1 .. $max_wait_time_in_sleep_interval ) {
        return 1 if is_mysql_running();
        Cpanel::TimeHiRes::sleep($_SLEEP_INTERVAL);
    }
    warn if $@;
    return 0;
}

1;
