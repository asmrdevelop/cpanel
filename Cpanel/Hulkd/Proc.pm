package Cpanel::Hulkd::Proc;

# cpanel - Cpanel/Hulkd/Proc.pm                    Copyright 2022 cPanel, L.L.C.
#                                                           All rights reserved.
# copyright@cpanel.net                                         http://cpanel.net
# This code is subject to the cPanel license. Unauthorized copying is prohibited

use strict;
## no critic qw(TestingAndDebugging::RequireUseWarnings) - causes issues with cphulkd-dormant. see notes in PIG-3834.

use Cpanel::Proc::PID ();

my $pid_fh;

sub get_apps_to_start {
    my $hulk       = shift;        # optional, for logging
    my $launch_opt = shift || 0;

    my @applist = get_applist($launch_opt);
    my @apps;

    foreach my $app (@applist) {
        my $previous_pid = -e "/var/run/cphulkd_${app}.pid";
        if ($previous_pid) {
            if ( open my $pid_fh, '<', "/var/run/cphulkd_${app}.pid" ) {
                chomp( $previous_pid = readline($pid_fh) );
                close $pid_fh;
                chomp($previous_pid);

                if ( $previous_pid && $previous_pid != $$ && kill( 0, $previous_pid ) >= 1 ) {
                    local $@;
                    if ( my $cmdline = eval { Cpanel::Proc::PID->new($previous_pid)->cmdline() } ) {
                        $cmdline = "@$cmdline";

                        if ( $cmdline && $cmdline =~ m{hulk}i ) {
                            $hulk->warn("Hulkd ${app} is already running [PID $previous_pid]") if ref $hulk;
                            next;
                        }
                        else {
                            # if the pid is running and its not hulk we remove the pid file
                            $hulk->warn("Hulkd “${app}” with pid “$previous_pid” running unexpected command line “$cmdline”. Removing “/var/run/cphulkd_${app}.pid”.") if ref $hulk;
                            unlink "/var/run/cphulkd_${app}.pid";
                        }
                    }
                    else {
                        $hulk->warn("Failed to fetch examine “$app” previous pid “$previous_pid”: $@") if ref $hulk;
                    }
                }
            }

            # Do not unlink the pid file since we will overwrite them
            # later and this causes a race condition

        }
        push @apps, $app;
    }
    return \@apps;
}

sub write_pid_file {
    my ( $app, %opts ) = @_;

    # A previous call to this function, with the keep_open option set, would
    # have left the PID file open, so we'll need to close that before
    # proceeding.
    if ( $opts{'keep_open'} && defined $pid_fh ) {
        close $pid_fh;
        undef $pid_fh;
    }

    if ( open $pid_fh, '>', "/var/run/cphulkd_${app}.pid.$$" ) {
        syswrite( $pid_fh, "$$\n" );

        close $pid_fh unless $opts{'keep_open'};

        if ( rename( "/var/run/cphulkd_${app}.pid.$$", "/var/run/cphulkd_${app}.pid" ) ) {
            return 1;
        }
    }
    return;
}

sub get_applist {
    my ($apps_to_start) = @_;

    if ( ref $apps_to_start eq 'ARRAY' ) {
        return @{$apps_to_start};
    }

    return ( 'processor', 'dbprocessor' );    #start these by default
}

sub get_applist_ref {
    require Cpanel::Hulkd;
    return {
        'dbprocessor' => { 'code' => \&Cpanel::Hulkd::dbprocessor_run },
        'processor'   => { 'code' => \&Cpanel::Hulkd::processor_run }
    };
}

1;
