package Cpanel::Logger;

# cpanel - Cpanel/Logger.pm                        Copyright 2022 cPanel, L.L.C.
#                                                           All rights reserved.
# copyright@cpanel.net                                         http://cpanel.net
# This code is subject to the cPanel license. Unauthorized copying is prohibited

use strict;
## no critic qw(TestingAndDebugging::RequireUseWarnings)

# Dynamically loading modules in the common logging paths breaks perlinstaller.
use Cpanel::Time::Local ();

my $is_sandbox;
my $is_smoker;
our $VERSION = 1.3;

use constant TRACE_TOUCH_FILE => '/var/cpanel/log_stack_traces';

# This variable now only exists to accommodate users who perform overrides using lexical scoping.
# Ideally no one should need to use this in new code.
our $ENABLE_BACKTRACE;

our $DISABLE_OUTPUT;    # used by cpanminus
our $ALWAYS_OUTPUT_TO_STDERR;

# Used to set the log file
#   This value is best set via the environment variable 'CPANEL_LOGGER_FILE',
#   where all Cpanel::Logger objects will inherit the value.
#   Logs are relegated to the directory '/usr/local/cpanel/logs'.
#
#   This contrasts with the constructor argument of 'alternate_logfile' by giving a means to
#   override this value in the call itself.
our $STD_LOG_FILE   = '/usr/local/cpanel/logs/error_log';
our $PANIC_LOG_FILE = '/usr/local/cpanel/logs/panic_log';

my ( $cached_progname, $cached_prog_pid, %singleton_stash );

#########################################################################
#
# Method:
#   new
#
# Description:
#   Create a logger object
#
# Parameters (hashref):
#
#   open_now          - Open the log file when object in instantiated instead of
#                       immediately before writing.  This is expected to be
#                       used when the logger is running inside a daemon.
#
#   use_no_files      - If set the logger object will only write to
#                       STDERR/STDOUT based on the output flag in each call
#                       to logger
#                       output : 0 no output, 1 STDOUT, 2 STDERR
#
#   alternate_logfile - By default the logger logs message to $STD_LOG_FILE
#                       This argument allows specifying an alternate log file.
#
#   log_pid           - boolean, whether to include the PID in log entries
#
#   backtrace         - If true, the logger object will print backtraces where allowed.
#                       If defined but false, the logger object will not print backtraces unless otherwise required.
#                       If undefined, this decision is left to whether the file at TRACE_TOUCH_FILE exists.
#                       The $ENABLE_BACKTRACE package variable allows local overriding of this value, regardless of how it is set in the object.
#
# Returns:
#   A logger object singleton
#
sub new {
    my ( $class, $hr_args ) = @_;

    if ( $hr_args->{'open_now'} && $hr_args->{'use_no_files'} ) {
        die "“open_now” and “use_no_files” mutually exclude!";
    }

    my $args_sig = 'no_args';
    if ( $hr_args && ref($hr_args) eq 'HASH' ) {

        # this serialization is by no means fool proof (e.g. "'x=>' => 'y'" && "'x' => '=>y'") but it should be sufficiently "bad idea" proof
        # it's also faster and less memory intensive than Storable
        # Storable would be much more robust but requires bringing in  Storable (which might be free anyway since we use Storable for cache speed)
        $args_sig = join( ',', map { $_ . '=>' . $hr_args->{$_} } sort keys %{$hr_args} );    # Storable::freeze($hr_args);
    }

    my $no_load_from_cache = $hr_args->{'no_load_from_cache'} ? 1 : 0;

    if ( exists $singleton_stash{$class}{$args_sig} and !$no_load_from_cache ) {
        $singleton_stash{$class}{$args_sig}->{'cloned'}++;
    }
    else {
        $singleton_stash{$class}{$args_sig} = bless( {}, $class );
        if ( $hr_args && ref($hr_args) eq 'HASH' ) {
            foreach my $k ( keys %$hr_args ) {
                $singleton_stash{$class}{$args_sig}->{$k} = $hr_args->{$k};
            }
        }
    }
    my $self = $singleton_stash{$class}{$args_sig};

    if ( !$self->{'cloned'} ) {

        # Lets not leak memory by default
        if ( $self->{'open_now'} && !$self->{'use_no_files'} ) {
            $self->_open_logfile();
        }
    }

    # Normalize the value of the backtrace property if one was given:
    $self->_set_backtrace( $ENABLE_BACKTRACE // $self->{'backtrace'} // _get_backtrace_touchfile() );

    return $self;
}

#
# when or where Logger is implemented in non-OO sense
# fake it out
#
sub __Logger_pushback {
    if ( @_ && index( ref( $_[0] ), __PACKAGE__ ) == 0 ) {
        return @_;
    }
    return ( __PACKAGE__->new(), @_ );
}

# This is to be used to catch programming mistakes such as improper or missing arguments
sub invalid {
    my ( $self, @list ) = __Logger_pushback(@_);

    my %log = (
        'message'   => $list[0],
        'level'     => 'invalid',
        'output'    => 0,
        'service'   => $self->find_progname(),
        'backtrace' => $self->get_backtrace(),
        'die'       => 0,
    );

    if ( is_sandbox() ) {
        if ( !-e '/var/cpanel/DEBUG' ) {
            $self->notify( 'invalid', \%log );
        }
        $log{'output'} = _stdin_is_tty() ? 2 : 1;
    }
    return $self->logger( \%log );
}    # end of invalid

sub is_sandbox {
    return 0           if $INC{'B/C.pm'};        # avoid cache during compile
    return $is_sandbox if defined $is_sandbox;
    return ( $is_sandbox = -e '/var/cpanel/dev_sandbox' ? 1 : 0 );
}

sub is_smoker {
    return 0          if $INC{'B/C.pm'};         # avoid cache during compile
    return $is_smoker if defined $is_smoker;
    return ( $is_smoker = -e '/var/cpanel/smoker' ? 1 : 0 );
}

# This is just like invalid but it causes the system to die on a sandbox.
sub deprecated {    ## no critic qw(Subroutines::RequireArgUnpacking)
    my ( $self, @list ) = __Logger_pushback(@_);

    my %log = (
        'message'   => $list[0],
        'level'     => 'deprecated',
        'output'    => 0,
        'service'   => $self->find_progname(),
        'backtrace' => $self->get_backtrace(),
        'die'       => 0,
    );

    unless ( is_sandbox() ) {
        $self->logger( \%log );
        return;
    }

    $self->notify( 'deprecated', \%log );

    $log{'output'} = _stdin_is_tty() ? 2 : 1;
    $log{'die'}    = 1;

    return $self->logger( \%log );
}

sub debug {
    my ( $self, $message, $conf_hr ) = @_;    # not appropriate for debug() : __Logger_pushback(@_);

    $self = $self->new() if !ref $self;

    $conf_hr ||= {
        'force'     => 0,
        'backtrace' => 0,
        'output'    => 1,    # Logger's debug level should output to STDOUT
    };
    return unless $conf_hr->{'force'} || ( defined $Cpanel::Debug::level && $Cpanel::Debug::level );    ## PPI NO PARSE - avoid recursive use statements

    # $message ||= "debug() at " . __FILE__ . " line " . __LINE__;
    if ( !defined $message ) {
        my @caller = caller();
        $message = "debug() at $caller[1] line $caller[2].";
    }

    my %log = (
        'message'   => $message,
        'level'     => 'debug',
        'output'    => $conf_hr->{'output'},
        'backtrace' => $conf_hr->{'backtrace'},
    );

    if ( ref $log{'message'} ) {

        # Must be quoted on perlcc will compile in YAML::Syck
        my $outmsg = $log{'message'};
        eval 'local $SIG{__DIE__}; local $SIG{__WARN__}; require Cpanel::YAML::Syck; $outmsg = YAML::Syck::Dump($outmsg);';
        my @caller = caller();
        $log{'message'} = "$log{'message'} at $caller[1] line $caller[2]:\n" . $outmsg;
    }
    elsif ( $log{'message'} =~ m/\A\d+(?:\.\d+)?\z/ ) {
        $log{'message'} = "debug() number $log{'message'}";
    }

    $self->logger( \%log );

    return \%log;
}

#
# This is use to provide incidental information that is not an error.
# Message should be verbose as there is no backtrace
#
sub info {
    my ( $self, @list ) = __Logger_pushback(@_);
    return $self->logger(
        {
            'message' => $list[0],
            'level'   => 'info',

            # If we have open_now set do not write to STDOUT as it won't be a terminal
            # ever
            'output'    => $self->{'open_now'} ? 0 : 1,    # FB#59177: info level should output to STDOUT
            'backtrace' => 0

        }
    );
}    # end of info

# Used to replace regular warn
sub warn {
    my ( $self, @list ) = __Logger_pushback(@_);
    return $self->logger(
        {
            'message'   => $list[0],
            'level'     => 'warn',
            'output'    => _stdin_is_tty() ? 2 : 0,
            'backtrace' => $self->get_backtrace()
        }
    );
}    # end of warn

# Used to replace regular error
sub error {
    my ( $self, @list ) = __Logger_pushback(@_);
    return $self->logger(
        {
            'message'   => $list[0],
            'level'     => 'error',
            'output'    => -t STDIN ? 2 : 0,
            'backtrace' => $self->get_backtrace()
        }
    );
}    # end of error

# Used to replace regular die
sub die {
    my ( $self, @list ) = __Logger_pushback(@_);
    my %log = (
        'message'   => $list[0],
        'level'     => 'die',
        'output'    => _stdin_is_tty() ? 2 : 0,
        'backtrace' => $self->get_backtrace()
    );
    return $self->logger( \%log );
}    # end of die

# Used to replace regular die and log message to separate log file so that
# it is preserved
sub panic {
    my ( $self, @list ) = __Logger_pushback(@_);
    my %log = (
        'message'   => $list[0],
        'level'     => 'panic',
        'output'    => 2,
        'backtrace' => $self->get_backtrace()
    );
    return $self->logger( \%log );
}    # end of panic

#
# This is used to provide raw logging and must be called in
# object context. The return value and setting of $!/$^E is
# the same as for logger().
#
sub raw {
    return $_[0]->logger(
        {
            'message'   => $_[1],
            'level'     => 'raw',
            'output'    => 0,
            'backtrace' => 0
        }
    );
}

#
# Deprecated behavior. Usage needs to be replaced throughout
# nostdout: 0 or undef prints to STDOUT if -t STDOUT
#           1 suppress STDOUT
# at present where used isn't converted into OO operational
#
sub cplog {
    my $msg      = shift;
    my $loglevel = shift;
    my $service  = shift;
    my $nostdout = shift;
    if ( !$nostdout ) {
        $nostdout = 1;
    }
    else {
        $nostdout = 0;
    }
    logger( { 'message' => $msg, 'level' => $loglevel, 'service' => $service, 'output' => $nostdout, 'backtrace' => $ENABLE_BACKTRACE // _get_backtrace_touchfile() } );
}    # end of cplog (deprecated)

# get hash configuration from configuration or message

sub _get_configuration_for_logger {
    my ( $self, $cfg_or_msg ) = @_;

    my $hr = ref($cfg_or_msg) eq 'HASH' ? $cfg_or_msg : { 'message' => $cfg_or_msg };

    # default values
    $hr->{'message'} ||= 'Something is wrong';

    # very telling :-/
    $hr->{'level'}  ||= '';
    $hr->{'output'} ||= 0;

    # use this variable to disable all output (used by cpanm)
    $hr->{'output'} = 0 if $DISABLE_OUTPUT;
    if ( !exists $hr->{'backtrace'} ) {
        $hr->{'backtrace'} = $self->get_backtrace();
    }

    # this flag disable any file logging ( can be used when mocking )
    $hr->{'use_no_files'} ||= 0;
    $hr->{'use_fullmsg'}  ||= 0;

    return $hr;
}

# we can mock it if needed
sub _write {
    return print { $_[0] } $_[1];
}

sub get_backtrace {
    my ($self) = __Logger_pushback(@_);

    # if defined, always allow the variable to override instances
    return $ENABLE_BACKTRACE // $self->{'backtrace'};
}

sub _set_backtrace {
    my ( $self, @args ) = __Logger_pushback(@_);
    $self->{'backtrace'} = $args[0] ? 1 : 0;
    return;
}

sub _get_backtrace_touchfile {
    return -e TRACE_TOUCH_FILE ? 1 : 0;
}

# Cpanel::AttributeProvider not used here because
# Cpanel::Logger needs to stay lightweight
sub get_fh {
    my ($self) = @_;
    return $self->{'log_fh'};
}

# Cpanel::AttributeProvider not used here because
# Cpanel::Logger needs to stay lightweight
sub set_fh {
    my ( $self, $fh ) = @_;
    $self->{'log_fh'} = $fh;
    return 1;
}
#
# Arguments: a hash reference containing these keys
# message : User defined message
# level : logging level
#             die,  panic                - causes exit
#             invalid, deprecated, panic - writes to ULC/logs/panic_log
#             info, warn, error, debug   - written to log in the [time] [level] [service] backtrace? [message] format
#             raw                        - messages are written directly to the log
# service : message origin, in modules use __PACKAGE__
# output : 0 no output, 1 STDOUT, 2 STDERR
# backtrace : on by default, true log Carp::longmess, false suppress Carp::longmess
# log_pid: off by default, includes the pid in the log message
#
# Returns:
#  0 - at least one write to the log failed
#  1 - all log log writes successful
#
#  This sets $! to the most recent I/O error; unfortunately, there
#  are several things that this function does internally, so that variable may
#  or may not tell you anything useful. TODO: A redesign of this module should
#  take this into account and fix it!
#
sub logger {    ## no critic(RequireArgUnpacking)
    my ( $self, @list ) = __Logger_pushback(@_);
    my $hr = $self->_get_configuration_for_logger( $list[0] );
    my ( $msg, $time, $status );
    $status = 1;

    my ($msg_maybe_bt) = $hr->{'backtrace'} ? $self->backtrace( $hr->{'message'} ) : $hr->{'message'} . "\n";

    if ( $hr->{'level'} eq 'raw' ) {
        $msg = $hr->{'message'};
    }
    else {
        $time ||= Cpanel::Time::Local::localtime2timestamp();
        $hr->{'service'} ||= $self->find_progname();                       # only compute the service name if we HAVE to do so as it can be expensive

        # To remove EACCES errors seen in strace, we need to verify that the log
        # file either does not exist or is writable.
        # Otherwise, the code works the same with and without the check.
        #   if we do not want to use any file, do not try to open them
        if ( $self->{'log_pid'} ) {
            $msg = "[$time] $hr->{'level'} [$hr->{'service'}] [$$] $msg_maybe_bt";
        }
        else {
            $msg = "[$time] $hr->{'level'} [$hr->{'service'}] $msg_maybe_bt";
        }
    }
    unless ( $hr->{'use_no_files'} ) {

        local $self->{'log_fh'} = \*STDERR if $ALWAYS_OUTPUT_TO_STDERR;

        # TODO: Remove IO::Scalar usage when we finish converting
        # legacy 5.6 code.  Note: UNIVERSAL used here instead of eval/->isa for speed
        $self->_open_logfile() if !$self->{'log_fh'} || ( !eval { fileno( $self->{'log_fh'} ) } && !UNIVERSAL::isa( $self->{'log_fh'}, 'IO::Scalar' ) );
        _write( $self->{'log_fh'}, $msg ) or $status = 0;

        if ( $hr->{'level'} eq 'panic' || $hr->{'level'} eq 'invalid' || $hr->{'level'} eq 'deprecated' ) {
            my $panic_fh;
            require Cpanel::FileUtils::Open;
            if ( Cpanel::FileUtils::Open::sysopen_with_real_perms( $panic_fh, $PANIC_LOG_FILE, 'O_WRONLY|O_APPEND|O_CREAT', 0600 ) ) {
                $time ||= Cpanel::Time::Local::localtime2timestamp();
                $hr->{'service'} ||= $self->find_progname();                       # only compute the service name if we HAVE to do so as it can be expensive
                _write( $panic_fh, "$time $hr->{level} [$hr->{'service'}] $msg_maybe_bt" );
                close $panic_fh;
            }
        }
    }

    if ( $hr->{'output'} ) {
        $hr->{'service'} ||= $self->find_progname();    # only compute the service name if we HAVE to do so as it can be expensive
        my $out = "$hr->{level} [$hr->{'service'}] $hr->{'message'}\n";
        if ( $self->{'timestamp_prefix'} ) {
            $out = "[$time] $out";
        }
        $out = $msg if $hr->{'use_fullmsg'};

        $status &&= $self->_write_message( $hr, $out );
    }

    # goes away anyway if STDERR
    if ( ( $hr->{'level'} eq 'die' || $hr->{'level'} eq 'panic' || $hr->{'die'} ) ) {
        CORE::die "exit level [$hr->{'level'}] [pid=$$] ($hr->{'message'})\n";    # make sure we die if die is overwritten
    }

    return $status;
}    # end of logger

sub _write_message {
    my ( $self, $hr, $out ) = @_;
    my $status = 1;

    # not a used output type
    if ( $hr->{'output'} == 3 ) {
        _write( \*STDOUT, $out ) or $status = 0;
        _write( \*STDERR, $out ) or $status = 0;
    }
    elsif ( $hr->{'output'} == 1 && ( $self->{'use_stdout'} || _stdout_is_tty() ) ) {
        _write( \*STDOUT, $out ) or $status = 0;
    }
    elsif ( $hr->{'output'} == 2 ) {
        _write( \*STDERR, $out ) or $status = 0;
    }
    return $status;
}

#
# so the short forms can have it too
#
sub find_progname {
    if ( $cached_progname && $cached_prog_pid == $$ ) {
        return $cached_progname;
    }
    my $s = $0;

    if ( !length $s ) {    # Someone _could_ set $0 = '';
        my $i = 1;         # 0 is always find_progname
        while ( my @service = caller( $i++ ) ) {
            last             if ( $service[3] =~ /::BEGIN$/ );
            $s = $service[1] if ( $service[1] ne '' );
        }
    }

    # remove path elements so we don't create exploits in log display/parse
    $s =~ s@.+/(.+)$@$1@ if $s =~ tr{/}{};

    # and file extensions -- ie cpsrvd.pl -> logs as cpsrvd
    $s =~ s@\..+$@@ if $s =~ tr{\.}{};

    # and after a space so we don't break log parsers
    $s =~ s@ .*$@@ if $s =~ tr{ }{};

    $cached_progname = $s;
    $cached_prog_pid = $$;

    return $s;
}

#
sub backtrace {    ## no critic qw(Subroutines::RequireArgUnpacking)
    my ( $self, @list ) = __Logger_pushback(@_);
    if ( ref $list[0] ) {
        return $list[0] if scalar @list == 1;
        return (@list);
    }
    require Cpanel::Carp;
    local $_;    # Protect surrounding program - just in case...
    local $Carp::Internal{ (__PACKAGE__) } = 1;
    local $Carp::Internal{'Cpanel::Debug'} = 1;
    return Cpanel::Carp::safe_longmess(@list);

}

sub redirect_stderr_to_error_log {
    return open( STDERR, '>>', $STD_LOG_FILE );
}

sub notify {
    my ( $self, $call, $log_ref ) = @_;

    # Note  $log_ref->{'subject'} will override the subject for legacy
    # compat
    my $time = Cpanel::Time::Local::localtime2timestamp();
    my ($bt) = $self->backtrace( $log_ref->{'message'} );
    $log_ref->{'service'} //= '';
    my $logfile = qq{$time [$log_ref->{'service'}] } . ( $bt // '' );

    if ( eval { require Cpanel::LoadModule; Cpanel::LoadModule::load_perl_module('Cpanel::iContact::Class::Logger::Notify'); 1; } ) {

        # This might be running as an unprivileged user, and failure here
        # prevents the user from seeing the real deprecated message.
        eval {
            require Cpanel::Notify;
            Cpanel::Notify::notification_class(
                'class'            => 'Logger::Notify',
                'application'      => 'Logger::Notify',
                'constructor_args' => [
                    'origin'       => $log_ref->{'service'},
                    'logger_call'  => $call,
                    'attach_files' => [ { name => 'cpanel-logger-log.txt', content => \$logfile } ],
                    'subject'      => $log_ref->{'subject'},
                ]
            );
        };

    }

    # fallback if Logger::Notify iContact class doesn't exist
    elsif ( eval { require Cpanel::LoadModule; Cpanel::LoadModule::load_perl_module('Cpanel::iContact'); 1; } ) {
        Cpanel::iContact::icontact(
            'application' => $log_ref->{'service'},
            'subject'     => $log_ref->{'subject'} ? $log_ref->{'subject'} : qq{Cpanel::Logger::$call called in $log_ref->{'service'}},
            'message'     => $logfile,
        );

        # if everything is missing warn
    }
    else {
        CORE::warn( $log_ref->{'subject'} ? $log_ref->{'subject'} : qq{Cpanel::Logger::$call called in $log_ref->{'service'}} . ": $logfile" );
    }

    return;
}

# Aliases for compatibility with Cpanel::Update::Logger, Cpanel::Output, and Cpanel::LoggerAdapter
*fatal   = *die;
*out     = *info;
*success = *info;
*throw   = *die;
*warning = *warn;

sub _is_subprocess_of_cpsrvd {
    require Cpanel::Server::Utils;
    goto \&Cpanel::Server::Utils::is_subprocess_of_cpsrvd;
}

sub _open_logfile {
    my ($self) = @_;
    my $usingstderr = 0;
    my $log_fh;

    $self->{'alternate_logfile'} ||= $STD_LOG_FILE;
    if ( $STD_LOG_FILE eq $self->{'alternate_logfile'} && _is_subprocess_of_cpsrvd() ) {
        $log_fh      = \*STDERR;
        $usingstderr = 1;
    }
    else {
        # Note: we do not warn here because its quite possible Cpanel::Logger is being
        # called as a user and cannot write to the log file we want.  At this point the system
        # expects to write to STDERR and not warn about it.
        require Cpanel::FileUtils::Open;
        if ( !Cpanel::FileUtils::Open::sysopen_with_real_perms( $log_fh, $self->{'alternate_logfile'}, 'O_WRONLY|O_APPEND|O_CREAT', 0600 ) ) {
            ( $usingstderr, $log_fh ) = ( 1, \*STDERR );
        }

        # Disable buffering to ensure log is written right away
        # since we no longer use syswrite since
        # syswrite() is deprecated on :utf8 handles and will be fatal in perl 5.30
        select( ( select($log_fh), $| = 1 )[0] );    ## no critic qw(Variables::RequireLocalizedPunctuationVars InputOutput::ProhibitOneArgSelect) -- Cpanel::FHUtils::Autoflush would be expensive to load every time
    }

    $self->{'log_fh'}      = $log_fh;
    $self->{'usingstderr'} = $usingstderr;
    return 1;
}

# This traps exceptions so that it works
# even under “small” tests.
sub _stdin_is_tty {
    local $@;
    return eval { -t STDIN };
}

# This traps exceptions so that it works
# even under “small” tests.
sub _stdout_is_tty {
    local $@;
    return eval { -t STDOUT };
}

# This should only ever be needed if the cached singleton is known to be in a bad / non-working state.
sub clear_singleton_stash {
    %singleton_stash = ();
    return;
}

1;

__END__

=head1 Simple to use logging!

    See also tests/Cpanel-Logger.t for other working examples.

    my $cplog = Cpanel::Logger->new();

    # the main OO interface
    $cplog->info("Just wanted to log some info");
    $cplog->warn("I am a warning");
    $cplog->error("I am an error");
    $cplog->die("I will die");
    $cplog->panic("I will die loudly and be recorded forever in the panic log");

    my %msg = (
        'message'   => $args{'title'},
        'service'   => $args{'summary'},
        'output'    => 0,
        'backtrace' => 1,
        # Logger knows about info, warn, error, die, panic
        'level' => ''
    );

    $cplog->logger(\%msg);
    ...

=head2 Using alternative log file targets

    The default log targets are '/usr/local/cpanel/logs/error_log' for
    standard log messages (warn, error, die, info, debug, and panic*). The log
    level of panic is sent to a secondary log file,
    '/usr/local/cpanel/logs/panic_log'.

    * panic messages are sent to the standard log file and the panic_log
      file

    To specify an alternative log target:

    This can be done at the time of object creation or manipulated directly in
    the object. This log target is only valid for the object currently within
    scope of the change.

=head2 For development sanity checking:

    $cplog->invalid("Log useful info on public builds,
    in development builds I email a message to the server contact.");

    This is disabled by touching /var/cpanel/DEBUG

=head2 To catch calls which should be discouraged

    # Dies on a sandbox
    # Warns on all systems
    $cplog->deprecated("FOO::Bar::baz() is deprecated. Call Bar::Baz::bee() instead");

=head2 debug() for development, QA, and troubleshooting

   $logger->debug(@ARGS);

This only does anything if $Cpanel::Debug::level is true (or you force it)

For convienience, this method can also be called as a class method:

   Cpanel::Logger->debug(@ARGS);

The arguments are:

=over 4

=item 1 debug data

nothing/undef, String message, reference to output in YAML, number/decimal

   $logger->debug()
   $logger->debug(undef, {force=>1});

   debug() at tests/Cpanel-Logger.t line 252.

   $logger->debug("I was able to get here");

   debug [Cpanel-Logger] I was able to get here

   $logger->debug(\%hash);

   debug [Cpanel-Logger] HASH(0x831f084) at tests/Cpanel-Logger.t line 256:
   ---
   a: 1

   $logger->debug(42);

   if ($x) {
      $logger->debug(42.1);
      thing() or return;
      $logger->debug(42.2);
   }

   $logger->debug(43);

If $x is false:

   debug [Cpanel-Logger] debug() number 42
   debug [Cpanel-Logger] debug() number 43

If $x is true and thing() returns true:

   debug [Cpanel-Logger] debug() number 42
   debug [Cpanel-Logger] debug() number 42.1
   debug [Cpanel-Logger] debug() number 42.2
   debug [Cpanel-Logger] debug() number 43

If $x is true and thing() returns false:

   debug [Cpanel-Logger] debug() number 42
   debug [Cpanel-Logger] debug() number 42.1

=item 2 config hashref

=over 4

=item 'force'

Force output even if $Cpanel::Debug::level says not to

=item 'backtrace'

Same as 'backtrace' to logger()

=item 'output'

Same as 'output' to logger();

=back


=back
