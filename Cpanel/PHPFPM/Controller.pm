package Cpanel::PHPFPM::Controller;

# cpanel - Cpanel/PHPFPM/Controller.pm             Copyright 2022 cPanel, L.L.C.
#                                                           All rights reserved.
# copyright@cpanel.net                                         http://cpanel.net
# This code is subject to the cPanel license. Unauthorized copying is prohibited

use strict;
use warnings;

use Cpanel::OS                ();
use Cpanel::SafeRun::Object   ();
use Cpanel::PHPFPM::Constants ();    # PPI NO PARSE - It is being used
use Cpanel::ProcessInfo       ();
use Cpanel::Debug             ();

=head1 NAME

Cpanel::PHPFPM::Controller

=head1 SYNOPSIS

Module for 'controlling' our Apache PHP-FPM daemon master processes for various ea-php versions.

=head1 DESCRIPTION

    use Cpanel::PHPFPM::Controller ();
    my $restarted = 0;
    local $@;
    eval { $restarted = defined( Cpanel::PHPFPM::Controller::process_action( '56', 'restart_gracefully' ) ); };
    warn $@ if $@;
    ... # Do something else after restarting it perhaps

=head1 SUBROUTINES

=cut

#######################################################################
# Utility functions
#######################################################################

=head2 process_action

Processes an action that affects a PHP-FPM worker pool.

Accepts two arguments:
* VERSION - scalar value indicating an ea-php version.
* ACTION  - what you want to do (supported actions are 'start', 'stop', 'restart' and 'restart_gracefully').

Returns 0 on bad user input, dies if PHP-FPM fails to start/restart/restart_gracefully and returns undef on success.

=cut

# determine whether systemctl or init system, do the needful

my $action_message;

sub process_action {
    my ( $version, $action ) = @_;

    if ( $action ne 'start' and $action ne 'restart' and $action ne 'stop' and $action ne 'restart_gracefully' ) {
        warn "Unknown action to _process_action() [ $action ] [ $version ] . We only allow start, restart, restart_gracefully and stop\n";
        return 0;
    }

    # Just return if there's nothing to start for this version
    return if ( $action ne 'stop' && !phpfpm_version_users_configured($version) );

    if ( $action eq 'restart_gracefully' ) {

        # this can only be restarted gracefully if it is
        # already running
        my $pid = get_pid_from_version($version);
        if ($pid) {
            my $pid_exe;

            local $@;
            warn if !eval { $pid_exe = Cpanel::ProcessInfo::get_pid_exe($pid); 1 };

            if ( $pid_exe && index( $pid_exe, 'php-fpm' ) != -1 ) {
                kill( 'USR2', $pid );

                # EA-8697/CPANEL-29985: There is a bug in PHP 5x where an attempt to reload
                # will cause the process to die if there are a large number of pools.
                # Check if this has happened, if so, trigger a full restart
                if ( $version =~ /^5/ ) {
                    sleep 1;
                    $pid    = get_pid_from_version($version);
                    $action = 'restart' unless $pid;
                }
            }
            else {
                # Executable for PID $pid doesn't look right -- Just do a hard restart to be safe
                $action = 'restart';
            }
        }
        else {

            # This means we can't find the FPM master process pid for ea-php$version, so fall back to a hard restart
            $action = 'restart';
        }
    }

    my $action_result;
    if ( grep { $action eq $_ } qw{start stop restart} ) {

        # Setting this in the namespace level requires undef'ing it here, as we set it in the called subs.
        undef $action_message;
        $action_result = Cpanel::OS::is_systemd() ? systemctl_action( $version, $action ) : init_script_action( $version, $action );
    }

    # Ok. Now that we've told it to restart, let's check if it is running now.
    # Not needed if we're stopping it, obviously
    if ( $action ne 'stop' ) {

        # If the $action is not stop, yet also is not start or restart, then it is going to be 'restart_gracefully' to be meaningful in code.
        # As such, key on that and whether the systemd action for start/stop/restart processed successfully before bothering with PID checks.
        if ( $action eq 'restart_gracefully' || $action_result ) {
            require Cpanel::TimeHiRes;
            my $pid;
            my $ctr = 0;

            # Wait up to a maximum of 10s.
            # use $Cpanel::Debug::Level to check for $ENV{'CPANEL_DEBUG_LEVEL'} as otherwise it is scrubbed *after BEGIN*
            print "Waiting up to 10s for PHP-FPM Version $version to be ready...\n" if $Cpanel::Debug::level;
            while ( !( $pid = get_pid_from_version($version) ) && $ctr++ < 100 ) {
                Cpanel::TimeHiRes::sleep(0.1);
            }
            if ($pid) {
                my $pid_exe;

                local $@;
                warn if !eval { $pid_exe = Cpanel::ProcessInfo::get_pid_exe($pid); 1 };

                if ( $pid_exe && $pid_exe =~ m/php-fpm/ ) {
                    return undef;
                }
            }
        }
        die $action_message ? $action_message : "PHP-FPM Version $version failed to start\n";
    }
    return;
}

=head2 systemctl_action

Runs the relevant systemd script for restarting the PHP-FPM pool in question.

Accepts two arguments:
* VERSION - scalar value indicating an ea-php version.
* ACTION  - what you want to do (supported actions are 'start', 'stop', 'restart' and 'restart_gracefully').

Returns 1 regardless of the outcome.

=cut

sub systemctl_action {
    my ( $version, $action ) = @_;
    my $service = 'ea-php' . $version . '-php-fpm';
    my $run     = Cpanel::SafeRun::Object->new( 'program' => '/usr/bin/systemctl', 'args' => [ $action, $service ] );
    if ( $run->CHILD_ERROR() ) {
        my $msg        = join( q< >, map { $run->$_() // () } qw( autopsy stdout stderr ) );
        my $status_run = Cpanel::SafeRun::Object->new( 'program' => '/usr/bin/systemctl', 'args' => [ 'status', "$service" ] );    # ea-php56-php-fpm.service
        my $status_msg = join( q< >, map { $status_run->$_() // () } qw( stdout stderr ) );

        $action_message = "Failed to perform action “$action” for php-fpm “$version”: $msg: $status_msg";
        return 0;
    }

    return 1;
}

=head2 init_script_action

Runs the relevant system V init script for restarting the PHP-FPM pool in question.

Accepts two arguments:
* VERSION - scalar value indicating an ea-php version.
* ACTION  - what you want to do (supported actions are 'start', 'stop', 'restart' and 'restart_gracefully').

Returns 1 regardless of the outcome.

=cut

sub init_script_action {
    my ( $version, $action ) = @_;
    my $run = Cpanel::SafeRun::Object->new( 'program' => '/etc/init.d/ea-php' . $version . '-php-fpm', 'args' => [$action] );
    if ( $run->CHILD_ERROR() ) {
        my $msg = join( q< >, map { $run->$_() // () } qw( autopsy stdout stderr ) );
        $action_message = "Failed to perform action “$action” for php-fpm “$version”: $msg";
        return 0;
    }
    return 1;
}

=head2 restart_version

Wrapper for process_action that only requires passing in a version. 'restart' is explicitly set as the second argument.
Otherwise this sub does exactly the same thing and returns the same way.

=cut

sub restart_version {
    my ($version) = @_;
    process_action( $version, 'restart' );
    return;
}

=head2 get_phpfpm_versions

Returns an ARRAYREF of whatever versions of ea-php* are able to use PHP-FPM.

=cut

# Finds versions of ea-php available on the filesystem
sub get_phpfpm_versions {
    my @versions;
    if ( opendir( my $optcpanel_dh, ${Cpanel::PHPFPM::Constants::opt_cpanel} ) ) {
        my @files = readdir($optcpanel_dh);
        foreach my $file (@files) {
            if ( $file =~ m/ea\-php(\d{2})/ ) {

                # Look for config and binary (config can still exist after rpm removed, but is still required to provide functional service)
                if ( -f ${Cpanel::PHPFPM::Constants::opt_cpanel} . '/' . $file . '/root/etc/php-fpm.conf' and -f ${Cpanel::PHPFPM::Constants::opt_cpanel} . '/' . $file . '/root/usr/sbin/php-fpm' ) {
                    push( @versions, $1 );
                }
            }
        }
        close($optcpanel_dh);
    }
    return \@versions;
}

=head2 get_pid_from_version

Returns SCALAR value of a PID corresponding to the passed in $version SCALAR value (if it exists).
If it cannot be found, the subroutine returns undef.

=cut

# Given a phpfpm version, returns the current pid in it's configured pidfile, if it has one
sub get_pid_from_version {
    my ($version) = @_;
    my $pid;
    if ( open( my $fpmconf_fh, '<', ${Cpanel::PHPFPM::Constants::opt_cpanel} . '/ea-php' . $version . '/root/etc/php-fpm.conf' ) ) {
        while ( my $line = <$fpmconf_fh> ) {
            if ( $line =~ m/^pid\s*=\s*(\/.*\.pid)$/ ) {
                my $pid_file_path = $1;
                if ( open( my $pid_file_fh, '<', $pid_file_path ) ) {
                    $pid = <$pid_file_fh>;
                    close($pid_file_fh);
                }
            }
        }
    }
    return $pid;
}

=head2 phpfpm_version_users_configured

Returns a count of users currently configured to be using PHP-FPM for the passed in ea-php version.

=cut

# Given a phpfpm version, returns number of users configured for it to run
sub phpfpm_version_users_configured {
    my ($version) = @_;

    # We might get $version as just the numbers like 55, 99, 70, etc, or a full string, like ea-php55, ea-php99 or ea-php70
    if ( $version =~ m/ea-php(\d+)/ ) {
        $version = $1;
    }
    my $count = 0;

    if ( opendir( my $user_confs_dir, ${Cpanel::PHPFPM::Constants::opt_cpanel} . '/ea-php' . $version . '/root/etc/php-fpm.d/' ) ) {
        $count = scalar grep { length $_ > 5 && substr( $_, -5 ) eq '.conf' } readdir($user_confs_dir);
    }
    return $count;
}

=head2 get_phpfpm_versions_in_use

Returns a list of each installed version of php that at least one domain is configured to use.

=cut

sub get_phpfpm_versions_in_use {
    my @versions;

    # First get a list of all versions of php on this system.
    for my $ver ( @{ get_phpfpm_versions() } ) {

        # Now see if anyone is using that version right now.
        if ( phpfpm_version_users_configured($ver) > 0 ) {
            push( @versions, $ver );
        }
    }
    return \@versions;
}

=head1 SEE ALSO

Cpanel::Server::FPM::Manager -- If you were looking for a similar module, but one that affects the 'cpanel' FPM service instead of Apache's, that's your best bet.

=cut

1;
