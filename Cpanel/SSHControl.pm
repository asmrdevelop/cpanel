package Cpanel::SSHControl;

# cpanel - Cpanel/SSHControl.pm                    Copyright 2022 cPanel, L.L.C.
#                                                           All rights reserved.
# copyright@cpanel.net                                         http://cpanel.net
# This code is subject to the cPanel license. Unauthorized copying is prohibited

#----------------------------------------------------------------------
#NOTE: This code prints() to the default output. Be sure to capture STDOUT
#or to select() a different filehandle if you need it not to do that.
#----------------------------------------------------------------------

use strict;
## no critic(RequireUseWarnings) -- requires auditing and additional tests

use Try::Tiny;

use Scalar::Util ();    #We need Scalar::Util::dualvar for Net::OpenSSH.
use Net::OpenSSH ();
use Carp         ();
use POSIX        ();    # Expect requires this

use Cpanel::OS               ();
use Cpanel::LoadFile         ();
use Cpanel::TempFile         ();
use Cpanel::Exception        ();
use Cpanel::Exception::Utils ();
use Cpanel::Expect::Shell    ();
use Cpanel::Kill::Single     ();
use Cpanel::Waitpid          ();
use Cpanel::Rand::Get        ();
use Cpanel::SSH::Key         ();

our $SSH_TIMEOUT = 28;
our $ESC_TIMEOUT = 20;

my $CTRL_C = chr 3;
my $CTRL_Z = chr 26;

our $SHELL   = '(/bin/bash || /usr/local/bin/bash || /bin/sh)';    # case 105585: Prefer /bin/bash, /usr/local/bin/bash first as /bin/sh may be dash
our $VERSION = '2.6';

#Parameters:
#   debug (boolean)
#   verbose (boolean)
#   auth_info (hashref of key/value pairs to pass to scripts/sshcontrol)
sub new {
    my ( $class, %OPTS ) = @_;

    my $self = {
        'debug'         => $OPTS{'debug'},
        'verbose'       => $OPTS{'verbose'},
        'normalized'    => 0,
        'exp'           => undef,
        'connected'     => 0,
        '__creator_pid' => $$,

        #Copy this hashref so that we can manipulate it without affecting
        #the caller's data.
        'auth_info' => { %{ $OPTS{'auth_info'} } },
    };

    bless $self, $class;

    return $self;
}

#Parameters are same as new() except:
#   ssh (instance of Net::OpenSSH)
sub new_from_external {
    my ( $class, %OPTS ) = @_;

    my $self = new( $class, %OPTS );

    $self->{'ssh'}       = $OPTS{'ssh'};
    $self->{'connected'} = 1;

    return $self;
}

sub connect {
    my ($self) = @_;

    my $auth_info = $self->{'auth_info'};

    my $sudoers      = Cpanel::OS::sudoers();
    my $login_method = $auth_info->{'ssh_username'} eq 'root' ? 'root' : $sudoers;

    my $rootpass = $auth_info->{'root_pass'};
    my $ssh_key  = $auth_info->{'ssh_private_key'};
    my $keypass  = $auth_info->{'ssh_private_key_password'} || $auth_info->{ $login_method . '_pass' };

    my @password_methods;
    my @key_methods;
    if ( length $ssh_key && -r $ssh_key ) {
        @key_methods = (
            {
                'passphrase' => $keypass,
                'key_path'   => $ssh_key
            }
        );
    }

    if ( $login_method eq $sudoers ) {
        my $wheelpass = $auth_info->{'wheel_pass'};

        if ( defined $wheelpass ) {
            push @password_methods, { 'password' => $wheelpass };
        }
        if ( defined $rootpass ) {
            push @password_methods, { 'password' => $rootpass };
        }
    }
    else {
        if ( length $rootpass ) {
            push @password_methods, { 'password' => $rootpass };
        }
    }

    $auth_info->{'password_methods'} = \@password_methods;
    $auth_info->{'key_methods'}      = \@key_methods;

    return $self->_ssh_connection();
}

sub disconnect {
    my ($self) = @_;

    if ( $self->{'pid'} ) {
        Cpanel::Kill::Single::safekill_single_pid( $self->{'pid'}, 1 );
        delete $self->{'pid'};
    }

    return 1;
}

sub disconnect_master {
    my ($self) = @_;

    return 1 if !$self->{'connected'};

    if ( my $master_pid = $self->{'ssh'}->get_master_pid() ) {
        $self->{'connected'} = 0;

        $self->cleanup();

        kill 'KILL', $master_pid;
    }

    return 1;
}

sub cleanup {
    my ($self) = @_;
    if ( my $control_path = $self->{'ssh'}->get_ctl_path() ) {
        unlink($control_path);
    }
    return 1;
}

sub soft_disconnect {
    my ($self) = @_;
    $self->{'exp'}->do('');
    $self->{'exp'}->do("exit");
    $self->{'exp'}->soft_close();
    return $self->disconnect();
}

sub _ssh_connection {
    my ($self) = @_;

    local $| = 1;

    my $auth_info    = $self->{'auth_info'} || die "Failed to load auth_info";
    my $port         = $auth_info->{'ssh_port'};
    my $host         = $auth_info->{'ssh_ip'};
    my $ssh_username = $auth_info->{'ssh_username'};

    my @password_methods = @{ $auth_info->{'password_methods'} };
    my @key_methods      = @{ $auth_info->{'key_methods'} };
    my @connect_methods;

    if ( $auth_info->{'key_or_pass'} ) {
        @connect_methods = ( @key_methods, @password_methods );
    }
    else {
        @connect_methods = ( @password_methods, @key_methods );
    }

    my $temp_obj = Cpanel::TempFile->new();
    my ( $temp_file, $temp_fh );

    foreach my $connect_method (@connect_methods) {
        my $method_name = join( " ", keys %{$connect_method} );

        print "Connecting to $host:$port as $ssh_username...using method $method_name...";

        ( $temp_file, $temp_fh ) = $temp_obj->file();

        local $ENV{'TERM'} = 'dumb';

        $self->{'ssh'} = Net::OpenSSH->new(
            'master_opts' => [
                Cpanel::SSH::Key::host_key_checking_legacy(),
                '-o' => "UserKnownHostsFile=/dev/null",
                '-o' => 'ControlPersist=no',
                ( $self->{'verbose'} ? ( ('-v') x $self->{'verbose'} ) : () ),
                ( $self->{'quiet'}   ? '-q'                            : () ),
            ],

            %{$connect_method},
            'host'                => $host,
            'port'                => $port,
            'user'                => $ssh_username,
            'timeout'             => $SSH_TIMEOUT,
            'kill_ssh_on_timeout' => 1,

            #NB: Net::OpenSSH requires a real OS filehandle,
            #so a scalar-reference filehandle will not work.
            'master_stderr_fh' => $temp_fh,
        );

        if ( $self->{'ssh'}->error() ) {
            next;    # This one failed, lets try the next connection string
        }

        last;        # Success
    }

    $self->{'connected'} = 0;

    if ( !$self->{'ssh'} ) {
        undef $self->{'ssh'};    # force stderr to be finished
        $self->_set_stderr_from_file($temp_file);
        die Cpanel::Exception::create_raw( 'ConnectionFailed', $self->{'stderr'} || "Failed to create ssh object" );
    }
    elsif ( $self->{'ssh'}->error() ) {
        $self->_set_stderr_from_file($temp_file);
        my $safe_error = $self->{'ssh'}->error();
        undef $self->{'ssh'};    # force stderr to be finished
        if ( length $self->{'stderr'} ) {
            $safe_error .= ": $self->{'stderr'}";
        }
        $safe_error =~ s{\r\n}{ \n};
        die Cpanel::Exception::create_raw( 'ConnectionFailed', $safe_error );
    }

    print "Connection Success\n";

    $self->{'connected'} = 1;

    return 1;
}

sub _set_stderr_from_file {
    my ( $self, $temp_file ) = @_;
    $self->{'stderr'} ||= '';

    if ($temp_file) {
        $self->{'stderr'} .= Cpanel::LoadFile::load($temp_file);
    }
    if ( length $self->{'stderr'} ) {
        $self->{'stderr'} =~ s{\r\n}{\n};
        $self->{'stderr'} =~ s{Warning: Permanently added \S+ \S+ to the list of known hosts.\n?}{}g;
        $self->{'stderr'} =~ s{\n+$}{};
    }
    return 1;
}

sub _get_root_shell {
    my ($self) = @_;

    my $exp_obj = $self->{'exp'};

    if ( has_xfer_debug() ) {
        $exp_obj->exp_internal(1);
        $exp_obj->debug(3);
        $exp_obj->log_stdout(1);
    }

    my $auth_info = $self->{'auth_info'} || die "Failed to load auth_info";

    if ( $auth_info->{'ssh_username'} eq 'root' ) {
        Carp::confess('Already have a root shell');
    }

    my ( $escalation_method, $err );
    try {
        $escalation_method = $self->_escalate_privs();
    }
    catch {
        $err = $_;
    };

    if ( !$escalation_method ) {
        $err = "Failed to escalate to root using “sudo” and “su”: " . Cpanel::Exception::Utils::traceback_to_error( Cpanel::Exception::get_string( $err || '(reason unknown)' ) );
        $self->soft_disconnect();
    }

    return ( 0, $err ) if $err;

    return ( 1, $escalation_method );
}

#%OPTS can be:
#   - destfile
#     NOTE: If given as ".", takes the last node of the 'srcfile' path
#   - direction: either "download" or "upload"
#   - srcfile
sub scp {
    my ( $self, %OPTS ) = @_;

    delete $self->{'pid'};

    if ( $OPTS{'destfile'} eq '.' ) {
        $OPTS{'destfile'} = ( split( m{/+}, $OPTS{'srcfile'} ) )[-1] || '.';
    }

    $OPTS{'destfile'} =~ s{^~}{\.\/};
    $OPTS{'srcfile'}  =~ s{^~}{\.\/};

    my $temp_obj = Cpanel::TempFile->new();
    my ( $file, $write_fh ) = $temp_obj->file();

    my $which_file_is_local;

    if ( $OPTS{direction} eq "download" ) {
        $self->{'pid'} = $self->{'ssh'}->scp_get( { 'stderr_fh' => $write_fh, 'async' => 1, 'quiet' => 1, 'verbose' => 0 }, $OPTS{'srcfile'}, $OPTS{'destfile'} );
        $which_file_is_local = 'destfile';
    }
    elsif ( $OPTS{'direction'} eq 'upload' ) {
        $self->{'pid'} = $self->{'ssh'}->scp_put( { 'stderr_fh' => $write_fh, 'async' => 1, 'quiet' => 1, 'verbose' => 0 }, $OPTS{'srcfile'}, $OPTS{'destfile'} );
        $which_file_is_local = 'srcfile';
    }
    else {
        die "Invalid “direction”: [$OPTS{'direction'}]";
    }

    if ( !$self->{'pid'} ) {
        return ( 0, $self->{'ssh'}->{'error'} || 'Failed to create scp session pid' );
    }

    print "==sshcontrolsize=0==\n";
    {
        local $SIG{'ALRM'} = sub {
            print "==sshcontrolsize=" . ( stat( $OPTS{$which_file_is_local} ) )[7] . "==\n";
            alarm(1);
        };
        alarm(1);
        Cpanel::Waitpid::sigsafe_blocking_waitpid( $self->{'pid'} );
        $self->{'pid'} = undef;
        alarm(0);
    }
    print "==sshcontrolsize=" . ( stat( $OPTS{$which_file_is_local} ) )[7] . "==\n";

    $self->disconnect();

    my $err;
    if ( ( $err = Cpanel::LoadFile::loadfile($file) )
        && $err =~ m{^(scp:\s+.*|lost connection)}m ) {
        return ( 0, $1 );
    }
    return ( 1, 'OK' );
}

sub exec_as_root {
    my ( $self, $cmd ) = @_;
    my $auth_info = $self->{'auth_info'};

    if ( !$self->{'connected'} ) {
        Carp::confess("SSH must first be connected.  Please call ->connect();");
    }

    if ( !$self->_open_connection_and_start_expect() ) {
        my $failure_msg = "Failed to open a new connection and start expect.";
        warn $failure_msg;
        return ( 0, $failure_msg );
    }
    if ( $auth_info->{'ssh_username'} ne 'root' && $auth_info->{'root_escalation_method'} ne 'none' ) {
        my ( $root_ok, $escalation_method ) = $self->_get_root_shell();
        if ( !$root_ok ) {
            $self->soft_disconnect();
            return ( $root_ok, $escalation_method ) if !$root_ok;
        }
        print "==sshcontrolescalation_method=$escalation_method==\n";
    }

    if ( has_xfer_debug() ) {
        my $exp_obj = $self->{'exp'};
        $exp_obj->exp_internal(1);
        $exp_obj->debug(3);
        $exp_obj->log_stdout(1);
    }

    print "Normalizing root shell....\n";

    my ($err);
    try {
        $self->{'exp'}->normalize_shell();
    }
    catch {
        $err = "Failed to normalize shell: " . Cpanel::Exception::Utils::traceback_to_error( Cpanel::Exception::get_string( $_ || '(reason unknown)' ) );
        $self->soft_disconnect();
    };

    return ( 0, $err ) if $err;

    $self->{'normalized'} = 1;

    print "Done normalizing shell.\n";

    return $self->_exec_command_with_sh($cmd);
}

sub _exec_command_with_sh {
    my ( $self, $cmd ) = @_;

    my $exp_obj = $self->{'exp'};

    my $randkey = __PACKAGE__ . '::' . Cpanel::Rand::Get::getranddata(16);

    if ( has_xfer_debug() ) {
        $exp_obj->exp_internal(1);
        $exp_obj->debug(3);
    }

    #This must stay on, or else tests fail.
    $exp_obj->log_stdout(1);

    my $exec = "echo -n ==sshcontrol && echo output==$randkey== && $cmd ; echo -n ==sshcontrol && echo output==$randkey==";
    my $err;
    try {
        $exp_obj->cmd_then_poll( $exec, 15000 );
    }
    catch {
        $err = $_;
    };

    $self->soft_disconnect();

    return ( 0, Cpanel::Exception::get_string($err) ) if $err;

    return ( 1, 'OK' );
}

sub _open_connection_and_start_expect {
    my ($self) = @_;

    local $| = 1;
    local $ENV{'TERM'} = 'dumb';

    # If we are not connecting as root, we are going to need to use
    # sudo or su which both require tty. When a tty is added into the mix,
    # this system is not are reliable because we inherit any terminal
    # setting or config on the remote machine that we do not control
    my $method = $self->{'auth_info'}->{'ssh_username'} eq 'root' ? 'open2socket' : 'open2pty';

    ( $self->{'connection'}, $self->{'pid'} ) = $self->{'ssh'}->$method($SHELL);

    if ( !$self->{'connection'} ) {
        warn "SSH failed to open the connection: $!\n";
    }

    return 0 if !$self->{'connection'} || !$self->{'pid'};

    if ( POSIX::isatty( $self->{'connection'} ) ) {
        $self->{'connection'}->set_raw();
    }

    $self->{'exp'} = Cpanel::Expect::Shell->init( $self->{'connection'} );

    if ( !$self->{'exp'} ) {
        warn "Expect failed to open the connection: $!\n";
    }
    return $self->{'exp'} ? 1 : 0;
}

sub _escalate_privs {    ## no critic(ProhibitExcessComplexity)
    my ($self) = @_;

    local $| = 1;

    my $auth_info = $self->{'auth_info'} || die "Failed to load auth_info";
    my $rootpass  = $auth_info->{'root_pass'};
    my $wheelpass = $auth_info->{'wheel_pass'};

    my $got_root = 0;

    if ( $self->{'exp'}->is_tty() ) {
        $self->{'exp'}->do('');    # Try to force a login prompt to appear
    }
    else {
        $self->{'exp'}->do('echo CPANEL_OK');    # Just send something so we can read in if the account is disabled
    }
    print "Waiting for login prompt ....";
    if (
        $self->{'exp'}->expect(
            $ESC_TIMEOUT,
            $self->{'exp'}->is_tty() ? () : [qr/CPANEL_OK/],
            [qr/\]\s?/],
            [qr/\$\s?/],
            [qr/\#\s?/],
            [qr/\%\s?/],
            [qr/\?\s?/],
            [
                qr/(?:Shell access is not enabled|This account is currently not available)/i,
                sub {
                    print "Account is disabled.\n";
                    die "Account is disabled";
                }
            ],
            [
                qr/jailshell/i,
                sub {
                    print "Account has jailshell.\n";
                    die "Account has jailshell.";
                }
            ],

        )
    ) {
        print "Done waiting for login prompt.\n";
    }
    else {
        print "Waiting for login prompt timed out, assuming the shell has an odd prompt.\n";
        $self->{'exp'}->do('');    # Try to force a login prompt to appear
    }

    print "Normalizing user level shell...\n";
    $self->{'exp'}->normalize_shell();
    print "Done normalizing shell.\n";

    my ( @su_methods, @sudo_methods );

    push @su_methods,
      (
        {
            'method'      => 2,
            'name'        => 'su w/root pass',
            'keep_trying' => 0,
            'cmd'         => qq{su -l -c "echo -n SU_ && echo CPANEL_SUCCESS && $SHELL" - && exit || ( echo -n SU_ ; echo FAIL )},
            'password'    => $rootpass
        }
      ) if length $rootpass;

    if ( length $wheelpass && ( !length $rootpass || $wheelpass ne $rootpass ) ) {
        push @su_methods,
          (
            {
                'method'      => 4,
                'name'        => 'su w/wheel pass',
                'keep_trying' => 0,
                'cmd'         => qq{su -l -c "echo -n SU_ && echo CPANEL_SUCCESS && $SHELL" - && exit || ( echo -n SU_ ; echo FAIL )},
                'password'    => $wheelpass
            },
          );
    }

    push @sudo_methods,
      (
        {
            'method'      => 3,
            'name'        => 'sudo w/wheel pass',
            'keep_trying' => 1,
            'retry_cmd'   => 1,
            'cmd'         => qq{sudo su -l -c "echo -n SUDO_ && echo CPANEL_SUCCESS && $SHELL" - && exit || ( echo -n SUDO_ ; echo FAIL )},
            'password'    => $wheelpass
        }
      );

    if ( length $rootpass && ( !length $wheelpass || $rootpass ne $wheelpass ) ) {
        push @sudo_methods,
          (
            {
                'method'      => 5,
                'name'        => 'sudo w/root pass',
                'keep_trying' => 1,
                'cmd'         => qq{sudo su -l -c "echo -n SUDO_ && echo CPANEL_SUCCESS && $SHELL" - && exit || ( echo -n SUDO_ ; echo FAIL )},
                'password'    => $rootpass
            },
          );
    }

    my @methods;
    if ( $auth_info->{'root_escalation_method'} && $auth_info->{'root_escalation_method'} eq 'su' ) {
        @methods = ( @su_methods, @sudo_methods );
    }
    else {
        @methods = ( @sudo_methods, @su_methods );
    }
  METHOD_LOOP:
    foreach my $method (@methods) {
        print "Attempting to obtain root using method \"$method->{'name'}\"\n";

        my $run_command = sub {
            $self->{'exp'}->reset_shell();
            $self->{'exp'}->do("echo CPANEL_COMMAND && $method->{'cmd'}");
            $self->{'exp'}->expect( $ESC_TIMEOUT, 'CPANEL_COMMAND' );
        };

        $run_command->();

        my $password_sent = 0;
        my $failed        = 0;
        my $retry_counter = 0;

      PASSWORD_LOOP:
        for ( 0 .. 6 ) {
            last METHOD_LOOP   if $got_root;
            last PASSWORD_LOOP if $failed;

            $self->{'exp'}->expect(
                $ESC_TIMEOUT,
                [
                    qr/(word|word\s+for\s+\S+|phrase):/i,
                    sub {
                        if ( $password_sent && !$method->{'keep_trying'} ) {
                            print "$method->{'name'}: incorrect password\n";
                            $failed = 1;
                            return;
                        }
                        $password_sent++;
                        if ( $password_sent > 1 ) {
                            print "$method->{'name'} already failed, sending empty strings until it dies....\n";
                            $self->{'exp'}->do(q{});
                        }
                        else {
                            print "Sending password for $method->{'name'}...\n";

                            # case 105289: Some versions of 'su' need \n instead of \r
                            # when stty is raw.
                            $self->{'exp'}->send( ( length $method->{'password'} ? $method->{'password'} : q{} ) . "\n" );
                        }
                    }
                ],
                [
                    qr/(SUDO|SU)_CPANEL_SUCCESS/,
                    sub {
                        print "$method->{'name'} success...\n";
                        return ( $got_root = $method->{'name'} );
                    },
                ],
                [
                    qr/\r?\nSorry,\s+try\s+again/,
                    sub {
                        if ( !$method->{'retry_cmd'} || $retry_counter ) {
                            print "Received Generic SUDO access denied (check brute force protection?).\n";
                            $failed = 2;
                        }
                        ++$retry_counter;
                        return;
                    },
                ],
                [
                    qr/\r?\nSorry/,
                    sub {
                        print "Received Generic SUDO access denied (check brute force protection?).\n";
                        $failed = 2;
                        return;
                    },
                ],
                [
                    qr/root is not in the sudoers file/,
                    sub {
                        print "$method->{'name'} success...\n";
                        return ( $got_root = $method->{'name'} );
                    },
                ],
                [
                    qr/is not in the sudoers file/,
                    sub {
                        print "Failed because the user was not in the sudoers file\n";
                        $failed = 2;
                        return;
                    },
                ],
                [
                    qr/no such file/i,
                    sub {
                        print "Failed because command did not exist\n";
                        $failed = 2;
                        return;
                    },
                ],
                [
                    qr/:\s+Permission denied/i,
                    sub {
                        print "Failed because the user did not have permission to run the command.\n";
                        $failed = 2;
                        return;
                    },
                ],
                [
                    qr/(SUDO|SU)_FAIL/,
                    sub {
                        my $fail_reason = $self->{'exp'}->before();
                        $fail_reason =~ s/^\s+//;
                        $fail_reason =~ s/\s+$//;
                        print "$method->{'name'} failed ($fail_reason)...\n";
                        $failed = 1;
                        return;
                    },
                ],
                'eof'
            );

            if ( $self->{'debug'} ) {
                my $before = $self->{'exp'}->before();
                print $before . "\n" unless $failed == 2;
            }
        }

        print "Resetting Terminal....";

        for ( 0 .. 3 ) { $self->{'exp'}->do($CTRL_C); }

        $self->{'exp'}->do($CTRL_Z);
        print "Done.\n";
    }

    print "Failed to obtain root.\n" if !$got_root;
    return $got_root;

}

sub has_xfer_debug {
    return -e '/var/cpanel/xferdebug' ? 1 : 0;
}

sub DESTROY {
    my ($self) = @_;

    if ( $self->{'__creator_pid'} == $$ && $self->{'ssh'} ) {
        $self->disconnect();
    }
    return 1;
}

1;
