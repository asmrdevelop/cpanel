package Cpanel::VersionControl::Deployment;

# cpanel - Cpanel/VersionControl/Deployment.pm     Copyright 2022 cPanel, L.L.C.
#                                                           All rights reserved.
# copyright@cpanel.net                                         http://cpanel.net
# This code is subject to the cPanel license. Unauthorized copying is prohibited

=head1 NAME

Cpanel::VersionControl::Deployment

=head1 SYNOPSIS

    use Cpanel::VersionControl::Deployment ();

    my $dep = Cpanel::VersionControl::Deployment->new(
        'repository_root' => '/home/example/proj/myproj',
        'log_file'        => '/home/example/.cpanel/logs/some.log'
    );

    $dep->execute();

=head1 DESCRIPTION

Cpanel::VersionControl::Deployment is the interface for performing
deployments for any C<Cpanel::VersionControl> objects.  The
constructor performs a suite of validations on the input parameters,
and a validation on the state of the repository in question.  The
execute method performs the deployment.

=cut

use strict;
use warnings;

use Cpanel::Exception                      ();
use Cpanel::FindBin                        ();
use Cpanel::PwCache                        ();
use Cpanel::SafeDir::MK                    ();
use Cpanel::SafeRun::Object                ();
use Cpanel::Shell                          ();
use Cpanel::TempFile                       ();
use Cpanel::VersionControl::Cache          ();
use Cpanel::VersionControl::Deployment::DB ();
use Time::HiRes                            ();
use Cpanel::YAML                           ();

=head1 CLASS METHODS

=head2 Cpanel::VersionControl::Deployment-E<gt>new()

Creates a new deployment object.

=head3 Required argument keys

=over 4

=item repository_root

The absolute path of a repository that is managed by the
C<Cpanel::VersionControl> system.

=item log_file

The absolute path of a log file that expects to receive log
information for this deployment.

=back

=head3 Returns

An object of type C<Cpanel::VersionControl::Deployment>.

=head3 Dies

If any of the validation steps fails, the constructor will throw a
C<Cpanel::Exception>.

=cut

sub new {
    my ( $class, %args ) = @_;

    my $self = bless( {}, __PACKAGE__ );

    $self->_validate_args( \%args );
    $self->_validate_state();

    return $self;
}

=head2 $dep-E<gt>execute()

Perform the deployment.

The execute method loads up the set of tasks to be performed, and
performs them.

=cut

sub execute {
    my ($self) = @_;

    my $fh = $self->{'fh'} or return;

    $self->{'db'}->activate( $self->{'deploy_id'}, $self->{'vc'} );

    my $tempfile = $self->_prepare_tasks();
    my $cagefs   = $self->_get_cagefs_enter();

    my $run = Cpanel::SafeRun::Object->new(
        'program' => $cagefs ? $cagefs : $self->_get_user_shell(),
        'args'    => [$tempfile],
        'stdout'  => $fh,
        'stderr'  => $fh,
    );
    my $code = $run->error_code() || 0;
    my $now  = Time::HiRes::gettimeofday();
    print $fh "$now\nBuild completed with exit code $code\n";
    close $fh or die Cpanel::Exception::create(
        'IO::FileCloseError',
        [ 'path' => $self->{'log_file'}, 'error' => $! ]
    );

    $self->{'db'}->stamp(
        $self->{'deploy_id'},
        $code ? 'failed' : 'succeeded'
    );

    delete $self->{'fh'};
    delete $self->{'tempfile'};
    delete $self->{'shell'};

    $self->_update_vc_object() unless $code;

    return;
}

=head1 PRIVATE METHODS

=head2 $dep-E<gt>_prepare_tasks()

Collects the set of tasks from C<.cpanel.yml> in the repository's root
directory, and produces a script which will run those tasks.

=cut

sub _prepare_tasks {
    my ($self) = @_;

    my $yaml  = Cpanel::YAML::LoadFile("$self->{'vc'}{'repository_root'}/.cpanel.yml");
    my $tasks = $yaml->{'deployment'}{'tasks'} if ref $yaml eq 'HASH';
    my $fh    = $self->{'fh'};

    unless ($tasks) {
        my $now = Time::HiRes::gettimeofday();
        print $fh "$now\nfatal: invalid yaml format.\n";
        die Cpanel::Exception::create(
            'IO::FileReadError',
            [ 'path' => "$self->{'vc'}{'repository_root'}/.cpanel.yml" ]
        );
    }

    return $self->_write_tasks_script($tasks);
}

=head2 $dep-E<gt>_write_tasks_script()

Produces a script which will run each task, capture the exit code, and
exit the process if one of the tasks fails.

=cut

sub _write_tasks_script {
    my ( $self, $tasks ) = @_;

    my ( $tempfile, $tfh ) = $self->_prepare_temp_file();

    my $cagefs = $self->_get_cagefs_enter();
    my $shell  = $self->_get_user_shell();

    print $tfh '#!' . "$shell\n\n" if $cagefs;
    print $tfh "cd $self->{'vc'}{'repository_root'}\n\n";

    for my $task (@$tasks) {
        print $tfh <<"SEGMENT";
/bin/date '+\%s.\%N'
/bin/cat <<'EOH'
\$ $task
EOH
$task
exit=\$?
/bin/cat <<EOF

Task completed with exit code \$exit.

EOF
if [ \$exit != 0 ]
then
    exit \$exit
fi
SEGMENT
    }
    close $tfh or die Cpanel::Exception::create(
        'IO::FileCloseError',
        [ 'path' => $tempfile, 'error' => $! ]
    );

    return $tempfile;
}

=head2 $dep-E<gt>_prepare_temp_file()

Ensures the required configuration for creating the temporary
deployment script, and creates the temp file.  Returns the filename
and an open file handle.

=cut

sub _prepare_temp_file {
    my ($self) = @_;

    my $homedir = Cpanel::PwCache::gethomedir();
    Cpanel::SafeDir::MK::safemkdir("$homedir/tmp");

    $self->{'tempfile'} = Cpanel::TempFile->new( { 'path' => "$homedir/tmp" } );
    my ( $tempfile, $tfh ) = $self->{'tempfile'}->file();
    chmod 0700, $tempfile;

    return ( $tempfile, $tfh );
}

=head2 $vc-E<gt>_load_vc_object()

Loads the C<Cpanel::VersionControl> object from the disk cache.

If there is no object found, the function throws a
C<Cpanel::Exception>.

=cut

sub _load_vc_object {
    my ($self) = @_;

    my $vc = Cpanel::VersionControl::Cache::retrieve( $self->{'args'}{'repository_root'} );
    die Cpanel::Exception::create(
        'InvalidParameter',
        '“[_1]” is not a valid “[_2]”.',
        [ $self->{'args'}{'repository_root'}, 'repository_root' ]
    ) unless defined $vc;

    $self->{'vc'} = $vc;

    return;
}

=head2 $dep-E<gt>_load_deploy_id()

Load the deployment ID from the database.

If there is no relevant ID found, throws a C<Cpanel::Exception>.

=cut

sub _load_deploy_id {
    my ($self) = @_;

    $self->{'db'} = Cpanel::VersionControl::Deployment::DB->new();

    my ($dep) = grep { $_->{'repository_root'} eq $self->{'args'}{'repository_root'} && $_->{'log_path'} eq $self->{'args'}{'log_file'} && $_ } @{ $self->{'db'}->retrieve() };

    die Cpanel::Exception::create(
        'InvalidParameter',
        'No such deployment exists.'
    ) unless defined $dep;

    $self->{'deploy_id'} = $dep->{'deploy_id'};

    return;
}

=head2 $dep-E<gt>_update_vc_object()

Updates the 'last_deployment' field in the VersionControl object cache.

=head3 Notes

We reload the object from the cache once we're done with the
deployment in an attempt to minimize any race conditions with other
object updates.  Deployments may take some time, and the cached
information could have been updated over the course of the deployment.

=cut

sub _update_vc_object {
    my ($self) = @_;

    $self->{'vc'} = Cpanel::VersionControl::Cache::retrieve( $self->{'vc'}{'repository_root'} );
    return unless $self->{'vc'};

    my $deploy = $self->{'db'}->retrieve( $self->{'deploy_id'} );
    $self->{'vc'}{'last_deployment'} = $deploy;
    Cpanel::VersionControl::Cache::update( $self->{'vc'} );

    return;
}

=head2 $dep-E<gt>_validate_args()

Validates the two arguments, C<log_file> and C<repository_root>.  If
there is anything wrong with either of the arguments, this function
will throw a C<Cpanel::Exception>.

=cut

sub _validate_args {
    my ( $self, $args ) = @_;

    my $homedir = Cpanel::PwCache::gethomedir();

    die Cpanel::Exception::create(
        'MissingParameter',
        [ 'name' => 'log_file' ]
    ) unless length $args->{'log_file'};
    if (   $args->{'log_file'} !~ m~^\Q$homedir/.cpanel/logs/\E~
        || $args->{'log_file'} =~ m~/\.\./~
        || !-f $args->{'log_file'} ) {
        die Cpanel::Exception::create(
            'InvalidParameter',
            '“[_1]” is not a valid “[_2]”.',
            [ $args->{'log_file'}, 'log_file' ]
        );
    }

    open $self->{'fh'}, '>>', $args->{'log_file'}
      or die Cpanel::Exception::create(
        'IO::FileOpenError',
        [ 'path' => $args->{'log_file'}, 'mode' => '>>', 'error' => $! ]
      );

    die Cpanel::Exception::create(
        'MissingParameter',
        [ 'name' => 'repository_root' ]
    ) unless length $args->{'repository_root'};

    $self->{'args'} = $args;

    $self->_load_vc_object();
    $self->_load_deploy_id();

    return;
}

=head3 $dep-E<gt>_validate_state()

Validates the current state of the repository.  Dies with a
C<Cpanel::Exception> if the repository is not in a valid state to be
deployed.

=cut

sub _validate_state {
    my ($self) = @_;

    die Cpanel::Exception::create(
        'InvalidInvocation',
        'Repository “[_1]” is not in a deployable state.',
        [ $self->{'vc'}{'repository_root'} ]
    ) unless $self->{'vc'}->deployable();

    return;
}

=head3 $dep-E<gt>_get_user_shell()

Fetches the user's shell, and falls back to jailshell if their
configured shell is not usable (i.e. noshell or /bin/false).

=cut

sub _get_user_shell {
    my ($self) = @_;

    my $shell = Cpanel::Shell::get_shell();

    if ( $shell eq $Cpanel::Shell::JAIL_SHELL
        || !Cpanel::Shell::is_usable_shell($shell) ) {
        return $Cpanel::Shell::JAIL_SHELL;
    }

    return '/bin/bash';
}

=head3 $dep-E<gt>_get_cagefs_enter()

Fetches the location of cagefs_enter if it exists. Returns
undef if it does not exist.

=cut

my $cagefs_enter;

sub _get_cagefs_enter {
    my ($self) = @_;

    return $cagefs_enter if $cagefs_enter;

    return $cagefs_enter = Cpanel::FindBin::findbin('cagefs_enter.proxied');
}

=head1 CONFIGURATION AND ENVIRONMENT

There are no configuration files or environment variables which
are required or produced by this module.

=head1 DEPENDENCIES

L<Cpanel::Exception>, L<Cpanel::PwCache>, L<Cpanel::SafeDir::MK>,
L<Cpanel::SafeRun::Object>, L<Cpanel::Shell>, L<Cpanel::TempFile>,
L<Cpanel::VersionControl::Cache>,
L<Cpanel::VersionControl::Deployment::DB>, L<Time::HiRes>, and
L<Cpanel::YAML>.

=head1 LICENSE AND COPYRIGHT

Copyright (c) 2018, cPanel, Inc.  All rights reserved.  This code is
subject to the cPanel license.  Unauthorized copying is prohibited.

=cut

1;
