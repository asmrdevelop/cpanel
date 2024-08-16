package Cpanel::SafeRun::Object;

# cpanel - Cpanel/SafeRun/Object.pm                Copyright 2022 cPanel, L.L.C.
#                                                           All rights reserved.
# copyright@cpanel.net                                         http://cpanel.net
# This code is subject to the cPanel license. Unauthorized copying is prohibited

use cPstrict;

use parent 'Cpanel::ChildErrorStringifier';

#This module may not be available in updatenow or upcp.
BEGIN {
    eval { require Proc::FastSpawn; };
}

use IO::SigGuard ();

use Cpanel::Env                ();
use Cpanel::Exception          ();
use Cpanel::FHUtils::Autoflush ();
use Cpanel::FHUtils::OS        ();
use Cpanel::ReadMultipleFH     ();
use Cpanel::LoadModule         ();
use Cpanel::LocaleString       ();

use constant _ENOENT => 2;

my $CHUNK_SIZE = 2 << 16;

my $DEFAULT_TIMEOUT      = 3600;    # 1 hour
my $DEFAULT_READ_TIMEOUT = 0;

our $SAFEKILL_TIMEOUT = 1;

=encoding utf-8

=head1 NAME

Cpanel::SafeRun::Object

=head1 SYNOPSIS

Basic operation: throws an appropriate exception if the command
execution fails in any way …

    my $run = Cpanel::SafeRun::Object->new_or_die(
        program => '/path/to/command',
        args => [ 'foo', 'bar', 'key=value', 'key=value with spaces' ],

        # Give a string as input:
        stdin => 'This is input.',
    );

    my $stdout = $run->stdout();
    my $stderr = $run->stderr();

See L</COOKBOOK> below for additional examples.

=head1 DESCRIPTION

An object-oriented interface for invoking an external command.

=head1 WHY USE THIS MODULE?

Some of this module’s salient features are:

=over

=item * Timeouts

Timeouts ensure that a stuck child process doesn’t also hang your calling
process.

=item * Error reporting: starting up

Running a command in a subprocess is a multi-step process “under the hood”,
and any of those steps can fail. It’s important in those instances to
report failures in as much detail as possible, to give callers the best
chance of being able to fix the problem.

=item * Error reporting: finishing up

Just as important as error-checking the start of command execution is
error-checking the I<end> of that execution. This module makes it quick
and easy to fail if the child process ends via signal or nonzero exit.

=item * Use of L<vfork(2)>

cPanel’s fork of L<Proc::FastSpawn> is the product of significant
trial-and-error. This module facilitates significant speed improvements
under heavy load relative to the simpler fork/exec method that most
methods of command execution in Perl use.

=item * I/O flexibility

Unlike other, simpler methods of running a command, this module provides
interfaces for both static and interactive streaming to and from the
child process via all three standard streams.

=item * Additional features

Callbacks can be assigned to run in the child before running the command
and/or in the parent after forking.

Special controls facilitate fine-grained control of the subprocess’s
environment variables.

=back

Perl offers several ways to execute a command in a subprocess. The following
is an incomplete description of various other means of running a remote
command, and when and why this module is advantageous by comparison:

=over

=item C<readpipe()>

Quick and simple, but clumsy. This function invokes a shell, which
entails additional overhead as well as a requirement to escape arguments.
It lacks timeout controls, handling of STDERR, or a means to give STDIN
to the child. Doesn’t provide the same level of error reporting detail.

=item C<open()>

Better than C<readpipe()> but also lacks controls for timeouts,
and STDERR. STDIN and STDOUT are supported, but it’s either/or; you can’t
do both with the same subprocess. Passing a static string is a bit
awkward because you have to do the I/O manually. Error reporting is
similar to C<readpipe()>.

=item L<IPC::Open2> and L<IPC::Open3>

Doesn’t detect C<exec> failures in the child process. Passing a static
string as STDIN requires manual I/O. Error reporting is similar to
C<readpipe()>. No timeouts.

=item L<IPC::Run>

Maybe the closest CPAN offering to this module, this provides timeouts
in addition to concurrent I/O (including handling of static strings).
Error reporting still isn’t as detailed, though.

=back

=head1 SEE ALSO

L<Cpanel::Async::Exec> provides similar functionality to this module
for asynchronous code.

L<Cpanel::Exec> I<just> runs the command. It doesn’t wait for the
command to finish nor provide you I/O functionality.

=head1 NOTES

=over

=item * This does a Cpanel::Env::clean_env in the child
then adds in environment variables: HOME, USER, TMP, TEMP

=item * SIGPIPE is usually suppressed in this function
in favor of allowing exceptions from EPIPE to propagate in Perl.
The only exception is when you pass in C<stdin> as a C<CODE> reference;
in this case we still allow SIGPIPE because this
class doesn’t control the writes, which might not be error-checked.

(You can, and likely should, still suppress SIGPIPE and check for
errors in the C<stdin> callback.)

=item * This will also reset $SIG{'CHLD'} to 'DEFAULT' for the
duration of this function call. So if you’re doing manual child
process reaping, that will be suspended for the duration of this
function.

=item * If the child process forks, and these grandchildren hold STDOUT and
STDERR open even after the termination of the child, this object's constructor
will not return until timeout occurs! This is most likely to happen if this is
used to start a daemon, but the daemon fails to close stdout and stderr, but
there may be other patterns where this can lead to unexpected behavior. If I/O
is not desired, consider alternatives as described above.

=back

=head1 CONSTRUCTOR

Arguments:

=over

=item * C<program> (required, string)

Full path of the program to execute.

=item * C<args> (optional, arrayref)

Arguments for the command.

=item * stdin (optional, string | stringref | filehandle | coderef)

If not given, stdin is connected to /dev/null.

B<IMPORTANT:> A filehandle is assumed to have an empty PerlIO buffer.

Try to avoid passing a coderef here if you can. It should not
be necessary; see L<IO::Callback> for a good means of avoiding it.
If you must, though: a C<stdin> coderef receives a write handle
that is piped to the child process's STDIN. Its return is ignored.
Note that SIGPIPE is not suppressed when C<stdin> is a coderef.

=item * stdout (optional, filehandle)

=item * stderr (optional, filehandle)

Filehandles to direct STDOUT/STDERR to, in lieu of buffering.
The filehandles are LEFT OPEN after the program execution.
If given, stdout()/stdout_r()/stderr()/stderr_r() throw exceptions.

If you need callbacks, consult Cpanel::CPAN::IO::Callback::Write.
(NB: An easier way to capture output to a buffer is to use C<open()> on a
scalar reference.)

If STDOUT and STDERR are the same reference, then the child’s STDOUT
and STDERR will go to the same underlying file descriptor. This is especially
useful if, e.g., you want to capture STDOUT and STDERR in the same buffer.

B<IMPORTANT:> Filehandles are assumed to have an empty PerlIO buffer.

=item * timeout (optional, number)

How long (in seconds) to wait in total for the process to complete
before terminating it.
If not given, we wait for $DEFAULT_TIMEOUT seconds in total.
A value of 0 disables the total timeout.
Passing a value of 0 for 'timeout' and 'read_timeout' will disable timeout
entirely and WILL HANG if the child process does not exit on its own.

=item * read_timeout (optional, number)

How long (in seconds) to wait after a process stops responding before
terminating it.
If not given, we wait for $DEFAULT_READ_TIMEOUT seconds.
A value of 0 disables read_timeout entirely if 0 is passed for 'timeout'
as well.
If 0 is passed for 'timeout' and 'read_timeout' the parent process
WILL HANG if the child process does not exit on its own.
If 0 is passed for 'read_timeout' and a 0 is not passed for 'timeout',
then the 'read_timeout' will be the value of 'timeout'.

=item * before_exec (optional, coderef)

A coderef to execute immediately before we exec() the "program".
This is where you can tweak %ENV, setuid, chdir, etc.
NOTE: An exception thrown in here will print to STDERR and kill the
child process, preventing execution of the "program".

=item * after_fork (optional, coderef)

A coderef to execute immediately after we successfully fork().
It receives the child’s PID as an argument.
This is where you can e.g., set signal handlers on the parent
to be aware of the child PID.

=item * keep_env  (optional, boolean)

If set the enviorment will not be made safe

=item * homedir  (optional, string)

The homedir to use for the C<HOME> env variable

=item * user  (optional, string)

The name of the user to use for the C<USER> env variable

=back

=cut

my @_allowed_env_vars_cache;

sub new {    ## no critic qw(Subroutines::ProhibitExcessComplexity)
    my ( $class, %OPTS ) = @_;

    die "No “program”!" if !length $OPTS{'program'};

    if ( !defined $OPTS{'timeout'} ) {
        $OPTS{'timeout'} = $DEFAULT_TIMEOUT;
    }

    if ( !defined $OPTS{'read_timeout'} ) {
        $OPTS{'read_timeout'} = $DEFAULT_READ_TIMEOUT;
    }

    if ( $OPTS{'program'} =~ tr{><*?[]`$()|;&#$\\\r\n\t }{} && !-e $OPTS{'program'} ) {
        die Cpanel::Exception::create( 'InvalidParameter', 'A value of “[_1]” is invalid for “[_2]” as it does not permit the following characters: “[_3]”', [ $OPTS{'program'}, 'program', '><*?[]`$()|;&#$\\\\\r\\n\\t' ] );
    }

    my $args_ar = $OPTS{'args'} || [];
    die "“args” must be an arrayref" if defined $args_ar && ref $args_ar ne 'ARRAY';

    #There’s no good reason for undef to be in the argument list since
    #it can’t actually be passed as an argument between processes.
    die "Undefined value given as argument! (@$args_ar)" if grep { !defined } @$args_ar;

    my $pump_stdin_filehandle_into_child;

    my ( %parent_read_fh, %child_write_fh );

    my $merge_output_yn = $OPTS{'stdout'} && $OPTS{'stderr'} && ( $OPTS{'stdout'} eq $OPTS{'stderr'} );

    local $!;

    for my $handle_name (qw(stdout stderr)) {
        my $custom_fh = $OPTS{$handle_name} && UNIVERSAL::isa( $OPTS{$handle_name}, 'GLOB' ) && $OPTS{$handle_name};

        my $dupe_filehandle_will_work = $custom_fh && !tied(*$custom_fh) && ( fileno($custom_fh) > -1 );

        if ( !$custom_fh && $OPTS{$handle_name} ) {
            die "“$handle_name” must be a filehandle or undef, not $OPTS{$handle_name}";
        }

        if ($dupe_filehandle_will_work) {

            # If the passed-in filehandle’s file descriptor is
            # less than 3, then there’s potential for confusion if, e.g.,
            # the child’s STDOUT is redirected to the parent’s STDERR.
            # To avoid this, we duplicate the underlying file descriptor.
            if ( fileno($custom_fh) < 3 ) {
                open my $copy, '>&', $custom_fh or die "dup($handle_name): $!";
                $child_write_fh{$handle_name} = $copy;
            }
            else {
                $child_write_fh{$handle_name} = $custom_fh;
            }
        }

        # This makes for a single pipe from the child process so that the
        # output is always merged in the accurate order.
        elsif ( $merge_output_yn && $handle_name eq 'stderr' ) {
            $parent_read_fh{'stderr'} = $parent_read_fh{'stdout'};
            $child_write_fh{'stderr'} = $child_write_fh{'stdout'};
        }

        else {
            pipe $parent_read_fh{$handle_name}, $child_write_fh{$handle_name}    #
              or die "pipe() failed: $!";
        }
    }

    my ( $child_reads, $parent_writes );
    my $close_child_reads = 0;

    # This module is used on system Perl.  On 5.10, calling length on undef
    # produces a warning.
    if ( !defined $OPTS{'stdin'} || !length $OPTS{'stdin'} ) {
        open $child_reads, '<', '/dev/null' or die "open(<, /dev/null) failed: $!";
        $close_child_reads = 1;
    }
    elsif ( UNIVERSAL::isa( $OPTS{'stdin'}, 'GLOB' ) ) {
        my $fileno = fileno $OPTS{'stdin'};

        #fileno is -1 for filehandles to scalar references. Since those
        #filehandles are Perl abstractions, we have to handle those in perl.
        #fileno is undef for IO::Callback handles, so we'll have to handle them
        #via perl too
        if ( !defined $fileno || $fileno == -1 ) {
            $pump_stdin_filehandle_into_child = 1;
        }
        else {
            $child_reads = $OPTS{'stdin'};
        }
    }

    if ( !$child_reads ) {
        $close_child_reads = 1;
        pipe( $child_reads, $parent_writes ) or die "pipe() failed: $!";
    }

    my $self = bless {
        _program => $OPTS{'program'},
        _args    => $OPTS{'args'} || [],
    }, $class;

    #So we don't get -1 from waitpid().
    local $SIG{'CHLD'} = 'DEFAULT';

    my $exec_failed_message = "exec($OPTS{'program'}) failed:";
    my $used_fastspawn      = 0;
    if (
        $INC{'Proc/FastSpawn.pm'}                                   # may not be available yet due to upcp.static or updatenow.static
        && !$OPTS{'before_exec'}
        && !$Cpanel::AccessIds::ReducedPrivileges::PRIVS_REDUCED    # PPI NO PARSE - We not ever be set if its not loaded
    ) {
        $used_fastspawn = 1;
        my @env;

        # no before_exec and no PRIVS_REDUCED, we can use fastspawn
        #
        if ( !$OPTS{'keep_env'} ) {
            if ( !@_allowed_env_vars_cache ) {
                @_allowed_env_vars_cache = ( split( m{ }, Cpanel::Env::get_safe_env_vars() ) );
            }
            @env = map { exists $ENV{$_} ? ( $_ . '=' . ( $ENV{$_} // '' ) ) : () } @_allowed_env_vars_cache;
        }
        my $user    = $OPTS{'user'};
        my $homedir = $OPTS{'homedir'};
        if ( !$user || !$homedir ) {
            my ( $pw_user, $pw_homedir ) = ( getpwuid $> )[ 0, 7 ];
            $user    ||= $pw_user;
            $homedir ||= $pw_homedir;
        }
        die "Invalid EUID: $>" if !$user || !$homedir;

        push @env, "HOME=$homedir",    "USER=$user";                                  # need to always be set since we start clean and don't have before_exec
        push @env, "TMP=$homedir/tmp", "TEMP=$homedir/tmp" if !defined $ENV{'TMP'};

        $self->{'_child_pid'} = Proc::FastSpawn::spawn_open3(
            fileno($child_reads),                                                            # stdin
            defined $child_write_fh{'stdout'} ? fileno( $child_write_fh{'stdout'} ) : -1,    # stdout
            defined $child_write_fh{'stderr'} ? fileno( $child_write_fh{'stderr'} ) : -1,    # stderr
            $OPTS{'program'},                                                                # program
            [ $OPTS{'program'}, @$args_ar ],                                                 # args
            $OPTS{'keep_env'} ? () : \@env                                                   # env
        );

        if ( !$self->{_child_pid} ) {
            $self->{'_CHILD_ERROR'} = $! << 8;
            $self->{'_exec_failed'} = 1;
            ${ $self->{'_stdout'} } = '';
            ${ $self->{'_stderr'} } .= "$exec_failed_message $!";
        }
    }
    else {
        require Cpanel::ForkAsync;
        $self->{'_child_pid'} = Cpanel::ForkAsync::do_in_child(
            sub {
                $SIG{'__DIE__'} = 'DEFAULT';    ## no critic qw(Variables::RequireLocalizedPunctuationVars) -- will never be unset

                if ( $parent_read_fh{'stdout'} ) {
                    close $parent_read_fh{'stdout'} or die "child close parent stdout failed: $!";
                }

                if ( $parent_read_fh{'stderr'} && !$merge_output_yn ) {
                    close $parent_read_fh{'stderr'} or die "child close parent stderr failed: $!";
                }

                if ($parent_writes) {
                    close $parent_writes or die "close() failed: $!";
                }

                #NOTE: Perl 5.6 can't dupe filehandles with 3-arg open().
                open( *STDIN, '<&=' . fileno $child_reads ) or die "open(STDIN) failed: $!";    ##no critic qw(ProhibitTwoArgOpen)

                # Perl 5.6 will segfault if we try to duplicate a file descriptor to
                # itself.
                my $fileno_stdout = fileno \*STDOUT;
                if ( $fileno_stdout != fileno( $child_write_fh{'stdout'} ) ) {

                    if ( $fileno_stdout != 1 ) {
                        close *STDOUT            or die "close(STDOUT) failed: $!";
                        open( *STDOUT, '>>&=1' ) or die "open(STDOUT, '>>&=1') failed: $!";    ##no critic qw(ProhibitTwoArgOpen)
                    }

                    open( *STDOUT, '>>&=' . fileno $child_write_fh{'stdout'} ) or die "open(STDOUT) failed: $!";    ##no critic qw(ProhibitTwoArgOpen)
                }

                my $fileno_stderr = fileno \*STDERR;
                if ( $fileno_stderr != fileno( $child_write_fh{'stderr'} ) ) {

                    if ( $fileno_stderr != 2 ) {
                        close *STDERR            or die "close(STDOUT) failed: $!";
                        open( *STDERR, '>>&=2' ) or die "open(STDERR, '>>&=2') failed: $!";    ##no critic qw(ProhibitTwoArgOpen)
                    }

                    open( *STDERR, '>>&=' . fileno $child_write_fh{'stderr'} ) or die "open(STDERR) failed: $!";    ##no critic qw(ProhibitTwoArgOpen)
                }

                if ( !$OPTS{'keep_env'} ) {
                    Cpanel::Env::clean_env();
                }

                if ($Cpanel::AccessIds::ReducedPrivileges::PRIVS_REDUCED) {    # PPI NO PARSE --  can't be reduced if the module isn't loaded
                    my $target_euid = "$>";
                    my $target_egid = ( split( m{ }, "$)" ) )[0];
                    Cpanel::AccessIds::ReducedPrivileges::_restore_privileges( 0, 0 );    # PPI NO PARSE -- we will never get here if ReducedPrivileges wasn't loaded
                    Cpanel::LoadModule::load_perl_module('Cpanel::Sys::Setsid::Fast') if !$INC{'Cpanel/Sys/Setsid/Fast.pm'};
                    Cpanel::Sys::Setsid::Fast::fast_setsid();
                    Cpanel::LoadModule::load_perl_module('Cpanel::AccessIds::SetUids') if !$INC{'Cpanel/AccessIds/SetUids.pm'};
                    Cpanel::AccessIds::SetUids::setuids( $target_euid, $target_egid );
                }

                if ( $OPTS{'before_exec'} ) {
                    $OPTS{'before_exec'}->();
                }

                my $user    = $OPTS{'user'};
                my $homedir = $OPTS{'homedir'};
                if ( !$user || !$homedir ) {
                    Cpanel::LoadModule::load_perl_module('Cpanel::PwCache') if !$INC{'Cpanel/PwCache.pm'};
                    my ( $pw_user, $pw_homedir ) = ( Cpanel::PwCache::getpwuid_noshadow($>) )[ 0, 7 ];
                    $user    ||= $pw_user;
                    $homedir ||= $pw_homedir;
                }
                die "Invalid EUID: $>" if !$user || !$homedir;

                #TODO: Use //= once it's safe in compiled code.
                $ENV{'HOME'} = $homedir       if !defined $ENV{'HOME'};    # always cleared by clean_env, but may be reset in before_exec
                $ENV{'USER'} = $user          if !defined $ENV{'USER'};    # always cleared by clean_env, but may be reset in before_exec
                $ENV{'TMP'}  = "$homedir/tmp" if !defined $ENV{'TMP'};
                $ENV{'TEMP'} = "$homedir/tmp" if !defined $ENV{'TEMP'};

                exec( $OPTS{'program'}, @$args_ar ) or die "$exec_failed_message $!";
            }
        );
    }

    if ( $OPTS{'after_fork'} ) {
        $OPTS{'after_fork'}->( $self->{'_child_pid'} );
    }

    if ($close_child_reads) {    #only close it if we opened it
        close $child_reads or die "close() failed: $!";
    }

    # It's the caller's responsibility to close the filehandle they opened
    # Loop unrolled for speed
    if ( $parent_read_fh{'stdout'} ) {
        close $child_write_fh{'stdout'} or die "close() failed: $!";
    }

    if ( !$merge_output_yn && $parent_read_fh{'stderr'} ) {
        close $child_write_fh{'stderr'} or die "close() failed: $!";
    }

    if ($parent_writes) {
        if ( ref $OPTS{'stdin'} eq 'CODE' ) {

            #Here we do NOT control the writes, so we leave SIGPIPE in place.
            $OPTS{'stdin'}->($parent_writes);
        }
        else {

            #We control the writes, and we check them all,
            #so we can suppress SIGPIPE. We use autoflush to ensure
            #that everything is written out while SIGPIPE is suppressed.
            local $SIG{'PIPE'} = 'IGNORE';
            Cpanel::FHUtils::Autoflush::enable($parent_writes);

            if ($pump_stdin_filehandle_into_child) {
                my $buffer;

                my $is_os_stdin = Cpanel::FHUtils::OS::is_os_filehandle( $OPTS{'stdin'} );

                local $!;

                if ($is_os_stdin) {
                    while ( IO::SigGuard::sysread( $OPTS{'stdin'}, $buffer, $CHUNK_SIZE ) ) {
                        $self->_write_buffer_to_fh( $buffer, $parent_writes );
                    }
                }
                else {
                    while ( read $OPTS{'stdin'}, $buffer, $CHUNK_SIZE ) {
                        $self->_write_buffer_to_fh( $buffer, $parent_writes );
                    }
                }

                if ($!) {
                    die Cpanel::Exception::create( 'IO::ReadError', 'The system failed to read up to [format_bytes,_1] from the filehandle that contains standard input for the process that is running the command “[_2]”. This failure happened because of an error: [_3]', [ $CHUNK_SIZE, "$OPTS{'program'} @$args_ar", "$!" ] );
                }
            }
            else {
                my $to_print_r = ( ref $OPTS{'stdin'} eq 'SCALAR' ) ? $OPTS{'stdin'} : \$OPTS{'stdin'};

                if ( length $$to_print_r ) {
                    $self->_write_buffer_to_fh( $$to_print_r, $parent_writes );
                }
            }
        }

        # If the close fails, we still want to read the output
        # and errors since it may still be running but stopped
        # accepting input over STDIN.  That’s not always
        # a fatal error, and it’s important that we still
        # return enough information to be able to determine
        # what went wrong.
        close $parent_writes or warn "close() failed: $!";
    }

    my $reader;
    my $err_obj;

    my @filehandles = map { $parent_read_fh{$_} ? [ $parent_read_fh{$_}, $OPTS{$_} ] : () } qw( stdout stderr );

    if (@filehandles) {
        local $@;
        eval {
            $reader = Cpanel::ReadMultipleFH->new(
                filehandles  => \@filehandles,
                timeout      => $OPTS{'timeout'},
                read_timeout => $OPTS{'read_timeout'},
            );
        };
        $err_obj = $@;
    }

    if ( $parent_read_fh{'stdout'} ) {
        close $parent_read_fh{'stdout'} or warn "parent close(stdout) failed: $!";
    }

    if ( $parent_read_fh{'stderr'} && !$merge_output_yn ) {
        close $parent_read_fh{'stderr'} or warn "parent close(stderr) failed: $!";
    }

    if ($err_obj) {
        $self->{'_CHILD_ERROR'} = $self->_safe_kill_child();
        die $err_obj;
    }
    elsif ($reader) {
        if ( !$reader->did_finish() ) {
            $self->{'_timed_out_after'} = $reader->timed_out();
            $self->{'_CHILD_ERROR'}     = $self->_safe_kill_child();
        }

        $self->{"_stdout"} = $parent_read_fh{stdout} && $reader->get_buffer( $parent_read_fh{stdout} );

        # stderr may already have content from a prior error
        if ( !$self->{"_stderr"} ) {
            $self->{"_stderr"} = $parent_read_fh{stderr} && $reader->get_buffer( $parent_read_fh{stderr} );
        }
    }

    if ( !defined $self->{'_CHILD_ERROR'} ) {

        #The child process must never have this,
        #or else the parent won't receive the child's exit status.
        local $?;

        waitpid( $self->{'_child_pid'}, 0 ) if defined $self->{'_child_pid'};
        $self->{'_CHILD_ERROR'} = $?;

        if ( $self->{'_CHILD_ERROR'} ) {
            $self->{'_exec_failed'} = 1;
        }
    }

    # A compatibility hack to make fastspawn results
    # compatible with non-fastspawn results (exit 127)
    if ( $used_fastspawn && $self->{'_CHILD_ERROR'} == 32512 ) {
        $self->{'_CHILD_ERROR'} = _ENOENT() << 8;
        $self->{'_exec_failed'} = 1;
        ${ $self->{'_stderr'} } .= "$exec_failed_message $!";

        # We can only detect exec failed if we have stderr
    }
    elsif ( !$used_fastspawn && $self->{'_stderr'} && $self->{'_CHILD_ERROR'} && ( $self->{'_CHILD_ERROR'} >> 8 ) == 2 && index( ${ $self->{'_stderr'} }, $exec_failed_message ) > -1 ) {
        $self->{'_exec_failed'} = 1;
    }

    return $self;
}

sub _write_buffer_to_fh ( $self, $buffer, $fh ) {
    while ( length $buffer ) {
        my $wrote = IO::SigGuard::syswrite( $fh, $buffer ) or die $self->_write_error( \$buffer, $! );
        substr( $buffer, 0, $wrote, q<> );
    }

    return;
}

# this is intended to reduce boilerplate of handling problems with running programs. #
# if you need more advanced error handling, you should not use this interface #
sub new_or_die {
    my ( $class, @args ) = @_;
    return $class->new(@args)->die_if_error();
}

# This needs to be overridden to be able to produce a timeout in addition to error or signal codes:
sub to_exception {
    my ($self) = @_;

    if ( $self->timed_out() ) {
        return Cpanel::Exception::create(
            'ProcessFailed::Timeout',
            [
                process_name => $self->program(),
                ( $self->child_pid() ? ( pid => $self->child_pid() ) : () ),
                timeout => $self->timed_out(),
                $self->_extra_error_args_for_die_if_error(),
            ],
        );
    }

    return $self->SUPER::to_exception();
}

sub _extra_error_args_for_die_if_error {
    my ($self) = @_;
    return (
        stdout => $self->{'_stdout'} ? $self->stdout() : '',
        stderr => $self->{'_stderr'} ? $self->stderr() : '',
    );
}

sub _safe_kill_child {
    my ($self) = @_;
    Cpanel::LoadModule::load_perl_module('Cpanel::Kill::Single');
    return 'Cpanel::Kill::Single'->can('safekill_single_pid')->( $self->{'_child_pid'}, $SAFEKILL_TIMEOUT );    # One second to die
}

sub stdout_r {
    if ( !$_[0]->{'_stdout'} ) {
        Cpanel::LoadModule::load_perl_module('Cpanel::Carp');
        die 'Cpanel::Carp'->can('safe_longmess')->("STDOUT output went to filehandle!");
    }

    return $_[0]->{'_stdout'};
}

sub _additional_phrases_for_autopsy {
    if ( $_[0]->timed_out() ) {
        return Cpanel::LocaleString->new( 'The system aborted the subprocess because it reached the timeout of [quant,_1,second,seconds].', $_[0]->timed_out() );
    }

    return;
}

#Convenience
sub stdout {
    return ${ $_[0]->stdout_r() };
}

sub stderr_r {
    if ( !$_[0]->{'_stderr'} ) {
        Cpanel::LoadModule::load_perl_module('Cpanel::Carp');
        die 'Cpanel::Carp'->can('safe_longmess')->("STDERR output went to filehandle!");
    }

    return $_[0]->{'_stderr'};
}

#Convenience
sub stderr {
    return ${ $_[0]->stderr_r() };
}

sub child_pid {
    return $_[0]->{'_child_pid'};
}

sub timed_out {
    return $_[0]->{'_timed_out_after'};
}

sub program {
    return $_[0]->{'_program'};
}

sub _program_with_args_str {
    my $args_ar = $_[0]->{'_args'};
    return $_[0]->{'_program'} . ( ( $args_ar && ref $args_ar && scalar @$args_ar ) ? " @$args_ar" : '' );
}

#----------------------------------------------------------------------
#Overrides of Cpanel::ChildErrorStringifier;
#consult that class’s internal docs for more details.

sub _ERROR_PHRASE {
    my ($self) = @_;

    #
    # numf loads Locales.pm so it has been removed to avoid
    # calling get_locales_obj
    #
    return Cpanel::LocaleString->new( 'The “[_1]” command (process [_2]) reported error number [_3] when it ended.', $self->_program_with_args_str(), $self->{'_child_pid'}, $self->error_code() );
}

sub _SIGNAL_PHRASE {
    my ($self) = @_;

    return Cpanel::LocaleString->new( 'The “[_1]” command (process [_2]) ended prematurely because it received the “[_3]” ([_4]) signal.', $self->_program_with_args_str(), $self->{'_child_pid'}, $self->signal_name(), $self->signal_code() );
}

#----------------------------------------------------------------------

sub _write_error {
    my ( $self, $buffer_sr, $OS_ERROR ) = @_;

    my @cmd = ( $self->{'_program'}, @{ $self->{'_args'} } );

    return Cpanel::Exception::create( 'IO::WriteError', 'The system failed to send [format_bytes,_1] to the process that is running the command “[_2]” because of an error: [_3]', [ length($$buffer_sr), "@cmd", $OS_ERROR ], { length => length($$buffer_sr), error => $OS_ERROR } );
}

#----------------------------------------------------------------------

=head1 COOKBOOK

Below are examples of how to use this module to implement a number
of common use cases for running commands.

=head2 Diagnose failure in detail:

    # FYI: this still throws if the command fails to start.
    my $run = Cpanel::SafeRun::Object->new(
        program => '/path/to/command',
    );

    # The below methods come from Cpanel::ChildErrorStringifier:

    if (my $signum = $run->signal_code()) {
        my $signame = $run->signal_name();

        ...
    }
    elsif ($my $errnum = $run->error_code()) {
        ...
    }

You can also:

    $run->die_if_error();

Or, to get a human-readable description of the exit status:

    say $run->autopsy();

=head2 Diagnose thrown error from C<new_or_die()>:

    Cpanel::Try::try(
        sub {
            Cpanel::SafeRun::Object->new_or_die(
                program => '/path/to/command',
            );
        },

        # See these exception classes’ documentation for
        # more details:

        'Cpanel::Exception::ProcessFailed::Signal' => sub ($err) {
        },

        'Cpanel::Exception::ProcessFailed::Error' => sub ($err) {
        },

        'Cpanel::Exception::ProcessFailed::Timeout' => sub ($err) {
        },
    );

=head2 Send the child’s output to the parent’s STDOUT/STDERR:

    Cpanel::SafeRun::Object->new_or_die(
        program => '/path/to/command',

        stdout => \*STDOUT,
        stderr => \*STDERR,
    );

=head2 Process output line-by-line:

    use Cpanel::IOCallbackWriteLine ();

    Cpanel::SafeRun::Object->new_or_die(
        program => '/path/to/command',

        stdout => Cpanel::IOCallbackWriteLine->new(
            sub ($line) {
                # ...
            },
        ),
    );

=head2 Set a read filehandle as the child’s STDIN:

    my $fh = Cpanel::TempFH::create();

    syswrite $fh, 'hello!';
    sysseek $fh, 0, 0;

    Cpanel::SafeRun::Object->new_or_die(
        program => '/path/to/command',

        stdin => $fh,
    );

=head2 Run the command with different privileges or environment:

    Cpanel::SafeRun::Object->new_or_die(
        program => '/path/to/command',

        before_exec => sub {
            Cpanel::AccessIds::SetUids::setuids('suzie');

            $ENV{'WHATEVER'} = 'Hi, mom!'
        },
    );

=cut

1;
