package Cpanel::Transport::Files::Rsync;

# cpanel - Cpanel/Transport/Files/Rsync.pm         Copyright 2022 cPanel, L.L.C.
#                                                           All rights reserved.
# copyright@cpanel.net                                         http://cpanel.net
# This code is subject to the cPanel license. Unauthorized copying is prohibited

use strict;
use warnings;
use Cpanel::Locale              ();
use Cpanel::SSH::Key            ();
use Cpanel::Transport::Response ();
use Cpanel::Transport::Files    ();
use Net::OpenSSH                ();
use File::Temp                  ();
use File::Basename              ();
use Capture::Tiny               ();

our @ISA = ('Cpanel::Transport::Files');
my $locale;

=head1 NAME

Cpanel::Transport::Files::Rsync

=cut

# The existing SIGCHLD handlers coming from Cpanel::Daemonize (maybe others?)
# reaps the children spawned by Net::OpenSSH and results in errors when it attempts to wait on them
# Restoring the original even on DESTROY appears to restore it too soon, keeping it here for now
# regardless
my $orig_sig_child_handler = $SIG{'CHLD'};
$SIG{'CHLD'} = 'DEFAULT';    ## no critic(Variables::RequireLocalizedPunctuationVars)

# For debugging during bin/cpbackup/transporter
# $Net::OpenSSH::debug = -1;

# OPTS should contain session specific information (credentials, usernames, passwords, keys, etc), $CFG should be
# global configuration information.
#
# Required for instantiation:
# $OPTS contains:
#   'host', 'username' then either 'key' or 'password'.

=head1 SUBROUTINES

=head2 new( $opts_hr, $cfg,hr )

Returns a new Cpanel::Transport::Files::Rsync object, given the transport configuration

=cut

sub new {
    my ( $class, $OPTS, $CFG ) = @_;
    $locale ||= Cpanel::Locale->get_handle();

    $CFG ||= {};
    $OPTS->{'rsync_obj'} = _check_host( $OPTS, $CFG );
    my $self = bless $OPTS, $class;

    # Create rsync related default opts
    my %rsync_opts;
    $rsync_opts{'archive'}  = 1;
    $rsync_opts{'compress'} = 1;
    $rsync_opts{'timeout'}  = $OPTS->{timeout} || 30;

    # Save opts for future calls
    $self->{'rsync_opts'} = \%rsync_opts;
    return $self;
}

=head2 _missing_parameters( $param_hr )

Checks to see if vital parameters are included or not.
Creates default values for non-vital parameters.

=cut

sub _missing_parameters {
    my ($param_hashref) = @_;

    # attempt to automatically detect the auth type.
    if ( !defined $param_hashref->{'authtype'} ) {
        if ( exists $param_hashref->{'privatekey'} ) {
            $param_hashref->{'authtype'} = 'key';
        }
        elsif ( exists $param_hashref->{'password'} ) {
            $param_hashref->{'authtype'} = 'password';
        }
    }

    my @result = ();
    foreach my $key (qw/host username authtype/) {
        if ( !defined $param_hashref->{$key} ) {
            push @result, $key;
        }
    }

    my %defaults = (
        'path'            => '',
        'timeout'         => '30',    # --timeout=30
        'port'            => '22',
        'can_incremental' => 1
    );
    foreach my $key ( keys %defaults ) {
        if ( !defined $param_hashref->{$key} ) {
            $param_hashref->{$key} = $defaults{$key};
        }
    }

    # Some additional logic based on the authtype
    my $authtype = $param_hashref->{'authtype'} || 'none';
    if ( $authtype eq 'key' ) {
        if ( !defined $param_hashref->{'privatekey'} ) {
            push @result, 'privatekey';
        }
    }
    elsif ( $authtype eq 'password' ) {
        if ( !defined $param_hashref->{'password'} ) {
            push @result, 'password';
        }
    }

    return @result;
}

=head2 _get_valid_parameters()

Returns list of configuration parameters this module knows how to handle

=cut

sub _get_valid_parameters {
    return qw/host username authtype path timeout port privatekey passphrase password/;
}

=head2 _validate_parameters( $param_hr )

Takes a hash referense of configuration parameters and ensures the conform to
certain limits or criteria

=cut

sub _validate_parameters {
    my ($param_hashref) = @_;
    my @result = ();

    foreach my $key (qw/host username/) {
        if ( !defined $param_hashref->{$key} || $param_hashref->{$key} eq '' ) {
            push @result, $key;
        }
    }

    my $authtype = $param_hashref->{'authtype'};
    if ( $authtype eq 'key' ) {
        if ( !defined $param_hashref->{'privatekey'} ) {
            push @result, 'privatekey';
        }
        else {

            # Make sure the privatekey is an actual file
            my $file = $param_hashref->{'privatekey'};
            unless ( -s $file and -f $file ) {
                push @result, 'privatekey';
            }
        }
        delete $param_hashref->{'password'};
    }
    elsif ( $authtype eq 'password' ) {
        if ( !defined $param_hashref->{'password'} ) {
            push @result, 'password';
        }
        delete $param_hashref->{'privatekey'};
        delete $param_hashref->{'passphrase'};
    }
    else {
        push @result, 'authtype';
    }

    push @result, 'port'    unless Cpanel::Transport::Files::value_is_in_range( value => $param_hashref->{'port'},    min => 1,  max => 65535 );
    push @result, 'timeout' unless Cpanel::Transport::Files::value_is_in_range( value => $param_hashref->{'timeout'}, min => 30, max => 300 );

    return @result;
}

=head2 _translate_parameters( $opts_hr, $cfg_hr )

Translate our parameters into ones which will be used by
the Rsync library and store them in the config element

=cut

sub _translate_parameters {
    my ( $OPTS, $CFG ) = @_;

    $CFG->{'host'}    = $OPTS->{'host'};
    $CFG->{'user'}    = $OPTS->{'username'};
    $CFG->{'port'}    = $OPTS->{'port'};
    $CFG->{'timeout'} = $OPTS->{'timeout'};

    if ( defined $OPTS->{'privatekey'} ) {
        $CFG->{'key_path'}   = $OPTS->{'privatekey'};
        $CFG->{'passphrase'} = $OPTS->{'passphrase'} if defined $OPTS->{'passphrase'};
        delete $CFG->{'password'};
    }
    elsif ( defined $OPTS->{'password'} ) {
        $CFG->{'password'} = $OPTS->{'password'};
        delete $CFG->{'key_path'};
        delete $CFG->{'passphrase'};
    }

    $CFG->{'master_opts'}      = [ Cpanel::SSH::Key::host_key_checking_legacy() ];
    $CFG->{'default_ssh_opts'} = [ '-o' => 'ConnectionAttempts=3', '-qt' ];

    $OPTS->{'config'} = $CFG;
    return;
}

=head2 _check_host( $opts_hr, $cfg_hr )

Ensures that the configuration values to connect and aauthenticate to the remote destination
is accurate and usable

=cut

sub _check_host {    ## no critic(RequireArgUnpacking) - passing all args for exception
    my ( $OPTS, $CFG ) = @_;

    my @missing = _missing_parameters($OPTS);
    if (@missing) {
        die Cpanel::Transport::Exception::MissingParameter->new(
            \@_, 0,
            $locale->maketext( '“[_1]” is missing the following parameters: [list_and,_2]', __PACKAGE__, \@missing ),
            \@missing
        );
    }

    my @invalid = _validate_parameters($OPTS);
    if (@invalid) {
        die Cpanel::Transport::Exception::InvalidParameter->new(
            \@_, 0,
            $locale->maketext( '“[_1]” the following parameters were invalid: [list_and,_2]', __PACKAGE__, \@invalid ),
            \@invalid
        );
    }

    # Ensure the path is relative to the home directory
    $OPTS->{'path'} =~ s/^~+//;
    $OPTS->{'path'} =~ s/^\/+//;

    # Change our parameters into ones which can be used by the Net::OpenSSH module
    _translate_parameters( $OPTS, $CFG );

    # Instantiate the Rsync object using our converted params

    my $host = $OPTS->{'host'};

    # Make connection using SSH related options
    my $ssh_obj = Net::OpenSSH->new( $host, %{$CFG} );
    if ( $ssh_obj->error ) {
        die "Can't ssh to $host: " . $ssh_obj->error;
    }

    # Let the error message be a single line so it will show up in the UI
    my $errors = $ssh_obj->error || undef;
    my $error_msg;
    if ($errors) {
        if ( ref($errors) eq 'ARRAY' ) {
            $error_msg = join( ' ', @{$errors} );
        }
        else {
            $error_msg = $errors;
        }
        $error_msg =~ s/[\r\n]//g;
    }

    if ($errors) {
        die Cpanel::Transport::Exception::Network::Connection->new( \@_, 0, $error_msg );
    }

    ## TODO: give more pointed errors like the examples below left over from the SFTP module

    if ($error_msg) {
        if ( $error_msg eq 'Connection to remote server is broken' ) {

            # An invalid key will return error 37 (which is the same as a connection error)
            die Cpanel::Transport::Exception::Network::Authentication->new( \@_, 0, $error_msg );
        }
        elsif ( int $ssh_obj->error == 37 ) {

            # 37 is SFTP_ERR_CONNECTION_BROKEN
            die Cpanel::Transport::Exception::Network::Connection->new( \@_, 0, $error_msg );
        }
        elsif ( int $ssh_obj->error == 50 ) {

            # 50 is SFTP_ERR_PASSWORD_AUTHENTICATION_FAILED
            die Cpanel::Transport::Exception::Network::Authentication->new( \@_, 0, $error_msg );
        }
        die Cpanel::Transport::Exception->new(
            \@_, 0,
            $locale->maketext( 'The rsync object failed to instantiate: [_1]', $error_msg )
        );
    }
    else {
        return $ssh_obj;
    }
}

=head2 _build_response( $args, $data )

Generic function to return a parsed response or throw and error, based on any existing error status

=cut

sub _build_response {
    my ( $self, $args, $data ) = @_;
    if ( $self->{'rsync_obj'}->error ) {
        my $error_message = $self->{'rsync_obj'}->error;
        $error_message .= "\n" . $self->{_last_err} if $self->{_last_err};
        if ( $self->{'command_response'} ) {
            chomp( $self->{'command_response'} );
            $error_message .= " : Command output => '" . $self->{'command_response'} . "'";
        }
        die Cpanel::Transport::Exception->new( $args, 0, $error_message );
    }
    else {
        delete $self->{_last_err};
        return Cpanel::Transport::Response->new( $args, 1, 'OK', $data );
    }
}

=head2 _put( $local, $remote )

Attempts to copy a single file from a local source to a remote one.

=cut

# Rsync can't rename files, it can only copy a file as it is, so we have to break out the
# base directory of a file's full path and rsync it to there

sub _put {    ## no critic(RequireArgUnpacking) - passing all args for response
    my ( $self,            $local,       $remote )        = @_;
    my ( $local_filename,  $local_path,  $local_suffix )  = File::Basename::fileparse($local);
    my ( $remote_filename, $remote_path, $remote_suffix ) = File::Basename::fileparse($remote);
    $self->{_last_err} = Capture::Tiny::capture_stderr { $self->{'rsync_obj'}->rsync_put( $self->{'rsync_opts'}, $local, $remote_path ) };
    if ( $local_filename ne $remote_filename ) {

        #Capture *does not* do what you think it does, so we have to use system, and capture in the pty instead.
        $self->{_last_err} .= Capture::Tiny::capture_stderr { $self->{'rsync_obj'}->system("mv $remote_path/$local_filename $remote") };
    }
    return $self->_build_response( \@_ );
}

=head2 _put_inc( $local, $remote )

Attempts to copy a single file or directory from a local source to a remote one, using
rsync's link-dest flag to find the latest version of a file or files in the directory

=cut

sub _put_inc {    ## no critic(RequireArgUnpacking) - passing all args for response
    my ( $self,            $local,       $remote ) = @_;
    my ( $remote_filename, $remote_path, $suffix ) = File::Basename::fileparse($remote);

    # Trailing slashes are very meaningful for rsync
    my $div = '/';

    # This is important to update if you see "code 23" errors from rsync
    if ( $remote_filename =~ m/\.tar(\.bz2|\.gz)?$/ or $remote_filename =~ m/^\.master\.meta$/ or $remote_filename =~ m/^\.sql_dump.gz$/ or $remote_filename =~ m/^backup_incomplete$/ ) {
        $div = '';
    }
    my $account_or_system_path = '/accounts/';
    if ( $remote_filename eq 'system_files.tar' ) {
        $account_or_system_path = '/system/';
    }

    # Need to update this when we start supporting incremental system backups.
    # Currently these are single tarballs generated by the transporter process, handled by put() instead
    my $relative_remote = $account_or_system_path . $remote_filename . $div;

    # If we are just sending a single, special file (designated above), not a directory, skip the link_dest check
    if ( $div eq '/' ) {
        my $link_dest = $self->_determine_most_recent_remote_backup( $local, $self->{'path'}, $relative_remote );
        if ($link_dest) {
            $link_dest .= $relative_remote;
            $link_dest =~ s/\/+/\//g;
            $self->{'rsync_opts'}{'link-dest'} = $link_dest;
        }
    }
    $self->{_last_err} = Capture::Tiny::capture_stderr { $self->{'rsync_obj'}->rsync_put( $self->{'rsync_opts'}, $local . $div, $remote ) };
    return $self->_build_response( \@_ );
}

=head2 _determine_most_recent_remote_backup( $dir_path, $remote )

Looks in a remote directory to find the most recent dated directory name that has a relevant backup
in it to use for incremental backups, ultimately used in construction of arg passed to link-dest for rsync

=cut

# Do we want to check for "forward-dated" directories, where the "most recent" might be 3 days in the future ?
sub _determine_most_recent_remote_backup {
    my ( $self, $local, $path, $remote ) = @_;
    $path =~ s/^\/?/~\// unless $path =~ /^~/;

    my $dir = $self->_ls($path);
    my @bu_dirs;
    my $date_of_local_backup;

    # Try to get the date of the local backup we are transfering, if that fails for some reason, just use the current date since it should almost always be the case
    if ( $local =~ m/\/(\d{4}\-\d{2}\-\d{2})\/accounts\// ) {
        $date_of_local_backup = $1;
    }
    else {
        $date_of_local_backup = get_current_date();
    }

    while ( my ( $index, $item ) = each @{ $dir->{'data'} } ) {
        $item->{'filename'} =~ s/[\r\n]//g;
        if ( $item->{'type'} eq 'directory' and $item->{'filename'} =~ m/^\d{4}\-\d{2}\-\d{2}$/ ) {

            # Ignore any directory for today's date
            next if ( $item->{'filename'} eq $date_of_local_backup );

            # Make sure the full path to compare against exists
            if ( $self->_remote_path_exists( $path . '/' . $item->{'filename'} . '/' . $remote ) ) {
                push( @bu_dirs, $item->{'filename'} );
            }
        }
    }
    my $latest = pop(@bu_dirs);
    if ($latest) {
        return $path . '/' . $latest;
    }
    else {
        return;
    }
}

=head2 _remote_path_exists( $path )

Verifies that the given path exists on the remote destination

=cut

sub _remote_path_exists {
    my ( $self, $path ) = @_;
    my $response = $self->{'rsync_obj'}->test("ls $path");
    return $response;
}

=head2 get_current_date()

Returns a string in the format of YYYY-MM-DD representing the current date

=cut

sub get_current_date {
    my ( $day, $month, $year ) = (localtime)[ 3, 4, 5 ];
    $day   = sprintf( "%02d", $day );
    $month = sprintf( "%02d", $month + 1 );
    $year  = sprintf( "%04d", $year + 1900 );    # blame my OCD
    return $year . '-' . $month . '-' . $day;
}

=head2 _get( $remote, $local )

Copies a remote file or directory to a local one

=cut

sub _get {
    my ( $self,           $remote,     $local )  = @_;
    my ( $local_filename, $local_path, $suffix ) = File::Basename::fileparse($local);
    $self->{_last_err} = Capture::Tiny::capture_stderr { $self->{'rsync_obj'}->rsync_get( $self->{'rsync_opts'}, $remote, $local ) };
    return $self->_build_response( \@_ );
}

=head2 _mkdir( $path )

Creates a directory on the remote destination

=cut

sub _mkdir {
    my ( $self, $path ) = @_;
    $self->{_last_err} = Capture::Tiny::capture_stderr {
        $self->{'rsync_obj'}->system( { tty => 1 }, "mkdir -p $path" )
    };
    return $self->_build_response( \@_ );
}

=head2 _chdir( $path )

A placeholder function that stores the given $path as 'cwd' in the Rsync object.

=cut

sub _chdir {
    my ( $self, $path ) = @_;

    # Rsync has no concept of chdir/cwd, so we set it as a variable to construct paths if needed
    $self->{'rsync_obj'}->{'cwd'} = $path;
    return $self->_build_response( \@_ );
}

=head2 _rmdir( $path )

Removes a directory (or file due to implementaion) and all it's contents.
Take care not to pass in a dangerous $path

=cut

sub _rmdir {
    my ( $self, $path ) = @_;
    chomp($path);

    # Is it possible that $path is eq to '/', and would we know if it is a relative path to a chrooted account or not, and block if not ?
    my $res = $self->{'rsync_obj'}->capture( { tty => 1, stderr_to_stdout => 1 }, "rm -rf $path" );
    $self->{'command_response'} = $res;
    return $self->_build_response( $self, $path );
}

=head2 _delete( $path )

Removes a file from the remote destination

=cut

sub _delete {
    my ( $self, $path ) = @_;
    my $res = $self->{'rsync_obj'}->capture( { tty => 1, stderr_to_stdout => 1 }, "rm $path" );
    $self->{'command_response'} = $res;
    return $self->_build_response( \@_ );
}

=head2 _ls( $path )

Lists a file or directory with the given $path

=cut

sub _ls {    ## no critic(RequireArgUnpacking) - passing all args for response
    my ( $self, $path ) = @_;
    my @ls = $self->{'rsync_obj'}->capture( { tty => 1 }, "ls -al $path" );
    if ( $self->{'rsync_obj'}->error ) {
        if ( int $self->{'rsync_obj'}->error == 15 ) {
            die Cpanel::Transport::Exception::PathNotFound->new( \@_, 0, $self->{'rsync_obj'}->error );
        }
        die Cpanel::Transport::Exception->new( \@_, 0, $self->{'rsync_obj'}->error );
    }
    my @response = map { $self->_parse_ls_response($_) } @ls;
    return Cpanel::Transport::Response::ls->new( \@_, 1, 'OK', \@response );
}

=head2 _pwd()

A placeholder function that retrieves the path set via _chdir

=cut

sub _pwd {
    my ($self) = @_;
    my $cwd = $self->{'rsync_obj'}->cwd;
    return $self->_build_response( \@_, $cwd );
}

1;
