package Cpanel::Binaries::Role::Cmd;

# cpanel - Cpanel/Binaries/Role/Cmd.pm             Copyright 2022 cPanel, L.L.C.
#                                                           All rights reserved.
# copyright@cpanel.net                                         http://cpanel.net
# This code is subject to the cPanel license. Unauthorized copying is prohibited

=head1 NAME

Cpanel::Binaries::Role::Cmd

=head1 DESCRIPTION

This is a base class currently used by Cpanel::Binaries::Rpm and
Cpanel::Binaries::Role::Debian::Dpkg* but could be used for any system command you want to
interact with in your class. You only need to provide the sub bin in order to
make it work!

=head1 SYNOPSIS

    use parent 'Cpanel::Binaries::Role::Cmd';
    sub bin { return '/bin/rpm' }

    # Then later in code you can either do:

    sub foo ($self) {
        my $got = $self->cmd("-l", '--all');
        ...
    }

    # Or if you need callbacks during output,

    my ( $stdout, $stderr );

    return $self->rpm->run(
        args   => \@args,
        stdout_buffer => \$stdout,
        stderr_buffer => \$stderr,
    );

=cut

use cPstrict;

use Cpanel::Fcntl::Constants ();
use Cpanel::Fuser            ();
use Cpanel::OS               ();
use Cpanel::SafeRun::Extra   ();
use Cpanel::TimeHiRes        ();

use constant DEFAULT_LOCK_TIMEOUT               => 90 * 60;
use constant DEFAULT_LOCK_TIMEOUT_FRESH_INSTALL => 2 * DEFAULT_LOCK_TIMEOUT;

# NB: Duplicated from Cpanel::Async::EasyLock:
our $_DIR_PATH = '/var/cpanel/easylock';

sub new {
    my ( $class, %opts ) = @_;

    my %hash = %opts;

    my $self = \%hash;
    bless $self, $class;

    return $self;
}

sub lock_timeout ($self) {
    if ( $ENV{'CPANEL_BASE_INSTALL'} ) {

        # Fresh install can be longer than update and slow
        #   as we are running multiple processes in parallel
        #   increase the chance of success by giving it more time
        return $self->{'lock_timeout'} //= DEFAULT_LOCK_TIMEOUT_FRESH_INSTALL;
    }

    return $self->{'lock_timeout'} //= DEFAULT_LOCK_TIMEOUT;
}

=head1 METHODS

=head2 bin_path ($self)

You must override this method with a method that determines the binary your class will interact with.

=cut

sub bin_path ($self) { die "unimplemented" }

=head2 locks_to_wait_for ($self)

If your class's binary will exit based on a competing lock, you can provide this sub in your subclass which provides a list of these files.

Before you try to run anything, these files will be checked to assure nothing has them open in any way.

=cut

sub locks_to_wait_for { return }

=head2 lock_to_hold ($self)

If your class's binary should not be run when related code is running, you can provide one or more locks which will be locked sequentially (beware the deadlock!).

When cmd/run calls are made, this lock is placed and then released when the commands are complete.

=cut

sub lock_to_hold { return }

=head2 needs_lock ($self, @args).

If your class implements locks_to_wait_for or lock_to_hold, it probably will also want to provide exceptions to some commands that are read-only based and don't require a lock. Providing this method in your subclass allows you to provide exceptions.

B<@args> are passed to your method so you can use this information to determine if you need a lock.

Return value is boolean.

=cut

sub needs_lock ( $self, @args ) {
    return 0;
}

=head2 bin ($self)

Cache the bin_path to the object

=cut

sub bin ($self) {
    die q[Method call] unless ref $self;

    return $self->{'bin'} if length $self->{'bin'};

    my $bin = $self->bin_path or die q[No bin_path set for ] . ref $self;
    -x $bin                   or die("Cannot find $bin on this system.");

    return $self->{'bin'} = $bin;
}

=head2 cmd ( $self, @args )

Pass the args you want sent to your binary and the output and exit is returned:

    { 'output' => '...', 'status' => $? };

=cut

sub cmd ( $self, @args ) {
    return $self->cmd_with_logger( undef, @args );
}

sub cmd_but_warn_on_fail ( $self, @args ) {
    my $out = $self->cmd(@args);
    warn '[' . $self->bin() . " @args] exited $out->{'status'} ($out->{'output'})" if $out->{'status'};
    return $out;
}

=head2 cmd_with_logger ( $self, $logger, @args )

Pass the logger and args you want sent to your binary.

The output will be captured and returned but will also log the output via ->info / ->warning as it goes.

Returns:

    { 'output' => '...', 'status' => $? };

=cut

sub cmd_with_logger ( $self, $logger, @args ) {
    return $self->_cmd_with_logger( 1, $logger, @args );
}

sub cmd_with_logger_no_timeout ( $self, $logger, @args ) {
    return $self->_cmd_with_logger( 0, $logger, @args );
}

sub _cmd_with_logger ( $self, $enable_timeout, $logger, @args ) {
    my $output_buffer = '';

    # Run this commnd and feed my callback whenevery you get an output line.

    # case CPANEL-29784:
    # For backwards compat with Cpanel::SafeRun::Dynamic::livesaferun
    # we need to call the callback for BOTH stderr and stdout
    my $run = $self->run(
        args   => \@args,
        buffer => \$output_buffer,
        $enable_timeout ? () : (
            timeout      => 0,
            read_timeout => 0,
        ),
        logger => $logger,
    );

    if ( $logger && $run->CHILD_ERROR() ) {
        my $msg = join( q< >, $run->autopsy(), $output_buffer );
        $logger->warning($msg);
    }

    return { 'output' => $output_buffer, 'status' => $run->CHILD_ERROR() };
}

=head2 run_or_die ( $self, @args )

The same as run but dies if there is failure via Cpanel::SafeRun::Extra.

=cut

sub run_or_die ( $self, @args ) {
    return $self->run( args => \@args, die_on_error => 1 );
}

=head2 run ( $self, %opts )

Everything in this class uses this method to run things. Before it runs, we use _setup_envs assure a
consistent environment and output data. On RHEL 8+ systems, we hack a PTY in place so rpm commands
run interactively.

Returns a Cpanel::SafeRun::Extra.

=cut

sub run ( $self, %opts ) {
    my $bin = $self->bin;

    # On RHEL 8+ systems, we have to fool the rpm command into thinking this is an interactive terminal.
    # See github for more information https://github.com/rpm-software-management/rpm/commit/6ce2d43e2533505aa252159bfa8cc799965655bb
    if ( $> == 0 && $bin =~ m{bin/rpm$} && Cpanel::OS::retry_rpm_cmd_no_tty_hack() ) {
        require IO::Pty;
        $opts{stdin} = eval { IO::Pty->new } || undef;    # If new fails, we will be vulnerable to pid conflicts but we already have protections against that at a module level.
    }

    my %saferun_args = (
        program      => $bin,
        envs         => $self->_setup_envs,
        args         => $opts{args}         // [],
        die_on_error => $opts{die_on_error} // 0,
    );

    foreach my $param (qw{stdout stderr stdin timeout read_timeout buffer logger}) {
        next unless exists $opts{$param};
        $saferun_args{$param} = $opts{$param};
    }

    my $method = $opts{die_on_error} ? 'new_or_die' : 'new';

    my $logger = $opts{'logger'};

    my $lock_to_hold = $self->get_lock_for_cmd( $logger, $saferun_args{args} );

    # Cheater debug to figure out what command was run.
    # printf("Running $bin -- %s\n", join( ", ", $opts{args}->@*) );
    return Cpanel::SafeRun::Extra->$method(%saferun_args);
}

=head2 special_lang_env_vars

provides a full list of all known locale variables which coerce binaries into producing
untranslated output. This makes it easier to process the output.

=cut

sub special_lang_env_vars {
    return qw/LANG LANGUAGE LC_ALL LC_MESSAGES LC_CTYPE/;
}

=head2 lang

By default, all Cpanel::Binaries objects use LANG=C but you can customize this in child classes.

=cut

sub lang { return 'C' }

sub _setup_envs ($self) {
    my $lang = $self->lang;
    my @keys = special_lang_env_vars();

    my %env;
    @env{@keys}              = ($lang) x scalar @keys;
    $env{'PYTHONIOENCODING'} = $ENV{'PYTHONIOENCODING'} || 'UTF-8:backslashreplace';
    $env{'DEBIAN_FRONTEND'}  = 'noninteractive';                                       # doesn't hurt non-ubuntu systems, but absolutely required for them

    return \%env;
}

=head2 hold_lock ( $self, $logger )

This method does nothing if lock_to_hold is not defined.

When called, this method tries to use lock_to_hold to create a flock. If something else is
holding it, it waits for lock_timeout ( defaults to DEFAULT_LOCK_TIMEOUT ) seconds before
giving up.

If $logger is passed, it will log that it is waiting for the lock.

Failure to get a lock file will result in an exception being thrown.

=cut

sub hold_lock ( $self, $logger, $args ) {
    my $lock_file = $self->lock_to_hold() or return;
    $lock_file =~ m{/} and die "lock file name only please, not an absolute path";

    my $dir_path = $_DIR_PATH;

    if ( !-d $dir_path ) {
        mkdir $dir_path, 0700;
    }
    -d $dir_path or die("Cannot create a lock without $dir_path being present");

    $lock_file = "$dir_path/$lock_file";

    my $lock_timeout = $self->lock_timeout;

    sysopen( my $fh, $lock_file, $Cpanel::Fcntl::Constants::O_RDONLY | $Cpanel::Fcntl::Constants::O_CREAT ) or die("Cannot open $lock_file for locking");
    my $start = time;
    my $cnt   = 0;
    while ( time - $start < $lock_timeout ) {
        flock( $fh, $Cpanel::Fcntl::Constants::LOCK_EX | $Cpanel::Fcntl::Constants::LOCK_NB ) and do {
            return $fh;
        };

        if ($logger) {
            $logger->info( "Waiting for lock to execute: " . join( " ", $self->bin, @$args ) ) if $cnt == 0;
            $cnt++;

            if ( $cnt % 40 == 0 ) {
                $logger->info( "Waiting for exclusive lock to run " . $self->bin );
            }
        }

        $self->_sleep_randomly;
    }

    my $msg = "Failed to get exclusive lock to run " . $self->bin;
    $logger && $logger->error($msg);

    return die $msg;
}

sub get_lock_for_cmd ( $self, $logger, $args ) {
    return unless $self->needs_lock(@$args);

    my $lock = $self->hold_lock( $logger, $args );
    $self->wait_for_locks($logger);

    return $lock;
}

=head2 wait_for_locks ( $self, $logger )

This method does nothing if locks_to_wait_for is an empty list.

When called, this method uses Cpanel::Fuser to determine if any of the known lock files are open by any processes.
it waits for lock_timeout ( defaults to DEFAULT_LOCK_TIMEOUT ) seconds before giving up.

If $logger is passed, it will log that it is waiting for the lock.

Failure to get a lock file will result in an exception being thrown.

=cut

sub wait_for_locks ( $self, $logger = undef ) {
    my @lock_files = $self->locks_to_wait_for;

    my $lock_timeout = $self->lock_timeout;

    my $start = time;
    my $cnt   = 0;
    while ( time - $start < $lock_timeout ) {
        my %locks = Cpanel::Fuser::check(@lock_files) or return 1;

        if ( $logger && ( $cnt++ % 40 ) == 0 ) {
            my $open_locks = %locks;
            $logger->info( "Waiting for $open_locks related locks to clear for " . $self->bin );
        }

        $self->_sleep_randomly;
    }

    return die "Timeout waiting for distro lock files related to " . $self->bin;
}

# Jitter the sleep time so we are less likely to collide with other lockers.
sub _sleep_randomly {
    Cpanel::TimeHiRes::sleep( ( 100 + rand(50) ) / 1000 );
    return;
}

1;
