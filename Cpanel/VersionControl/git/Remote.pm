package Cpanel::VersionControl::git::Remote;

# cpanel - Cpanel/VersionControl/git/Remote.pm     Copyright 2022 cPanel, L.L.C.
#                                                           All rights reserved.
# copyright@cpanel.net                                         http://cpanel.net
# This code is subject to the cPanel license. Unauthorized copying is prohibited

=head1 NAME

Cpanel::VersionControl::git::Remote

=head1 SYNOPSIS

    use Cpanel::VersionControl ();

    my $vc = Cpanel::VersionControl->new(
        'type' => 'git',
        'source_repository' => {
            'name' => 'somename',
            'url' => 'https://...'
        },
        ...
    );

=head1 DESCRIPTION

Cpanel::VersionControl::git::Remote is an implementation module for
supporting Git under the Cpanel::VersionControl system, and creation
via cloning from a remote.

=cut

use strict;
use warnings;

use parent qw(Cpanel::VersionControl::git);

use Cpanel::Config::LoadCpConf    ();
use Cpanel::Exception             ();
use Cpanel::LoadModule            ();
use Cpanel::PwCache               ();
use Cpanel::SafeDir::MK           ();
use Cpanel::Umask                 ();
use Cpanel::Validate::URL         ();
use Cpanel::VersionControl::Cache ();
use Cpanel::VersionControl::git   ();
use Encode                        ();
use Try::Tiny;

=head1 VARIABLES

=head2 $GIT_READ_TIMEOUT

The length of time in seconds we're willing to wait for git to start
responding from remote servers.  Default is 5 seconds.

=cut

our $GIT_READ_TIMEOUT = 5;

my $logger;
our $host_key_cr;

=head1 METHODS

=head2 Cpanel::VersionControl::git::Remote-E<gt>new()

Create a new remote git object.

=head3 Notes

The clone operation is done in the user's task queue.

=cut

sub new {
    my ( $class, %args ) = @_;

    my $self = bless( {}, $class );

    $self->_validate_creation_args( \%args );

    Cpanel::LoadModule::load_perl_module('Cpanel::UserTasks');

    my ($log_file) = $self->log_file('create');
    Cpanel::UserTasks->new()->add(
        'subsystem' => 'VersionControl',
        'action'    => 'create',
        'args'      => {
            'repository_root' => $self->{'repository_root'},
            'log_file'        => $log_file
        }
    );

    return $self;
}

=head2 $vc-E<gt>create()

Clones the source repository into the repository path.

=head3 Returns

Nothing.  Completion implies success.

=head3 Dies

If the directory creation or git clone command fails, a Cpanel::Exception
will be thrown.

=head3 Notes

The target directory is created before git is invoked to ensure the
directory has restricted permissions.

=cut

sub create {
    my ( $self, $log_file ) = @_;

    if ( !$self->_exists() ) {
        my $fh = $self->_validate_log_file($log_file);
        my $cr = $self->_handle_ssh_host_options();

        my $directory = Encode::decode( 'utf-8', $self->{'repository_root'} );
        try {
            unless ( -d $directory ) {
                my $umask = Cpanel::Umask->new(022);
                Cpanel::SafeDir::MK::safemkdir( $directory, 0700 ) or die Cpanel::Exception::create( 'IO::DirectoryCreateError', [ path => $self->{'repository_root'}, error => $! ] );
            }
            Cpanel::VersionControl::git::_run_git_command(
                'args' => [
                    'clone',
                    "--origin=$self->{'source_repository'}{'remote_name'}",
                    $self->{'source_repository'}{'url'},
                    $directory
                ],
                'stdout' => $fh,
                'stderr' => $fh,
                'fatal'  => 1,
                defined $cr ? ( 'before_exec' => $cr ) : (),
            );
        }
        catch {
            my $err = $_;
            Cpanel::VersionControl::Cache::remove( $self->{'repository_root'} );
            print $fh "$self->{'repository_root'} may exist, and may need to be cleaned up.";
            die $err;
        };
        close $fh || die Cpanel::Exception::create(
            'IO::FileCloseError',
            [ 'path' => $log_file, 'error' => $! ]
        );
    }

    $self->SUPER::create();

    return;
}

=head2 $vc-E<gt>update()

Perform an update of repository parameters.  Also perform a fetch of
the upstream repository.

=head3 Arguments

The update() method accepts key-value pairs on which elements to update.

=head3 Returns

Nothing.

=head3 Notes

Most of the operation of this function lies in the superclass's update
method.  This function deals entirely with remotes.  Since we consider
that we can only have one remote that we consider "upstream", we will
only handle one.

=cut

sub update {
    my ( $self, %args ) = @_;

    if ( defined $args{'source_repository'} ) {
        my $repo = $args{'source_repository'};
        if ( defined $repo->{'remote_name'} ) {
            $self->_update_remote_name( $repo->{'remote_name'} );
        }

        # We will not be handling updating of the remote's URL for now.
    }

    my $cr = $self->_handle_ssh_host_options();
    $self->_run_git(
        'args' => [
            'fetch',
            $self->{'source_repository'}{'remote_name'}
        ],
        defined $cr ? ( 'before_exec' => $cr ) : (),
    );

    $self->SUPER::update(%args);

    return;
}

=head2 $vc-E<gt>available_branches()

Returns an arrayref of the list of available branches for the remote
repository.

=head3 Notes

Because the list of branches can change at any time by pushing into
the repository, it is inappropriate to save this list anywhere, as it
can go out of date very quickly.

=cut

sub available_branches {
    my ($self) = @_;

    # We won't worry about getting into the repo root, because this
    # method could be called before the clone has actually occurred.
    #
    # TODO:  rethrows for logging are for amateurs.  The API should be
    # logging these failures, because it's the one that actually
    # handles them.  We should not be the ones who need to handle
    # logging.
    my $run;
    my $cr = $self->_handle_ssh_host_options();
    try {
        $run = Cpanel::VersionControl::git::_run_git_command(
            'args' => [
                'ls-remote',
                '--heads',
                $self->{'source_repository'}{'url'}
            ],
            'read_timeout' => $GIT_READ_TIMEOUT,
            'fatal'        => 1,
            defined $cr ? ( 'before_exec' => $cr ) : (),
        );
    }
    catch {
        my $err = $_;

        _logger()->warn("The system encountered an error when it attempted to retrieve the remote repository for $self->{'repository_root'}:");
        _logger()->warn($err);
        die $err;
    };
    my %branches = map { $_ => 1 } @{ $self->SUPER::available_branches() };
    for my $branch ( split /\n/, $run->stdout() ) {
        $branch =~ s~.*refs/heads/~~;
        $branches{$branch} = 1;
    }
    return [ sort keys %branches ];
}

=head2 $vc-E<gt>serialize()

Return a data structure suitable for JSON encoding.

=head3 Returns

An unblessed reference to the elements which correspond to our
published representation spec, sufficient for JSON encoding.

=cut

sub serialize {
    my ($self) = @_;

    my $return = $self->SUPER::serialize();

    $return->{'source_repository'} = {
        'remote_name' => $self->{'source_repository'}{'remote_name'},
        'url'         => $self->{'source_repository'}{'url'}
    };

    return $return;
}

=head1 PRIVATE METHODS

=head2 _validate_creation_args()

Ensure that the args we get to create a new object are valid.  Inserts
the args into the object as it validates them.

=head3 Returns

Nothing.  Completion implies success.

=head3 Dies

Any missing or invalid arg will cause a Cpanel::Exception to be thrown.

=head3 Notes

This will blow up on a URL with a username/password pair.  That can
appear in ps output, so rather than possibly leak it, we'll prevent
using it in the first place.

=cut

sub _validate_creation_args {
    my ( $self, $args ) = @_;

    $self->SUPER::_validate_creation_args($args);

    if ( $args->{'repository_root'} && -e $args->{'repository_root'} ) {
        $self->_ensure_directory_empty( $args->{'repository_root'} );
    }

    $self->{'source_repository'}{'remote_name'} = $args->{'source_repository'}{'remote_name'} || 'origin';

    unless ( defined $args->{'source_repository'}{'url'} ) {
        _logger()->warn("You must supply a remote URL when you clone a repository.");
        die Cpanel::Exception::create( 'MissingParameter', [ 'name' => 'url' ] );
    }

    if ( $args->{'source_repository'}{'url'} =~ m~://[^/]+:[^/]+@~ ) {
        _logger()->warn( Encode::encode( 'utf-8', "“$args->{'source_repository'}{'url'}” contains a password. You cannot use this URL." ) );
        die Cpanel::Exception::create( 'InvalidParameter', '“[_1]” contains a password. You cannot use this URL.', [ Encode::decode( 'utf-8', $args->{'source_repository'}{'url'} ) ] );
    }

    if ( !Cpanel::Validate::URL::is_valid_url( $args->{'source_repository'}{'url'} ) ) {
        _logger()->warn("“$args->{'source_repository'}{'url'}” is not a valid URL.");
        die Cpanel::Exception::create( 'InvalidParameter', '“[_1]” is not a valid URL.', [ Encode::decode( 'utf-8', $args->{'source_repository'}{'url'} ) ] );
    }

    $self->{'source_repository'}{'url'} = $args->{'source_repository'}{'url'};

    Cpanel::VersionControl::Cache::update($self);

    return;
}

=head2 _ensure_directory_empty()

If the target directory is not empty, cloning will fail. Prevents that
situation from happening and provides a clear error message.

=head3 Returns

Nothing.  Completion implies success.

=head3 Dies

If the target directory can not be read or is not empty, a Cpanel::Exception
is thrown.

=cut

sub _ensure_directory_empty {
    my ( $self, $dir ) = @_;

    my $dh;
    unless ( opendir $dh, $dir ) {
        _logger()->warn("The system could not read the “$dir” directory.");
        die Cpanel::Exception::create( 'IO::DirectoryReadError', [ path => $dir, error => $! ] );
    }

    while ( readdir $dh ) {
        if ( !/^\.\.?$/ ) {
            close $dh;
            _logger()->warn("Files already exist in directory “$dir”.");
            die Cpanel::Exception::create( 'InvalidParameter', 'You cannot use the “[_1]” directory because it already contains files.', [$dir] );
        }
    }
    close $dh;

    return;
}

=head2 $vc-E<gt>_set_branch()

Checks out the specified branch.  Performs a comparison against the
set of remote branches, and creates a local tracking branch if one
doesn't already exist.  If it is a remote tracking branch, will also
perform an upstream fast-forward-only pull.

=cut

sub _set_branch {
    my ( $self, $branch ) = @_;

    return if $self->_is_bare();

    my $cr = $self->_handle_ssh_host_options();
    if ( defined $branch ) {
        $self->_validate_branch($branch);

        my $run = $self->_run_git( 'args' => [ 'checkout', $branch ] );
        if ( $run->error_code() ) {
            $self->_run_git(
                'args' => [
                    'checkout',
                    '-b',
                    $branch,
                    "$self->{'source_repository'}{'remote_name'}/$branch"
                ],
                'fatal' => 1,
                defined $cr ? ( 'before_exec' => $cr ) : (),
            );
        }
    }

    $self->_run_git(
        'args'  => [ 'pull', '--ff-only', '--recurse-submodules' ],
        'fatal' => 1,
        defined $cr ? ( 'before_exec' => $cr ) : (),
    ) if $self->_tracking_branch();

    return;
}

=head2 $vc-E<gt>_tracking_branch()

Returns 0/1 whether the current branch is a tracking branch.

=cut

sub _tracking_branch {
    my ($self) = @_;

    my $branch = $self->branch();

    my $run = $self->_run_git(
        'args' => [
            'config',
            '--local',
            '--get',
            "branch.${branch}.remote"
        ]
    );

    return 0 if $run->error_code();
    return 1;
}

=head2 $vc-E<gt>_update_remote_name()

Change the name of the remote we have as our "origin".

=head3 Arguments

The new name of the remote we manage.

=head3 Returns

Nothing.

=head3 Dies

If the git command fails, a Cpanel::Exception will be thrown.

=cut

sub _update_remote_name {
    my ( $self, $name ) = @_;

    return if $name eq $self->{'source_repository'}{'remote_name'};

    $self->_run_git(
        'args' => [
            'remote',
            'rename',
            $self->{'source_repository'}{'remote_name'},
            $name
        ]
    );
    $self->{'source_repository'}{'remote_name'} = $name;

    return;
}

=head2 $vc-E<gt>_validate_log_file()

Validates location of log file and open a file handle for writing.

=head3 Arguments

Full path to a log file.

=head3 Returns

A file handle for appending to log file.

=head3 Dies

Under these conditions:

=over 4

=item log_file is not provided.

=item log file path is not under ~/.cpanel/logs

=item log file path contains /../

=item log file does not exist

=item unable to write to log file

=back

=cut

sub _validate_log_file {
    my ( $self, $log_file ) = @_;

    my $homedir = Cpanel::PwCache::gethomedir();

    die Cpanel::Exception::create(
        'MissingParameter',
        [ 'name' => 'log_file' ]
    ) unless $log_file;
    if (   $log_file !~ m~^$homedir/.cpanel/logs/~
        || $log_file =~ m~/\.\./~
        || !-f $log_file ) {
        die Cpanel::Exception::create(
            'InvalidParameter',
            '“[_1]” is not a valid “[_2]”.',
            [ $log_file, 'log file' ]
        );
    }

    open my $fh, '>>', $log_file
      or die Cpanel::Exception::create(
        'IO::FileOpenError',
        [ 'path' => $log_file, 'mode' => '>>', 'error' => $! ]
      );

    return $fh;
}

=head2 $vc-E<gt>_handle_ssh_host_options()

Gets a code reference that is needed to handle the server's
host key configuration for ssh.

=head3 Arguments

None.

=head3 Returns

A code ref or undef.

=cut

sub _handle_ssh_host_options {
    my ($self) = @_;

    return $host_key_cr if $host_key_cr;

    my $value = Cpanel::Config::LoadCpConf::loadcpconf()->{'ssh_host_key_checking'};

    if ( !$value ) {
        $host_key_cr = sub {
            $ENV{'GIT_SSH_COMMAND'} = 'ssh -oStrictHostKeyChecking=no';
        };
    }
    elsif ( $value eq 'dns' ) {
        $host_key_cr = sub {
            $ENV{'GIT_SSH_COMMAND'} = 'ssh -oStrictHostKeyChecking=yes -oVerifyHostKeyDNS=yes';
        };
    }
    else {
        $host_key_cr = sub {
            $ENV{'GIT_SSH_COMMAND'} = 'ssh -oStrictHostKeyChecking=yes';
        };
    }

    return $host_key_cr;
}

sub _logger {
    return $logger ||= do {
        Cpanel::LoadModule::load_perl_module('Cpanel::Logger');
        Cpanel::Logger->new();
    };
}

=head1 CONFIGURATION AND ENVIRONMENT

There are no configuration files or environment variables which
are required or produced by this module.

=head1 DEPENDENCIES

L<Cpanel::Exception>, L<Cpanel::LoadModule>, L<Cpanel::Validate::URL>,
L<Cpanel::VersionControl::Cache>, L<Cpanel::VersionControl::git>,
and L<Encode>.

=head1 SEE ALSO

L<Cpanel::VersionControl>, L<Cpanel::VersionControl::git>

=head1 LICENSE AND COPYRIGHT

Copyright (c) 2018, cPanel, Inc.  All rights reserved.  This code is
subject to the cPanel license.  Unauthorized copying is prohibited.

=cut

1;
