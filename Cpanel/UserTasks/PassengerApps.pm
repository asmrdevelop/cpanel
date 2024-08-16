package Cpanel::UserTasks::PassengerApps;

# cpanel - Cpanel/UserTasks/PassengerApps.pm       Copyright 2022 cPanel, L.L.C.
#                                                           All rights reserved.
# copyright@cpanel.net                                         http://cpanel.net
# This code is subject to the cPanel license. Unauthorized copying is prohibited

use cPstrict;

use Cpanel::SafeRun::Object ();
use Cpanel::Time::ISO       ();
use File::Path::Tiny        ();
use Cpanel::PwCache         ();
use Cpanel::JSON            ();

sub ensure_deps {
    my ( $class, $args ) = @_;
    my $homedir = Cpanel::PwCache::gethomedir() || die "Could not determine home directory: $!\n";

    my $fh = _user_task_do_log_file( $args->{log_file} //= "ensure_deps.log" );    # This is gross, see CPANEL-26038

    require Cwd;
    my $cwd = Cwd::cwd() || die "Could not determine starting path: $!\n";         # Prevent undef $cwd because chdir(undef) is equivalent to chdir($ENV{HOME})

    local $SIG{__DIE__} = sub { chdir($cwd) or warn "Could not go back into the starting path: $!\n"; };    # for eval()ers

    chdir("$homedir/$args->{app_path}") || die "Could not operate on given path: $!\n";

    my $cmd_ar = Cpanel::JSON::Load( $args->{cmd_json} );
    my $rv     = _user_task_run_cmd_to_logfh( [ @{$cmd_ar} ], $fh );                                        # This is gross, see CPANEL-26038

    chdir($cwd) || die "Could not go back into the starting path: $!\n";

    die "$cmd_ar->[0] failed" if !$rv;

    return $rv;
}

##############
#### helper ##
##############

sub _user_task_run_cmd_to_logfh {
    my ( $cmd_ar, $log_fh ) = @_;    # CPANEL-26038 could also accept a code referenc that is sporked off to the $log_fh that does the usertask processing strings

    my $prog = shift @{$cmd_ar};
    my @args = @{$cmd_ar};
    my $run  = Cpanel::SafeRun::Object->new(
        program => $prog,
        args    => \@args,
        stdout  => $log_fh,
        stderr  => $log_fh,
    );

    my $code = $run->error_code() || 0;
    my $fail = $code ? "FAILURE: " : "";

    my $now = Cpanel::Time::ISO::unix2iso();

    my $status_msg = "$now: ${fail}Task completed with exit code $code\n";

    warn $status_msg;               # adding the message to the user_task_runner.log file which is the one used... to parse the task.
    print {$log_fh} $status_msg;    # CPANEL-26038 Cpanel::UserTasks->add should do this so that tasks don't have to know the internals (in this case a special string it looks for in the the log file)
    close $log_fh;

    return 1 if $code == 0;
    return;
}

sub _user_task_do_log_file {
    my ($log_file) = @_;

    # CPANEL-26038 Cpanel::UserTasks->add should do all of this for us
    die "log_file must be just the file name\n" if !defined $log_file || !length $log_file || $log_file =~ m{(?:[/\0]|\.\.)};    # yes the file could be ..foo but that is just silly, KISS

    my $homedir = Cpanel::PwCache::gethomedir() || die "Could not determine home directory: $!\n";

    File::Path::Tiny::mk("$homedir/.cpanel/logs") || die "Could not create $homedir/.cpanel/logs: $!\n";

    # Cpanel::UserTasks could add the task id to the name instead of time() (we don’t have access to the id at this point)
    my $path = "$homedir/.cpanel/logs/" . $log_file;
    open( my $fh, ">", $path ) or die "Could not create log file $path: $!\n";

    return $fh;
}

sub sse_process_log ( $sse_usertask, $log_raw ) {

    return unless length $log_raw;

    my @lines = split( "\n", $log_raw );

    foreach my $line (@lines) {

        next unless $line =~ qr{Task completed with exit code};

        if ( $line =~ m/FAILURE/ ) {
            $sse_usertask->send_task_failed();
        }
        else {
            $sse_usertask->send_task_complete();
        }

        return 1;    # time to quit
    }

    return;          # returns 1 -> time to quit
}

1;

__END__

=encoding utf-8

=head1 ensure_deps()

Run command that will ensure an application’s dependencies are installed.

Takes a hashref that matches the first argument of C<ensure_deps()> in L<Cpanel::API::PassengerApps>.

Return void.

Dies if the path or type is invalid.
