package Whostmgr::Remote;

# cpanel - Whostmgr/Remote.pm                      Copyright 2022 cPanel, L.L.C.
#                                                           All rights reserved.
# copyright@cpanel.net                                         http://cpanel.net
# This code is subject to the cPanel license. Unauthorized copying is prohibited

use cPstrict;

=encoding utf-8

=head1 NAME

Whostmgr::Remote

=head1 DESCRIPTION

This object encapsulates logic to send requests to a remote server via SSH.

For a mostly-compatible interface that uses WebSocket/cpsrvd rather than SSH,
see L<Whostmgr::Remote::CommandStream::Legacy>.

=cut

#----------------------------------------------------------------------

our $VERSION = '3.5';

use parent 'Whostmgr::Remote::Base';

use Whostmgr::Remote::Base ();    # to silence cplint

use Whostmgr::Remote::SSHControlCache ();
use Cpanel::PwCache                   ();
use Cpanel::AdminBin::Serializer      ();

use Cpanel::Destruct           ();
use Cpanel::Config::LoadCpConf ();
use Cpanel::Encoder::Tiny      ();
use Cpanel::SafeRun::Object    ();    # PPI USE OK -- used by SAFERUN_OBJECT_CLASS
use Cpanel::Exception          ();
use Cpanel::Rand::Get          ();
use Cpanel::SSH::Key           ();
use Cpanel::Signals            ();

use Cpanel::CPAN::IO::Callback::Write ();
use Try::Tiny;

use Whostmgr::Remote::Parser          ();    # PPI USE OK -- dynamically used
use Whostmgr::Remote::Parser::Pkgacct ();    # PPI USE OK -- dynamically used
use Whostmgr::Remote::Parser::Scp     ();    # PPI USE OK -- dynamically used

use Whostmgr::Remote::State ();

our $MAX_SSH_CONNECTION_TIME = 172800;       # 2 days

our ( $LOCAL_PKGACCT_DIR, $CUSTOM_PKGACCT_DIR );
*LOCAL_PKGACCT_DIR  = *Whostmgr::Remote::Base::LOCAL_PKGACCT_DIR;
*CUSTOM_PKGACCT_DIR = *Whostmgr::Remote::Base::CUSTOM_PKGACCT_DIR;

our ( $STATUS, $MESSAGE, $RAWOUT, $REMOTE_USERNAME, $REMOTE_ARCHIVE_IS_SPLIT, $REMOTE_FILE_PATHS, $REMOTE_FILE_MD5SUMS, $RESULT, $REMOTE_FILE_SIZES, $ESCALATION_METHOD_USED ) = ( 0, 1, 2, 3, 4, 5, 6, 7, 8, 9 );
*STATUS                  = *Whostmgr::Remote::Base::STATUS;
*MESSAGE                 = *Whostmgr::Remote::Base::MESSAGE;
*RAWOUT                  = *Whostmgr::Remote::Base::RAWOUT;
*REMOTE_USERNAME         = *Whostmgr::Remote::Base::REMOTE_USERNAME;
*REMOTE_ARCHIVE_IS_SPLIT = *Whostmgr::Remote::Base::REMOTE_ARCHIVE_IS_SPLIT;
*REMOTE_FILE_PATHS       = *Whostmgr::Remote::Base::REMOTE_FILE_PATHS;
*REMOTE_FILE_MD5SUMS     = *Whostmgr::Remote::Base::REMOTE_FILE_MD5SUMS;
*RESULT                  = *Whostmgr::Remote::Base::RESULT;
*REMOTE_FILE_SIZES       = *Whostmgr::Remote::Base::REMOTE_FILE_SIZES;
*ESCALATION_METHOD_USED  = *Whostmgr::Remote::Base::ESCALATION_METHOD_USED;

my $debug;

# Singletons
#
#  $sshcontrol_cache - Once a connection is made this will be a Whostmgr::Remote::SSHControlCache
#                      object that will keep ssh connections open to remote systems indexed by
#                      an 'args_key' which is a generated from a combination of:
#                      'authuser', 'sshkey', 'host', and 'port'.
#
#                      This permits us to avoid making multiple connections to the remote ssh
#                      server if we already have one open which allows Whostmgr::Remote objects
#                      to share the same connection to the remote system and avoid the need
#                      to tear down and build of tcp connections which drastically increases the
#                      performance of the system.
#
#
my $sshcontrol_cache;
my $locale;

our $MAX_ATTEMPTS = 3;

#for testing
our $SAFERUN_OBJECT_CLASS = 'Cpanel::SafeRun::Object';

our $SSHCONTROL = '/usr/local/cpanel/bin/sshcontrol';

#----------------------------------------------------------------------

=head1 METHODS

=cut

# Opts are:
#
#   - host - REQUIRED
#   - user (i.e., username) - REQUIRED
#   - port
#   - password
#   - scriptdir
#   - enable_custom_pkgacct
#   - root_password
#   - root_escalation_method (“su” or “sudo”)
#   - sshkey_name
#   - sshkey_passphrase
#   - timeout
#   - use_global_connection_cache
#
## encapsulates authinfo, port, and host, as they never change between invocations
sub new {
    my ( $package, $args ) = @_;

    my ( $host, $port, $user, $password, $root_password, $root_escalation_method, $sshkey_name, $sshkey_passphrase, $timeout ) = @{$args}{qw(host port user password root_password root_escalation_method sshkey_name sshkey_passphrase timeout)};

    foreach my $required_param (qw(host user)) {
        if ( !length $args->{$required_param} ) {
            die Cpanel::Exception::create( 'MissingParameter', [ name => $required_param ] );
        }
    }
    if ( $user ne 'root' ) {
        if ( !length $root_escalation_method ) {
            die Cpanel::Exception::create( 'MissingParameter', 'You must provide the “[_1]” argument to connect as an unprivileged user.', ['root_escalation_method'] );
        }
        if ( $root_escalation_method eq 'none' ) {

            # skip
        }
        elsif ( $root_escalation_method eq 'su' ) {
            if ( !length $root_password ) {
                die Cpanel::Exception::create( 'MissingParameter', 'You must provide the “[_1]” argument to escalate privileges with “[_2]”.', [ 'root_password', 'su' ] );
            }
        }
        elsif ( $root_escalation_method ne 'sudo' ) {
            die Cpanel::Exception::create( 'InvalidParameter', 'The “[_1]” argument may only have a value of [list_or_quoted,_2].', [ 'root_escalation_method', [ 'su', 'sudo', 'none' ] ] );
        }
    }
    if ( !length $sshkey_name ) {
        if ( !length $password ) {
            die Cpanel::Exception::create( 'MissingParameter', 'You must provide the [list_or_quoted,_1] argument.', [ [ 'sshkey_name', 'password' ] ] );
        }
        if ( length $sshkey_passphrase ) {
            die Cpanel::Exception::create( 'MissingParameter', 'You must provide the “[_1]” argument if you provide the “[_2]” argument.', [ 'sshkey_name', 'sshkey_passphrase' ] );
        }
    }

    if ( defined $timeout && $timeout !~ m{^[0-9]+$} ) {
        die Cpanel::Exception::create( 'InvalidParameter', 'The “[_1]” argument must be a non-zero value.', ['timeout'] );    ## no extract maketext (developer error message. no need to translate)
    }

    my $self = {
        'authinfo' => {
            'user'                   => $user,
            'root_escalation_method' => $root_escalation_method,
            'sshkey_name'            => $sshkey_name,
            'sshkey_passphrase'      => $sshkey_passphrase,
            'root_password'          => $root_password,
            'password'               => $password,
        },
        'port'                  => ( $port || 22 ),
        'host'                  => $host,
        'timeout'               => $timeout,
        'scriptdir'             => ( $args->{'scriptdir'} || undef ),
        'enable_custom_pkgacct' => $args->{'enable_custom_pkgacct'},
        #
        # By default Whostmgr::Remote disconnects the sshcontrol
        # and ssh subprocess when the object is destroyed.
        #
        # If use_global_connection_cache is passed as an argument then we leave
        # everything open and expect close_all_cached_connections()
        # will be called some time before global destruction to clean
        # everything up.
        #
        '_use_global_connection_cache' => ( $args->{'use_global_connection_cache'} || 0 )

    };

    return bless $self, $package;
}

sub new_trap_exceptions {
    my ( $package, $args ) = @_;

    my ( $obj, $err_obj );

    try {
        $obj = new( $package, $args );
    }
    catch {
        $err_obj = $_;
    };

    if ($err_obj) {
        if ( UNIVERSAL::isa( $err_obj, 'Cpanel::Exception' ) ) {
            return ( 0, $err_obj->to_locale_string_no_id() );
        }
        else {
            return ( 0, Cpanel::Exception::get_string($err_obj) );
        }
    }

    return ( 1, $obj );
}

=head2 @out = I<OBJ>->remoteexec(%OPTS)

Runs a command on the remote server and (by default)
C<print()>s that command’s STDOUT.

%OPTS are:

=over

=item * C<cmd> - A string or array reference that gives the shell command.

=item * C<returnresult> - Boolean. If set, suppresses the local
C<print()>ing of the command’s STDOUT.

=item * C<callback> - Optional, a callback that receives each
line of the remote command’s STDOUT.

=item * C<txt> - Optional, a human-readable description of the command
that’s about to run. If given, this will be C<print()>ed immediately
before executing the remote command.

=back

The return (@out) is:

=over

=item 0) A boolean that indicates success (1) or failure (0).

=item 1) A text description of the failure. (Irrelevant otherwise.)

=item 2) The “raw” output from the remote command. This will include
various things that are C<echo>ed “under-the-hood” to avoid issues with
the remote shell.

=item 3) If the C<cmd> is pkgacct, a passthrough to
L<Whostmgr::Remote::Parser::Pkgacct>’s C<remote_username()>.

=item 4) If the C<cmd> is pkgacct, a passthrough to
L<Whostmgr::Remote::Parser::Pkgacct>’s C<remote_archive_is_split()>.

=item 5) If the C<cmd> is pkgacct, a passthrough to
L<Whostmgr::Remote::Parser::Pkgacct>’s C<remote_file_paths()>.

=item 6) If the C<cmd> is pkgacct, a passthrough to
L<Whostmgr::Remote::Parser::Pkgacct>’s C<remote_file_md5sums()>.

=item 7) The remote command’s STDOUT.

=item 8) If the C<cmd> is pkgacct, a passthrough to
L<Whostmgr::Remote::Parser::Pkgacct>’s C<remote_file_sizes()>.

=item 9) A human-readable description of the root-escalation method
that succeeded on the remote.

=back

=cut

# Public interface is in Whostmgr::Remote::Base …

sub _remoteexec_command ( $self, $remote_command_to_exec, %VALS ) {    ## no critic qw(ProhibitManyArgs) -- mis-parse

    # FIXME: this is a legacy hack for now
    my $use_pkgacct_parser = ( $remote_command_to_exec =~ m{pkgacct} ? 1 : 0 );

    my ( $run_ok, $msg, $parser ) = $self->_exec_sshcontrol(
        'parser'         => ( $use_pkgacct_parser ? 'Whostmgr::Remote::Parser::Pkgacct' : 'Whostmgr::Remote::Parser' ),
        'parser_options' => {
            'output_callback' => ( $VALS{'callback'} || undef ),
            'print'           => ( $VALS{'returnresult'} ? 0 : 1 ),
        },
        'action' => ( $VALS{'txt'} || '' ),
        'args'   => {
            ctl => 'ssh',
            cmd => $remote_command_to_exec,
            $self->_sshcontrol_args(),
        },
    );

    return ( 0, $msg, $parser->raw_error() || $parser->raw() ) if !$run_ok;

    return (
        1,
        _locale()->maketext('Success'),
        $parser->raw(),
        $use_pkgacct_parser ? $parser->remote_username()         : undef,
        $use_pkgacct_parser ? $parser->remote_archive_is_split() : undef,
        $use_pkgacct_parser ? $parser->remote_file_paths()       : undef,
        $use_pkgacct_parser ? $parser->remote_file_md5sums()     : undef,
        $parser->result(),
        $use_pkgacct_parser ? $parser->remote_file_sizes() : undef,
        $parser->escalation_method_used()
    );
}

sub _remotecopy_post_validation ( $self, %VALS ) {
    my ( $run_ok, $msg, $parser ) = $self->_exec_sshcontrol(
        'parser'         => 'Whostmgr::Remote::Parser::Scp',
        'parser_options' => {
            'percent_callback' => $VALS{'callback'} || undef,
            'remote_file_size' => $VALS{'size'}     || undef,
            'print'            => 1,
        },
        'action' => ( $VALS{'txt'} || '' ),
        'args'   => {
            ctl       => 'scp',
            direction => $VALS{'direction'},
            srcfile   => $VALS{'srcfile'},
            destfile  => $VALS{'destfile'},
            $self->_sshcontrol_args(),
        },
    );

    return ( 0, $msg, $parser->raw() ) if !$run_ok;

    return (
        1,
        $msg,
        $parser->raw()
    );
}

sub _remotescriptcopy_first_destination ( $self, $destfile ) {
    return $self->{'authinfo'}{'user'} eq 'root' ? "$self->{'scriptdir'}/$destfile" : "~/${destfile}";
}

sub remotescriptcopy {
    my ( $self, %CFG ) = @_;

    my @ret = $self->SUPER::remotescriptcopy(%CFG);

    $CFG{'destfile'} ||= $self->_get_default_destfile_for_remotescriptcopy( $CFG{'srcfile'} );

    if ( $self->{'authinfo'}{'user'} ne 'root' ) {
        my $scriptdir = $self->{'scriptdir'};
        my $destfile  = $CFG{'destfile'};

        my $init_dest              = $self->_remotescriptcopy_first_destination($destfile);
        my $html_encoded_init_dest = Cpanel::Encoder::Tiny::safe_html_encode_str($init_dest);

        my $final_dest              = "$scriptdir/$CFG{'destfile'}";
        my $html_encoded_final_dest = Cpanel::Encoder::Tiny::safe_html_encode_str($final_dest);
        my $script_owner            = $self->{'authinfo'}{'user'};

        my @ret = $self->remoteexec(
            "txt" => _locale()->maketext( "Setting permissions on “[_1]” and moving into place at “[_2]” …", $html_encoded_init_dest, $html_encoded_final_dest ),
            "cmd" => "( test -e $scriptdir || mkdir -p $scriptdir ) && mv -f ~${script_owner}/$destfile $final_dest ; chmod 700 $final_dest"
        );

        if ( !$ret[$STATUS] ) {
            print _locale()->maketext( "Unable to set permission on “[_1]” with [asis,chmod].", $html_encoded_init_dest ) . "\n";
        }
    }
    return @ret;
}

sub remote_basic_credential_check {
    my ($self) = @_;

    if ( $self->{'authinfo'}->{'sshkey_name'} && $self->{'authinfo'}->{'sshkey_passphrase'} ) {
        my $homedir = Cpanel::PwCache::gethomedir();

        if ( !Cpanel::SSH::Key::validate_key_passphrase( "$homedir/.ssh/$self->{'authinfo'}->{'sshkey_name'}", $self->{'authinfo'}->{'sshkey_passphrase'} ) ) {
            my $message = _locale()->maketext( "The passphrase for the key “[_1]” is incorrect.", Cpanel::Encoder::Tiny::safe_html_encode_str( $self->{'authinfo'}->{'sshkey_name'} ) );
            return ( 0, $message, $message, $message, undef );
        }
    }

    return (
        $self->remoteexec(
            "txt"          => _locale()->maketext("Basic credential check …"),
            "returnresult" => 1,
            "cmd"          => "echo 'basic credential check'",
        )
    )[ $STATUS, $Whostmgr::Remote::Base::MESSAGE, $Whostmgr::Remote::Base::RAWOUT, $RESULT, $ESCALATION_METHOD_USED ];
}

sub _multi_exec_shell_commands ( $self, $commands ) {

    my ( $rand_part_1, $rand_part_2 ) = ( __PACKAGE__ . '::' . Cpanel::Rand::Get::getranddata(8), __PACKAGE__ . '::' . Cpanel::Rand::Get::getranddata(8) );

    my $run_command = $self->_create_multi_shell_command( $commands, $rand_part_1, $rand_part_2 );

    print STDERR "[send_cmd][$run_command]\n" if _debug();

    my @ret = $self->remoteexec(
        "txt"          => _locale()->maketext( "Fetching information from remote host: “[_1]” …", $self->{'host'} ),
        "returnresult" => 1,
        "cmd"          => $run_command
    );

    my ( $status, $result ) = @ret[ $STATUS, $RESULT ];
    if ( !$result ) {
        my $command_string = join( ';', map { $commands->{$_}{'command'} } sort { $commands->{$a}->{'id'} <=> $commands->{$b}->{'id'} } keys %{$commands} ) // '';
        my $host           = $self->{'host'} || '';
        my $message        = $ret[$Whostmgr::Remote::Base::MESSAGE] || $ret[$Whostmgr::Remote::Base::RAWOUT] || '';
        return ( 0, _locale()->maketext( "Failed to execute “[_1]” on remote host “[_2]” because of an error: [_3]", $command_string, $host, $message ) );
    }

    $self->_extract_results_from_execution( $commands, \$result, $rand_part_1, $rand_part_2 );

    foreach my $cmd ( keys %{$commands} ) {
        print STDERR "[multi_exec][$cmd][$commands->{$cmd}->{'result'}]\n" if _debug();
    }

    return ( 1, { map { $_ => $commands->{$_}->{'result'} } keys %{$commands} } );
}

sub _get_ssh_timeout {
    my ($self) = @_;

    my $timeout = $self->{'timeout'};

    if ( !$timeout ) {
        my $cpconf = Cpanel::Config::LoadCpConf::loadcpconf_not_copy();
        $timeout = $cpconf->{'transfers_timeout'};
    }

    if ( !$timeout || $timeout < 1800 ) { return 1800; }

    return $timeout;
}

sub _sshcontrol_args {
    my ($self) = @_;

    my $authinfo = $self->{'authinfo'};

    my $password_key = ( $authinfo->{'user'} eq 'root' ? 'root_pass' : 'wheel_pass' );

    my %args = (
        'host'     => $self->{'host'},
        'authuser' => $authinfo->{'user'},

        ssh_private_key_password => $authinfo->{'sshkey_passphrase'},
        root_pass                => $authinfo->{'root_password'},
        $password_key            => $authinfo->{'password'},

        'port'                   => $self->{'port'},
        'root_escalation_method' => $authinfo->{'root_escalation_method'},
        'sshkey'                 => $authinfo->{'sshkey_name'},
    );

    #Shouldn't matter, but just for "cleanliness":
    delete $args{$_} for grep { !defined $args{$_} } keys %args;

    return %args;
}

sub _exec_sshcontrol {    ## no critic qw(Subroutines::ProhibitExcessComplexity)
    my ( $self, %OPTS ) = @_;

    local $|                                         = 1;
    local $Whostmgr::Remote::State::last_active_host = $self->{'host'};

    $self->_connection_cache( $OPTS{'args'} );

    my $homedir   = Cpanel::PwCache::gethomedir();
    my $socketdir = "$homedir/.libnet-openssh-perl";
    chmod( 0700, $socketdir ) if -d $socketdir;

    if ( -e "/var/cpanel/xferdebug" ) {
        print "Whostmgr::Remote::_exec_sshcontrol: [" . join( " ", $SSHCONTROL, %{ $OPTS{'args'} } ) . "]" . ( $Whostmgr::Remote::State::HTML ? "<br />\n" : "\n" );
    }

    my $run_failed = 1;
    my ( $stderr, $run, $parser, $saferun_error );
    my $ssh_timeout = $self->_get_ssh_timeout();
    print "$OPTS{'action'} …\n" if $OPTS{'action'};
    {
        local $SIG{'__DIE__'} = 'DEFAULT';
        my $ssh_attempt = 0;
        while ($run_failed) {
            if ( ++$ssh_attempt > $MAX_ATTEMPTS ) {
                last;
            }
            elsif ( $ssh_attempt > 1 ) {
                print "Retrying …";
            }

            $stderr = '';
            $parser = "$OPTS{'parser'}"->new( 'timeout' => $ssh_timeout, %{ $OPTS{'parser_options'} } );

            try {
                $run = $SAFERUN_OBJECT_CLASS->new(
                    program => $SSHCONTROL,
                    stdin   => Cpanel::AdminBin::Serializer::Dump( $OPTS{'args'} ),
                    stdout  => Cpanel::CPAN::IO::Callback::Write->new(
                        sub {
                            # Avoid Cpanel::Signals::signal_needs_to_be_handled  and use
                            # Cpanel::Signals::has_signal as it does not clear the state.
                            #
                            # Since we are not handling the signal here we only
                            # need to break out of the loop as the signal will
                            # ultimately be handled in the transfer system at
                            # a higher level.
                            if ( Cpanel::Signals::has_signal('TERM') ) {
                                die Cpanel::Exception::create( 'RemoteAbort', 'Aborted.' );
                            }
                            elsif ( Cpanel::Signals::has_signal('USR1') ) {

                                #TODO: call Whostmgr::Transfers::State::should_skip(); which should have been
                                #told about what item we are transfering in the form of
                                # item-TRANSFER_AccountRemoteRoot_customer1  so it can
                                # look for a skip-TRANSFER_AccountRemoteRoot_customer1 that will be created
                                # by the process that is sending USR1 so we ensure that by the time USR1
                                # is sent, we have not started working on a different account and we skip
                                # the wrong one.  There needs to be a notice to the person calling the skip
                                # as well that it will attempt to skip but it can only do so while the transfer
                                # is in progress and if it finishes before the skip happens it will continue on.
                                die Cpanel::Exception::create( 'RemoteSkip', 'Skipped.' );
                            }
                            else {
                                return $parser->process_data(@_);
                            }
                        }
                    ),
                    stderr => Cpanel::CPAN::IO::Callback::Write->new(
                        sub {
                            $stderr .= $_[0];
                            return $parser->process_error_data(@_);
                        }
                    ),
                    read_timeout => $ssh_timeout,
                    timeout      => $MAX_SSH_CONNECTION_TIME,
                );
            }
            catch {
                $saferun_error = $_;
            };

            $parser->finish();

            if ($saferun_error) {
                if ( eval { $saferun_error->isa('Cpanel::Exception::RemoteSkip') || $saferun_error->isa('Cpanel::Exception::RemoteAbort') } ) {
                    last;    #Next please
                }
                elsif ( eval { $saferun_error->isa('Cpanel::Exception::RemoteSSHAccessDenied') || $saferun_error->isa('Cpanel::Exception::RemoteSSHRootEscalationFailed') || $saferun_error->isa('Cpanel::Exception::RemoteSSHMissing') || $saferun_error->isa('Cpanel::Exception::RemoteSCPMissing') } ) {
                    print $Whostmgr::Remote::State::ERROR_PREFIX . _locale()->maketext( "[asis,sshcontrol] execution encountered a fatal error: [_1]", $saferun_error->to_locale_string() );
                    last;    #Fatal error, retry is not going to help this
                }
                elsif ( eval { $saferun_error->isa('Cpanel::Exception') } ) {
                    print $Whostmgr::Remote::State::ERROR_PREFIX . $saferun_error->to_locale_string_no_id();
                }
                else {
                    print $Whostmgr::Remote::State::ERROR_PREFIX . Cpanel::Exception::get_string_no_id($saferun_error);
                }
            }
            elsif ( $run->timed_out() ) {
                $self->_destroy_connection_cache();
                $self->_connection_cache( $OPTS{'args'} );
                if ( $run->timed_out() == $ssh_timeout ) {
                    print $Whostmgr::Remote::State::ERROR_PREFIX . _locale()->maketext( "[output,asis,sshcontrol] failed because it went [quant,_1,second,seconds] without reading any data.", $ssh_timeout ) . "\n";
                }
                else {
                    print $Whostmgr::Remote::State::ERROR_PREFIX . _locale()->maketext( "[output,asis,sshcontrol] failed because it took longer than [quant,_1,second,seconds].", $MAX_SSH_CONNECTION_TIME ) . "\n";
                }
            }
            elsif ( $run->CHILD_ERROR() ? 1 : 0 ) {
                print $Whostmgr::Remote::State::ERROR_PREFIX . _locale()->maketext( "[asis,sshcontrol] execution failed with error: [_1]", $stderr );
            }
            else {
                $run_failed = 0;
            }
        }
    }
    print "Done\n" if $OPTS{'action'};

    if ($saferun_error) {
        my $error;
        if ( eval { $saferun_error->isa('Cpanel::Exception') } ) {
            $error = $saferun_error->to_locale_string_no_id();
        }
        else {
            $error = Cpanel::Exception::get_string_no_id($saferun_error);
        }
        if ( !eval { $saferun_error->isa('Cpanel::Exception::RemoteSkip') || $saferun_error->isa('Cpanel::Exception::RemoteAbort') } ) {
            $self->_display_trace_output( $error, $parser->raw() );
        }
        $self->_destroy_connection_cache();
        return ( 0, $error, $parser );

    }
    elsif ( $parser->error() ) {
        $self->_display_trace_output( $parser->error(), $parser->raw() );
        $self->_destroy_connection_cache();
        return ( 0, $parser->error(), $parser );
    }
    elsif ( $run->timed_out() ) {
        my $error;
        if ( $run->timed_out() == $ssh_timeout ) {
            $error = _locale()->maketext( "[output,asis,sshcontrol] failed because it went [quant,_1,second,seconds] without reading any data.", $ssh_timeout ) . " $stderr " . $parser->raw();
        }
        else {
            $error = _locale()->maketext( "[output,asis,sshcontrol] failed because it took longer than [quant,_1,second,seconds].", $MAX_SSH_CONNECTION_TIME ) . " $stderr " . $parser->raw();
        }
        $self->_display_trace_output( $error, $parser->raw() );
        $self->_destroy_connection_cache();
        return ( 0, $error, $parser );
    }
    elsif ($run_failed) {
        my $error = _locale()->maketext( "[output,asis,sshcontrol] execution failed with a “[_1]” signal and an “[_2]” error: [_3]", $run->signal_name(), $run->error_name(), $stderr );
        $error .= "\n\t" . _locale()->maketext( 'Raw: [_1]', $parser->raw() );
        $self->_display_trace_output( $error, $parser->raw() );
        $self->_destroy_connection_cache();
        return ( 0, $error, $parser );
    }

    if ( $parser->ctl_pid() && $parser->ctl_path() ) {
        $self->_save_connection( $parser->ctl_path(), $parser->ctl_pid() );
    }

    return ( 1, _locale()->maketext('Success'), $parser );
}

sub _display_trace_output {
    my ( $self, $reason, $txt ) = @_;

    $txt =~ s/^\s*==sshcontrol.*//mg;
    $txt =~ s/\n+/\n/sg;

    if ( !$Whostmgr::Remote::State::HTML ) {
        return print "[$reason]\n$txt\n";
    }
    else {
        return print qq{
    <br />
    <blockquote>
        <div style="color: #f22;">$reason</div><br />
        <strong>Trace Output</strong><br />
    <textarea cols="80" rows="10" style="border: 1px #ccc inset; background-color: #000; color: #fff; font-weight: 700; font-family: Courier,fixed; font-size: 12px;">} . Cpanel::Encoder::Tiny::safe_html_encode_str($txt) . qq{</textarea></blockquote>
    <br />
};
    }
}

sub _create_multi_shell_command {
    my ( $self, $commands, $rand_part_1, $rand_part_2 ) = @_;

    return join(
        ';',
        map {
            my @pieces = (
                qq[echo -n "==ssh_multi_exec=begin=$commands->{$_}->{'id'}="],
                qq[echo -n "$rand_part_1"],
                qq[echo -n "$rand_part_2=="],
                qq[LC_ALL=$commands->{$_}->{'locale'} $commands->{$_}->{'command'}],
                qq[echo -n "==ssh_multi_exec=end=$commands->{$_}->{'id'}="],
                qq[echo -n "$rand_part_1"],
                qq[echo -n "$rand_part_2=="],
            );

            '(' . join( ';', @pieces ) . ')';
        } sort { $commands->{$a}->{'id'} <=> $commands->{$b}->{'id'} } keys %{$commands}
    );
}

sub _extract_results_from_execution {
    my ( $self, $commands, $resultref, $rand_part_1, $rand_part_2 ) = @_;

    print STDERR "[resultref][$$resultref]\n" if _debug();

    foreach my $cmdkey ( keys %{$commands} ) {
        my $begin = quotemeta("==ssh_multi_exec=begin=$commands->{$cmdkey}{'id'}=${rand_part_1}${rand_part_2}==");
        my $end   = quotemeta("==ssh_multi_exec=end=$commands->{$cmdkey}{'id'}=${rand_part_1}${rand_part_2}==");
        print STDERR "begin[$begin]\n" if _debug();
        print STDERR "end[$end]\n"     if _debug();
        $$resultref =~ m{$begin(.*?)$end}s;
        print STDERR "1[" . ( $1 || '' ) . "]\n" if _debug();
        $commands->{$cmdkey}->{'result'} = $1;
    }
    return 1;
}

sub _connection_cache {
    my ( $self, $cmd_ref ) = @_;

    $sshcontrol_cache ||= Whostmgr::Remote::SSHControlCache->new();

    return ( $self->{'connection_cache_args_key'} = $sshcontrol_cache->augment_sshcontrol_command($cmd_ref) );
}

sub _save_connection {
    my ( $self, $ctl_path, $ctl_pid ) = @_;

    return if !$self->{'connection_cache_args_key'};

    return $sshcontrol_cache->register_sshcontrol_master( $self->{'connection_cache_args_key'}, $ctl_path, $ctl_pid );
}

sub _destroy_connection_cache {
    my ($self) = @_;

    if ( $sshcontrol_cache && $self->{'connection_cache_args_key'} ) {

        # Tell the sshcontrol_cache singleton to disconnect the connection
        # we are currently using.  This leaves all other connections in place
        # that the object is currently managing.
        $sshcontrol_cache->destroy_connection_by_args_key( $self->{'connection_cache_args_key'} );
    }

    return;
}

sub _locale {
    require Cpanel::Locale;
    return $locale ||= Cpanel::Locale->get_handle();
}

sub _debug {
    return $debug if defined $debug;
    $debug = -e '/var/cpanel/whostmgr_remote_debug' ? 1 : 0;
    return $debug;

}

# We are still stuck with a destroy method (with Cpanel::Destruct guarding)
# in this module because we can't remove
# the one from Whostmgr::Remote::SSHControlCache without
# some serious refactoring.
sub DESTROY {
    my ($self) = @_;

    return if $self->{'_use_global_connection_cache'};

    return if Cpanel::Destruct::in_dangerous_global_destruction();

    $self->_destroy_connection_cache();

    return;
}

# Not an object method as it affects the global
sub close_all_cached_connections {
    undef $sshcontrol_cache;

    return;
}

1;
