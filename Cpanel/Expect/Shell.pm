package Cpanel::Expect::Shell;

# cpanel - Cpanel/Expect/Shell.pm                  Copyright 2022 cPanel, L.L.C.
#                                                           All rights reserved.
# copyright@cpanel.net                                         http://cpanel.net
# This code is subject to the cPanel license. Unauthorized copying is prohibited

#----------------------------------------------------------------------
# XXX MAINTAINER BEWARE: There be dragons here!!!
#
# This module has caused no end of test flappage. We think we've got it pretty
# "tame" now, but for future maintenance, here are some things we've learned:
#
# At several points in the logic below it is necessary to send "echo" statements
# in order to "synchronize" with the remote shell. Those echo statements:
#   - should produce predictable output (e.g., no "echo $$")
#   - should NOT contain exactly what will be output
#       ...because some shells (e.g., tcsh) ALWAYS echo the command to the TTY.
#   - "echo -n $str1; echo $str2" fails because a PROMPT_COMMAND environment
#       variable in the shell could alter what the shell actually outputs.
#
# In light of the above, the currently in-use pattern is to send parameters to
# "echo" with multiple spaces in between, then watch for the output of those
# parameters as single-spaced.
#----------------------------------------------------------------------

use cPstrict;

use Try::Tiny;

use parent qw(Cpanel::Expect);

use Cpanel::Debug                 ();
use Cpanel::Exception             ();
use Cpanel::Expect::Shell::Detect ();

#Since we don’t "own" the Expect.pm logic (i.e., it comes from CPAN,
#not from us), it's safer to add our own logic using the "inside-out" pattern.
my %instance_data;

my $TIMEOUT = 150;

my $cmd_then_poll_RETRIES = 3;

my @NEVER_NORMALIZE = qw(
  ftpsh
  jailshell
  nologin
  noshell
);

our @ALLOWED_SHELLS = qw(
  sh
  bash
);
my @TRY_SHELLS = (
    @ALLOWED_SHELLS,
    '/bin/sh',
);

my %SHELL_ENV_VARIABLES = (
    'LANG'   => 'en_US.UTF-8',
    'LC_ALL' => 'en_US.UTF-8',
    'TERM'   => 'dumb',
);

my %BASH_ENV_VARIABLES = (
    %SHELL_ENV_VARIABLES,
    'PS2'            => q<>,
    'PS3'            => q<>,
    'PS4'            => q<>,
    'PROMPT_COMMAND' => q<>,
);

sub _shell_is_allowed {
    my ( $self, $shell ) = @_;

    $shell =~ s<.*/><>;
    return scalar grep { $shell eq $_ } @ALLOWED_SHELLS;
}

#NB: C-based shells use "setenv" have a "set prompt" command.
#That's not important, though, unless we use other shells directly;
#as this module works now, we just normalize everything to bash.
sub _bourne_family_shell_normalize_commands {
    my ($self) = @_;

    my ( $str1, $str2 ) = _get_short_rand_strings();

    $instance_data{$self}{'_prompt_env'} = "$str1:$str2:cPs#";

    return (
        qq<export PS1="$instance_data{$self}{'_prompt_env'}">,
        ( map { "export $_=\"$BASH_ENV_VARIABLES{$_}\"" } keys %BASH_ENV_VARIABLES ),
    );
}

#Turns the remote shell into bash, sets up a few environment variables,
#and sets up a reasonable-standard stty.
sub normalize_shell {
    my ($self) = @_;

    local $| = 1;

    # If the remote connection is a socket we do not have to worry
    # about garbage being added
    if ( $self->is_tty() ) {
        try {
            require IO::Stty;

            if ( $INC{"IO/Stty.pm"} ) {
                $self->stty(qw(raw icrnl -echo));
                $self->slave->stty(qw(raw icrnl -echo));
            }
            else {
                Cpanel::Debug::log_warn("IO::Stty is not available. Shell interaction will not be reliable.");
            }

        };    # May fail on systems with
              # olders IO::Tty and Expect
              # but thats ok since we run stty manually
              # for now.

    }

    my $current_shell_name = $self->get_shell_name();

    #This should never actually happen in production.
    if ( grep { $_ eq $current_shell_name } @NEVER_NORMALIZE ) {
        die Cpanel::Exception->create( 'You attempted to normalize the shell “[_1]”. This should never happen! To prevent further errors, the system has aborted the shell normalization.', $current_shell_name );
    }

    if ( !$self->_shell_is_allowed($current_shell_name) ) {
        $current_shell_name = $self->_execute_usable_shell_or_die($current_shell_name);
    }
    else {
        $self->_setup_shell() or die Cpanel::Exception->create_raw( "Could not normalize shell: {" . $self->before() . "[" . $self->match() . "]" . $self->after() . "}" );
    }

    return 1;
}

sub _execute_usable_shell_or_die {
    my ( $self, $current_shell ) = @_;

    for my $try_shell (@TRY_SHELLS) {
        $self->clear_accum();
        my ( $rand1, $rand2 ) = _get_short_rand_strings();

        #NOTE: See above about "echo" statements.
        my $shell_cmd = "exec $try_shell -c 'echo ___ $rand1   $rand2 ___;$try_shell;'";
        $self->do($shell_cmd);

        #Tell the shell to echo a random string
        #until we see the anticipated string. This allows for cases when
        #there may be long-running stuff between shell prompts, or when the
        #shell takes a long time to load.
        if ( !$self->expect( $TIMEOUT, [qr{___ $rand1 $rand2 ___}s] ) ) {
            next;
        }

        if ( $self->_setup_shell() ) {
            my $new_shell = $self->get_shell_name();
            if ( $self->_shell_is_allowed($new_shell) ) {
                return $new_shell;
            }
        }
    }

    die "Invalid shell ($current_shell), and could not switch to a different one!";
}

#NOTE: csh/tcsh will ALWAYS echo the command, regardless of "stty raw -echo".
sub get_shell_name {
    my ($self) = @_;

    #Decreasing order of (seeming) reliability...
    my @methods_to_try = (
        '_get_shell_name_from_readlink',
        '_get_shell_name_from_shell_echo',
        '_get_shell_name_from_proc_cmdline',
    );

    my $name;

    for my $method (@methods_to_try) {
        try { $name = $self->$method() }
        catch {
            Cpanel::Debug::log_warn( "Failed to get remote shell via $method: " . $_->to_string() );
        };
        last if length $name;
    }

    if ( !length $name ) {
        die Cpanel::Exception->create('The system failed to detect the remote shell. This probably indicates misconfiguration on the remote host or very high system load.');
    }

    $name =~ s/\s//g;

    $self->shell_name($name);

    return $name;
}

#This works for simple, one-line, no-spaces responses only.
#Don't use it for anything fancier!
#
sub _cmd_then_poll_oneline {
    my ( $self, $cmd ) = @_;

    my ( $rand1, $rand2 ) = _get_short_rand_strings();
    my ( $rand3, $rand4 ) = _get_short_rand_strings();

    #NOTE: This method only works for "simple" commands because the "echo"
    #below will smash everything that's space-separated onto a single line
    #with only one space between.
    #
    #NOTE: See above about "echo" statements.
    #
    $self->do("echo $rand1  $rand2 `$cmd` $rand3   $rand4");

    my $payload;
    $self->expect(
        $TIMEOUT,
        [
            qr<$rand1 $rand2 .* $rand3 $rand4>s,
            sub {
                $payload = $self->match();
            },
        ],
    );

    if ( defined $payload ) {
        $payload =~ s<.*$rand1 $rand2 ><>s;
        $payload =~ s< $rand3 $rand4.*><>s;
    }

    return $payload;
}

sub _get_shell_name_from_proc_cmdline ($self) {

    return Cpanel::Expect::Shell::Detect::via_proc_cmdline(
        sub ($cmd) {
            $self->_cmd_then_poll_oneline($cmd);
        }
    );
}

sub _get_shell_name_from_readlink ($self) {

    return Cpanel::Expect::Shell::Detect::via_proc_exe(
        sub ($cmd) {
            $self->_cmd_then_poll_oneline($cmd);
        }
    );
}

sub _get_shell_name_from_shell_echo {
    my ($self) = @_;

    return $self->_cmd_then_poll_oneline('echo $0');
}

#NOTE: We've had race safety issues with this little one.
#Hopefully the below will serve us, barring the "exceptionally exceptional".
#
sub reset_shell {
    my ($self) = @_;

    # The shell never needs to be reset if the remote
    # is not a terminal
    return 1 if !$self->is_tty();
    return $self->cmd_then_poll('echo reset') eq 'reset' ? 1 : 0;
}

sub end_shell {
    my ($self) = @_;

    $self->do('');
    $self->do('exit');
    return $self->soft_close();
}

#NOTE: csh/tcsh will ALWAYS echo the command, regardless of "stty raw -echo".
sub cmd_then_poll {
    my ( $self, $cmd, $timeout ) = @_;

    #
    # Wait for the shell to return something so we know its good to send
    #

    my ( $matched_pattern_position, $error, $successfully_matching_string, $before_match, $after_match );

    for ( 1 .. $cmd_then_poll_RETRIES ) {

        $self->clear_accum();

        #NOTE: See above about "echo" statements.
        #
        my ( $echo1, $echo2 ) = _get_short_rand_strings();
        $self->do(qq{echo zz  $echo1    $echo2  zz});

        ( $matched_pattern_position, $error, $successfully_matching_string, $before_match, $after_match ) = $self->expect( int( $TIMEOUT / $cmd_then_poll_RETRIES ), [qr/zz $echo1 $echo2 zz/] );

        last if $matched_pattern_position;

        # naive retry strategy
        sleep $_ if $_ < $cmd_then_poll_RETRIES;
    }

    if ( !$matched_pattern_position ) {
        $before_match                 = '' if !defined $before_match;
        $after_match                  = '' if !defined $after_match;
        $successfully_matching_string = '' if !defined $successfully_matching_string;
        die Cpanel::Exception::create_raw( 'Timeout', "The command “$cmd” didn’t seem to finish within $TIMEOUT seconds because of an error: “$error”! Captured shell output was: {" . $self->clear_accum() . "},{" . $before_match . "[" . $successfully_matching_string . "]" . $after_match . "} [shell setup]" );
    }

    $self->clear_accum();

    $timeout ||= $TIMEOUT;

    my $call_insert;

    #If all we're echoing back is a simple string with no variables or spaces,
    #then our work is easier.
    if ( $cmd =~ m{^echo ([^\s\$])$} ) {
        $call_insert = $1;
    }
    else {
        # We can only reliably do an echo command if setup_shell
        # was successful. If the shell isn't setup it could
        # have PROMPT_COMMAND set so we can get garbage between
        # commands.  For examaple
        #
        # echo -n cow;echo pig
        #
        # Should return 'cowpig'
        #
        # However if PROMPT_COMMAND is set we might get
        # 'cowThe quote of the day is: I like to break my bashrc
        # pig'
        #
        if ( !$self->shell_is_setup() ) {
            my $current_shell_name = $self->shell_name() || 'UNKNOWN';
            die Cpanel::Exception->create_raw("The command “$cmd” cannot be executed because the shell “$current_shell_name” could not be setup.");

        }
        $call_insert = ";$cmd;echo -n ";
    }

    my ( $rand1, $rand2 ) = _get_short_rand_strings();
    my ( $rand3, $rand4 ) = _get_short_rand_strings();

    my $call = qq{echo -n $rand3} . '__' . $call_insert . '__' . $rand4 . qq{___$rand1} . '__' . $rand2 . '___';

    $self->do($call);

    ( $matched_pattern_position, $error, $successfully_matching_string, $before_match, $after_match ) = $self->expect( $timeout, [qr{___\Q$rand1\E__\Q$rand2\E___}s] );
    if ( !$matched_pattern_position ) {
        die Cpanel::Exception::create_raw( 'Timeout', "The command “$cmd” didn’t seem to finish within $timeout seconds because of an error: “$error”! Captured shell output was: {" . $self->clear_accum() . "},{" . $before_match . "[" . $successfully_matching_string . "]" . $after_match . "}" );
    }

    $self->clear_accum();

    if ( $before_match =~ m{\Q$rand3\E__(.*?)__\Q$rand4\E}s ) {
        return $1;
    }

    die Cpanel::Exception->create_raw( "Could not run cmd and poll: {" . $self->clear_accum() . "},{" . $before_match . "[" . $successfully_matching_string . "]" . $after_match . "}" );
}

sub _setup_shell {
    my ($self) = @_;

    my $has_working_shell = 0;

    if ( $self->is_tty() ) {
        for ( 1 .. 2 ) {

            $self->do('stty raw icrnl -echo');    # Do stty first to turn off line wrapping
                                                  # We need to send stty before we start reading the output of commands
                                                  # as they may wrap in random places before stty has finished executing
                                                  # and return output like the below:
                                                  #
                                                  # [0;32mâ€¢[0;0m [root@shaggy:~]# stty raw icrnl -echo;unset HISTFILE;export PS1=&quot;c_311009
                                                  # &lt;aw icrnl -echo;unset HISTFILE;export PS1=&quot;c_3110098                                   7_P:c_46041464P:cPs#&quot;;exp
                                                  #
                                                  # &lt;ILE;export PS1=&quot;c_31100987_P:c_46041464P:cPs#&quot;;expo                        rt PS4=&quot;&quot;;export PS3=&quot;&quot;;e
                                                  #
                                                  # &lt;_P:c_46041464P:cPs#&quot;;export PS4=&quot;&quot;;export PS3=&quot;&quot;;ex                        port TERM=&quot;dumb&quot;;export P

            $self->do(
                join ';',

                #Most shells automatically interpret CR as LF when needed.
                #dash/ash/sh and ksh are prominent exceptions.
                'unset HISTFILE',
                $self->_bourne_family_shell_normalize_commands(),
            );

            my @expect = $self->expect(
                $TIMEOUT,
                [
                    qr<stty:\s+command\s+not\s+found>i,
                    sub {
                        die Cpanel::Exception->create_raw('“stty” is missing!');
                    },
                ],
                [
                    $instance_data{$self}{'_prompt_env'},
                    sub {
                        $has_working_shell = 1;
                    },
                ]
            );

            # avoid a race condition, sometimes we need to retry the do/expect sequence
            last if $has_working_shell;

            $self->reset_shell();
        }
    }
    else {
        # If the remote is a socket we do not have to worry
        # about the remote terminal adding garbage
        $self->do('unset HISTFILE');
        $has_working_shell = 1;
    }

    $self->shell_is_setup($has_working_shell);

    return $has_working_shell;
}

# NOTE: These strings need to be short so we do not exceed 80 characters
# which can cause the line to wrap and produce random failures before
# stty has set us to raw mode.
sub _get_short_rand_strings {
    return ( 'c_' . _rand_int(8) . '_P', 'c_' . _rand_int(8) . 'P' );
}

sub _rand_int {
    my ($length) = @_;
    my $str = '';
    while ( length $str < $length ) {
        $str = substr( int rand( "9" x $length ), 0, $length );
    }
    return $str;
}

sub DESTROY {
    my ($self) = @_;

    delete $instance_data{$self};

    return $self->SUPER::DESTROY();
}

1;
