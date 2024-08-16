package Cpanel::Unix::PID::Tiny;

# cpanel - Cpanel/Unix/PID/Tiny.pm                 Copyright 2022 cPanel, L.L.C.
#                                                           All rights reserved.
# copyright@cpanel.net                                         http://cpanel.net
# This code is subject to the cPanel license. Unauthorized copying is prohibited

use strict;

$Cpanel::Unix::PID::Tiny::VERSION = 0.9_2;

sub new {
    my ( $self, $args_hr ) = @_;
    $args_hr->{'minimum_pid'} = 11 if !exists $args_hr->{'minimum_pid'} || $args_hr->{'minimum_pid'} !~ m{\A\d+\z}ms;    # this does what one assumes m{^\d+$} would do

    if ( defined $args_hr->{'ps_path'} ) {
        $args_hr->{'ps_path'} .= '/' if $args_hr->{'ps_path'} !~ m{/$};
        if ( !-d $args_hr->{'ps_path'} || !-x "$args_hr->{'ps_path'}ps" ) {
            $args_hr->{'ps_path'} = '';
        }
    }
    else {
        $args_hr->{'ps_path'} = '';
    }

    return bless { 'ps_path' => $args_hr->{'ps_path'}, 'minimum_pid' => $args_hr->{'minimum_pid'} }, $self;
}

sub kill {
    my ( $self, $pid, $give_kill_a_chance ) = @_;
    $give_kill_a_chance = int $give_kill_a_chance if defined $give_kill_a_chance;
    $pid                = int $pid;
    my $min = int $self->{'minimum_pid'};
    if ( $pid < $min ) {

        # prevent bad args from killing the process group (IE '0')
        # or general low level ones
        warn "kill() called with integer value less than $min";
        return;
    }

    return 1 unless $self->is_pid_running($pid);

    # CORE::kill 0, $pid : may be false but still running, see `perldoc -f kill`
    my @signals = ( 15, 2, 1, 9 );          # TERM, INT, HUP, KILL
    foreach my $signal ( 15, 2, 1, 9 ) {    # TERM, INT, HUP, KILL

        _kill( $signal, $pid );

        # give kill() some time to take effect?
        if ($give_kill_a_chance) {
            my $start_time = time();
            while ( time() < $start_time + $give_kill_a_chance ) {
                if ( $self->is_pid_running($pid) ) {
                    select( undef, undef, undef, 0.25 );
                }
                else {
                    return 1;
                }
            }
        }
        return 1 unless $self->is_pid_running($pid);
    }

    # Failed to kill
    return;
}

sub is_pid_running {
    my ( $self, $check_pid ) = @_;

    $check_pid = int $check_pid;
    return if !$check_pid || $check_pid < 0;

    return 1 if $> == 0 && _kill( 0, $check_pid );    # if we are superuser we can avoid the the system call. For details see `perldoc -f kill`
                                                      # If the proc filesystem is available, it's a good test. If not, continue on to system call
    return 1 if -e "/proc/$$" && -r "/proc/$$" && -r "/proc/$check_pid";

    return;
}

sub pid_info_hash {
    my ( $self, $pid ) = @_;
    $pid = int $pid;
    return if !$pid || $pid < 0;

    my @outp = $self->_raw_ps( 'u', '-p', $pid );
    chomp @outp;
    my %info;
    @info{ split( /\s+/, $outp[0], 11 ) } = split( /\s+/, $outp[1], 11 );
    return wantarray ? %info : \%info;
}

sub _raw_ps {
    my ( $self, @ps_args ) = @_;
    my $psargs = join( ' ', @ps_args );
    my @res    = `$self->{'ps_path'}ps $psargs`;
    return wantarray ? @res : join '', @res;
}

sub get_pid_from_pidfile {
    my ( $self, $pid_file ) = @_;

    # if this function is ever changed to use $self as a hash object, update pid_file() to not do a class method call
    return 0 if !-e $pid_file or -z _;

    open my $pid_fh, '<', $pid_file or return;
    my $pid = <$pid_fh>;
    close $pid_fh;

    return 0 if !$pid;
    chomp $pid;
    return int( abs($pid) );
}

sub is_pidfile_running {
    my ( $self, $pid_file ) = @_;
    my $pid = $self->get_pid_from_pidfile($pid_file) || return;
    return $pid if $self->is_pid_running($pid);
    return;
}

sub pid_file {
    my ( $self, $pid_file, $newpid, $retry_conf ) = @_;
    $newpid = $$ if !$newpid;

    my $rc = $self->pid_file_no_unlink( $pid_file, $newpid, $retry_conf );
    if ( $rc && $newpid == $$ ) {
        $self->create_end_blocks($pid_file);
    }
    return 1 if defined $rc && $rc == 1;
    return 0 if defined $rc && $rc == 0;
    return;
}

sub create_end_blocks {
    my ( $self, $pid_file ) = @_;    ## no critic qw(Variables::ProhibitUnusedVariables);

    # prevent forked childrens' END from killing parent's pid files
    #   'unlink_end_use_current_pid_only' is undocumented as this may change, feedback welcome!
    #   'carp_unlink_end' undocumented as it is only meant for testing (rt57462, use Test::Carp to test END behavior)
    if ( $self->{'unlink_end_use_current_pid_only'} ) {
        eval 'END { unlink $pid_file if $$ eq ' . $$ . '}';    ## no critic qw(ProhibitStringyEval)
        if ( $self->{'carp_unlink_end'} ) {
            eval 'END { require Carp;Carp::carp("[info] $$ unlink $pid_file (current pid check)") if $$ eq ' . $$ . '}';    ## no critic qw(ProhibitStringyEval)
        }
    }
    else {
        eval 'END { unlink $pid_file if Cpanel::Unix::PID::Tiny->get_pid_from_pidfile($pid_file) eq $$ }';                  ## no critic qw(ProhibitStringyEval)
        if ( $self->{'carp_unlink_end'} ) {
            eval 'END { require Carp;Carp::carp("[info] $$ unlink $pid_file (pid file check)") if Cpanel::Unix::PID::Tiny->get_pid_from_pidfile($pid_file) eq $$ }';    ## no critic qw(ProhibitStringyEval)
        }
    }

    return;
}

*pid_file_no_cleanup = \&pid_file_no_unlink;    # more intuitively named alias

sub pid_file_no_unlink {
    my ( $self, $pid_file, $newpid, $retry_conf ) = @_;
    $newpid = $$ if !$newpid;

    if ( ref($retry_conf) eq 'ARRAY' ) {
        $retry_conf->[0] = int( abs( $retry_conf->[0] ) );
        for my $idx ( 1 .. scalar( @{$retry_conf} ) - 1 ) {
            next if ref $retry_conf->[$idx] eq 'CODE';
            $retry_conf->[$idx] = int( abs( $retry_conf->[$idx] ) );
        }
    }
    else {
        $retry_conf = [ 3, 1, 2 ];
    }

    my $passes = 0;
    require Fcntl;

  EXISTS:
    $passes++;
    if ( -e $pid_file ) {

        my $curpid = $self->get_pid_from_pidfile($pid_file);

        # TODO: narrow even more the race condition where $curpid stops running and a new PID is put in
        # the file between when we pull in $curpid above and check to see if it is running/unlink below

        return 1 if int $curpid == $$ && $newpid == $$;     # already setup
        return   if int $curpid == $$;                      # can't change it while $$ is alive
        return   if $self->is_pid_running( int $curpid );

        unlink $pid_file;                                   # must be a stale PID file, so try to remove it for sysopen()
    }

    #
    # TODO: FIXME: This should rename() the pidfile
    # into place to ensure we never have an empty pidfile
    #
    # write only if it does not exist:
    my $pid_fh = _sysopen($pid_file);
    if ( !$pid_fh ) {
        return 0 if $passes >= $retry_conf->[0];
        if ( ref( $retry_conf->[$passes] ) eq 'CODE' ) {
            $retry_conf->[$passes]->( $self, $pid_file, $passes );
        }
        else {
            sleep( $retry_conf->[$passes] ) if $retry_conf->[$passes];
        }
        goto EXISTS;
    }

    print {$pid_fh} int( abs($newpid) );
    close $pid_fh;

    return 1;
}

sub _sysopen {
    my ($pid_file) = @_;
    sysopen( my $pid_fh, $pid_file, Fcntl::O_WRONLY() | Fcntl::O_EXCL() | Fcntl::O_CREAT() ) || return;
    return $pid_fh;
}

sub _kill {    ## no critic(RequireArgUnpacking
    return CORE::kill(@_);    # goto &CORE::kill; is problematic
}

# This code attempts to deal with all of the crazy associated with getting a pid file:
# 1. It being stale (kill it!)
# 2. It being very young (move on)
# 3. The pid file disappearing out from under you when checked (race condition?)
# 4. The pid file being against an unrelated process.

sub get_run_lock {

    my ( $pid_file, $min_age_seconds, $max_age_seconds, $cmdline_regex ) = @_;

    $pid_file                or die("Need a pid file to get a run lock.");
    defined $min_age_seconds or $min_age_seconds = 15 * 60;
    defined $max_age_seconds or $max_age_seconds = 20 * 60 * 60;

    # Deal with the possibility of the pid file going away between fail to get pid file and stat.
    # If it happens more than once, something's funny. Just throw your hands up and fail.
    foreach ( 1 .. 2 ) {

        # Try to claim the pid file.
        my $upid    = Cpanel::Unix::PID::Tiny->new();
        my $got_pid = $upid->pid_file($pid_file);

        # Success!
        return 1 if ($got_pid);

        # Stat the pid file.
        my @pid_stat = stat($pid_file);

        # Try again if the stat failed (file just went away?)
        next if ( !@pid_stat );

        # Just fail if the pid file appears to be < $min_age_seconds old.
        my $pid_age = time() - $pid_stat[9];
        return 0 if ( $min_age_seconds && $pid_age < $min_age_seconds );

        my $active_pid = $upid->get_pid_from_pidfile($pid_file);
        if ( !-e "/proc/$active_pid" ) {
            unlink $pid_file;
            next;
        }

        # The process went away?
        open( my $fh, '<', "/proc/$active_pid/cmdline" ) or next;

        # Can't read it? Something's funny.
        my $cmdline = <$fh>;

        # The pid appears to be us and the file is older than $max_age_seconds. Let's send it a kill signal and remove the file.
        if ( $max_age_seconds && $pid_age > $max_age_seconds ) {
            _kill( 'TERM', $active_pid );
            unlink $pid_file;
        }

        if ( !$cmdline or ( $cmdline_regex && $cmdline !~ $cmdline_regex ) ) {
            unlink $pid_file;
        }

    }
    return undef;    # I give up!
}

1;

__END__

=head1 NAME

Cpanel::Unix::PID::Tiny - This file is a fork of Unix::PID::Tiny 0.9 on CPAN.

It has been changed in both places since.

=cut
