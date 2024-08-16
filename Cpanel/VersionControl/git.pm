package Cpanel::VersionControl::git;

# cpanel - Cpanel/VersionControl/git.pm            Copyright 2022 cPanel, L.L.C.
#                                                           All rights reserved.
# copyright@cpanel.net                                         http://cpanel.net
# This code is subject to the cPanel license. Unauthorized copying is prohibited

=head1 NAME

Cpanel::VersionControl::git

=head1 SYNOPSIS

    use Cpanel::VersionControl ();

    my $vc = Cpanel::VersionControl->new( 'type' => 'git', ... );

=head1 DESCRIPTION

Cpanel::VersionControl::git is an implementation module for supporting
Git under the Cpanel::VersionControl system.

=cut

use strict;
use warnings;

use parent qw(Cpanel::VersionControl);

use Cpanel::Config::LoadCpUserFile      ();
use Cpanel::Exception                   ();
use Cpanel::Hostname                    ();
use Cpanel::LoadModule                  ();
use Cpanel::PwCache                     ();
use Cpanel::SafeDir::MK                 ();
use Cpanel::SafeRun::Object             ();
use Cpanel::SSH::Port                   ();
use Cpanel::Umask                       ();
use Cpanel::VersionControl::Cache       ();
use Cpanel::VersionControl::git::Remote ();
use Encode                              ();
use File::Basename                      ();
use File::Find::Rule                    ();

=head1 VARIABLES

=head2 $GIT_CMD

The full pathname of the git command we want to use.

=cut

our $GIT_CMD = '/usr/local/cpanel/3rdparty/bin/git';

=head2 $TEMPLATE_DIR

The full pathname of the standard git template directory.

=cut

our $TEMPLATE_DIR = '/usr/local/cpanel/3rdparty/share/git-cpanel';

=head1 CLASS METHODS

=head2 Cpanel::VersionControl::git-E<gt>new()

Create a new git object.

=cut

my $logger;

sub new {
    my ( $class, %args ) = @_;

    return Cpanel::VersionControl::git::Remote->new(%args)
      if defined $args{'source_repository'};

    my $self = bless( {}, $class );

    $self->_validate_creation_args( \%args );
    $self->create();

    return $self;
}

=head2 Cpanel::VersionControl::git-E<gt>deserialize()

Reconstruct an object that has been serialized via the serialize
method.

=head3 Arguments

=over 4

=item $object

The hashref we returned from the serialize method.

=back

=head3 Returns

A blessed object of the appropriate type.

=cut

sub deserialize {
    my ( $class, $object ) = @_;

    bless( $object, $class );
    for my $field ( @{ $object->supported_methods() } ) {
        delete $object->{$field};
    }

    return $object;
}

=head1 METHODS

=head2 $vc-E<gt>type()

Return the type of version control system we're using.

=head3 Returns

The string 'git'.

=cut

sub type {
    return 'git';
}

=head2 $vc-E<gt>create()

Creates an actual git repository on disk.

=head3 Arguments

This method takes no arguments

=head3 Returns

Nothing.  Completion implies success.

=head3 Dies

If the directory creation or git command fails, a Cpanel::Exception is thrown.

=head3 Notes

If the target directory does not exist, it is created before git is
invoked to ensure the directory has restricted permissions.

A bare repository (which we won't have created) can't take advantage
of any of our automation, so we won't bother doing the init if we find
a bare repo.

=cut

sub create {
    my ($self) = @_;

    my $directory = Encode::decode( 'UTF-8', $self->{'repository_root'} );
    unless ( -d $directory ) {
        my $umask = Cpanel::Umask->new(022);
        Cpanel::SafeDir::MK::safemkdir( $directory, 0700 ) or die Cpanel::Exception::create( 'IO::DirectoryCreateError', [ path => $self->{'repository_root'}, error => $! ] );
    }

    if ( !$self->_is_bare() ) {
        _run_git_command(
            'args' => [
                'init',
                "--template=$TEMPLATE_DIR/deployment",
                $self->{'repository_root'}
            ],
            'fatal' => 1
        );
    }
    $self->{'last_deployment'} = undef;

    $self->_update_repo_config();

    $self->_get_source_repo();

    Cpanel::VersionControl::Cache::update($self);

    return;
}

=head2 $vc-E<gt>update()

Update the settings of the repository.

=head3 Arguments

The update() method accepts key-value pairs on which elements to update.

=head3 Returns

Nothing.

=cut

sub update {
    my ( $self, %args ) = @_;

    if ( defined $args{'name'} ) {
        $self->{'name'} = $args{'name'};
        Cpanel::VersionControl::Cache::update($self);
    }

    $self->_set_branch( $args{'branch'} )
      if exists $args{'branch'};

    return;
}

=head2 $vc-E<gt>branch()

Returns the checked-out branch of the repository.  If there are no
commits, and therefore no branches, it will return undef.

Because we can't work with bare repositories in the same ways that we
work with working trees, we won't do any branch-handling for bare
repos.

=cut

sub branch {
    my ($self) = @_;

    return if $self->_is_bare();

    my $run    = $self->_run_git( 'args' => [ 'branch', '--list' ] );
    my $branch = (
        map { s/\((.*)\)$/$1/r }
        map { s/^\*\s*//r }
        grep /^\*/, split( /\n/, $run->stdout() )
    )[0]
      unless $run->error_code();

    return $branch;
}

=head2 $vc-E<gt>available_branches()

Returns an arrayref of the list of available branches for the
repository.

=head3 Notes

Because the list of branches can change at any time by pushing into
the repository, it is inappropriate to save this list anywhere, as it
can go out of date very quickly.

Bare repositories do have branches, but our concept of what a branch
is and does (can check it out into a working tree) is incompatible
with the capabilities that bare repositories offer.  In that case, we
return undef so callers won't get any ideas that they can "change
branches".

=cut

sub available_branches {
    my ($self) = @_;

    return if $self->_is_bare();

    my $run = $self->_run_git( 'args' => [ 'branch', '--list' ] );
    return [
        map    { s/^\*? +//r }
          grep { !m/HEAD detached/ && $_ }
          split /\n/, $run->stdout()
    ];
}

=head2 $vc-E<gt>clone_urls

Provide URLs suitable for cloning.

=head3 Notes

Our API spec leaves room for not only two types of access (read-write
and read-only), but also multiple instances of each URL type.

We explicitly do not URL-encode the directory path, because git
handles Unicode paths just fine by itself.  Furthermore, if we do try
to clone something with Unicode characters with a URL-encoded string,
it will typically clone without problems, but the resulting directory
name will also be URL-encoded, rather than the native characters that
we would probably want.

=cut

sub clone_urls {
    my ($self) = @_;

    my $user     = Cpanel::PwCache::getusername();
    my $host     = Cpanel::Config::LoadCpUserFile::load($user)->{'DOMAIN'} || Cpanel::Hostname::gethostname();
    my $ssh_port = Cpanel::SSH::Port::getport();

    if ( $ssh_port && $ssh_port != $Cpanel::SSH::Port::DEFAULT_SSH_PORT ) {
        $host .= ':' . $ssh_port;
    }

    my $obj = {
        'read_write' => [
            "ssh://$user\@$host$self->{'repository_root'}",
        ],
        'read_only' => [],
    };

    return $obj;
}

=head2 $vc-E<gt>last_update()

Provides the info for the commit at HEAD of the current branch.

=head3 Returns

A hashref of the form:

    {
        'date'       => <unix timestamp>,
        'identifier' => <commit sha>,
        'author'     => 'User Name <user@example.com>',
        'message'    => 'Added a new thing'
    }

If there are no commits in the repository, or there is strange or
missing output from the 'git log' command, last_update will return
undef.

=cut

sub last_update {
    my ($self) = @_;

    my $head;

    my $run = $self->_run_git(
        'args' => [
            'log',
            '-1',
            '--pretty=format:%H%n%an <%ae>%n%at%n%B'
        ]
    );
    my @lines = split /\n/, $run->stdout(), 4;
    if ( scalar @lines == 4 ) {
        $head = {
            'identifier' => shift @lines,
            'author'     => shift @lines,
            'date'       => shift @lines,
            'message'    => shift @lines
        };
    }

    return $head;
}

=head2 $vc-E<gt>deployable()

Returns a 0/1 value of whether the repository can be deployed or not.

=head3 Notes

We check that the repo is clean, that a C<.cpanel.yml> file is checked
into the repository itself, and whatever the super class checks.

=cut

sub deployable {
    my ($self) = @_;

    my $run = $self->_run_git( 'args' => [ 'status', '--porcelain' ] );
    return 0 unless $run->stdout() eq '';

    $run = $self->_run_git( 'args' => [ 'ls-files', '.cpanel.yml' ] );
    return 0 unless $run->stdout() eq ".cpanel.yml\n";

    return $self->SUPER::deployable();
}

=head2 $vc-E<gt>remove()

Removes a git repository from list of cpanel-controlled repositories.

=head3 Notes

The object will destroy itself after its operations are complete. No
further operations may be performed on the repository from the git
version control interface in cpanel, but no files will be removed from
user directory.

=cut

sub remove {
    my ($self) = @_;

    Cpanel::VersionControl::Cache::remove( $self->{'repository_root'} );
    %$self = ();
    return;
}

=head2 $vc-E<gt>serialize()

Return a data structure suitable for JSON encoding.

=head3 Returns

An unblessed reference to the elements which correspond to our
published representation spec, sufficient for JSON encoding.

=cut

sub serialize {
    my ($self) = @_;

    my $return = {};

    for my $field (qw(name repository_root last_deployment)) {
        $return->{$field} = $self->{$field}
          if exists $self->{$field};
    }

    $return->{'source_repository'} = {
        'remote_name' => $self->{'source_repository'}{'remote_name'},
        'url'         => $self->{'source_repository'}{'url'}
    } if $self->{'source_repository'};

    return $return;
}

=head2 $vc-E<gt>supported_methods()

Lists the fields which are supported by methods in this object.

=head3 Returns

An arrayref which contains the list of public methods which provide
field contents.

=cut

sub supported_methods {
    my ($self) = @_;

    my $methods = $self->SUPER::supported_methods();
    push @$methods, qw(type branch available_branches clone_urls last_update);
    return $methods;
}

=head1 PRIVATE METHODS

=head2 $vc-E<gt>_validate_creation_args()

Ensure that the args we get to create a new object are valid.  Inserts
the args into the object as it validates them.

=head3 Returns

Nothing.  Completion implies success.

=head3 Dies

Any missing or invalid arg will cause a Cpanel::Exception to be thrown.

=cut

sub _validate_creation_args {
    my ( $self, $args ) = @_;

    if ( !length $args->{'name'} ) {
        my $err = Cpanel::Exception::create( 'MissingParameter', [ 'name' => 'name' ] );
        _logger()->warn( $err->to_en_string_no_id() );
        die $err;
    }

    if ( $args->{'name'} =~ /[<>]/ ) {
        my $err = Cpanel::Exception::create( 'InvalidParameter', 'The repository name may not contain [list_or_quoted,_1].', [ [ '<', '>' ] ] );
        _logger()->warn( $err->to_en_string_no_id() );
        die $err;
    }

    $self->{'name'} = $args->{'name'};

    $self->_validate_repo_root( $args->{'repository_root'} );
    $self->{'repository_root'} = $args->{'repository_root'};

    return;
}

=head2 $vc-E<gt>_validate_repo_root()

Ensure that the repository root we get is valid according to our
rules.  First, it must exist, and it must not contain characters we
consider illegal:

    * | " ' ` < > [ ] { } ( ) & @ ? ; : = % # \

=head3 Returns

Nothing.  Completion implies success.

=head3 Dies

An invalid path name will cause a Cpanel::Exception to be thrown.

=cut

sub _validate_repo_root {
    my ( $self, $root ) = @_;

    unless ( defined $root ) {
        _logger()->warn('The repository_root parameter is required while creating a repository');
        die Cpanel::Exception::create( 'MissingParameter', [ 'name' => 'repository_root' ] );
    }
    if ( $root =~ m~[\s\$*|"'`<>[\]{}()&@;?:=%#\\]~ ) {
        _logger()->warn('The repository_root parameter contains illegal characters');
        die Cpanel::Exception::create( 'InvalidParameter', '“[_1]” is not a valid “[_2]”.', [ $root, 'repository_root' ] );
    }

    return;
}

=head2 $vc-E<gt>_validate_branch()

Ensure that the branch name we get exists within that repository.

=head3 Returns

Nothing.  Completion implies success.

=head3 Dies

An invalid branch name will cause a Cpanel::Exception to be thrown.

=cut

sub _validate_branch {
    my ( $self, $branch ) = @_;

    if ( $branch =~ m/ detached / ) {
        _logger()->warn("Attempting to detach head for $self->{'repository_root'}");
        die Cpanel::Exception::create(
            'InvalidParameter',
            'The system cannot manage repositories in the detached HEAD state.'
        );
    }

    if ( !grep { $_ eq $branch } @{ $self->available_branches() } ) {
        _logger()->warn("'$branch' is not a valid branch");
        die Cpanel::Exception::create(
            'InvalidParameter',
            '“[_1]” is not a valid “[_2]”.',
            [ $branch, 'branch' ]
        );
    }

    return;
}

=head2 $vc-E<gt>_set_branch()

Performs validate of a branch name, and checks out the branch for the
repository.

=cut

sub _set_branch {
    my ( $self, $branch ) = @_;

    return if !defined $branch || $self->_is_bare();

    $self->_validate_branch($branch);

    $self->_run_git(
        'args'  => [ 'checkout', $branch ],
        'fatal' => 1
    );

    return;
}

=head2 $vc-E<gt>_exists()

Determine whether the repository exists on disk.

=head3 Returns

0 if the repository has not been created, 1 if it has.

=cut

sub _exists {
    my ($self) = @_;

    if (
        -d $self->{'repository_root'}
        && (   -f "$self->{'repository_root'}/HEAD"
            || -f "$self->{'repository_root'}/.git/HEAD" )
    ) {
        return 1;
    }
    return 0;
}

=head2 $vc-E<gt>_is_bare()

Returns 0/1 whether the repository is a bare repository.

=cut

sub _is_bare {
    my ($self) = @_;

    return 0 if !-d $self->{'repository_root'};
    return 0 if !-e "$self->{'repository_root'}/HEAD";
    return 0 if -d "$self->{'repository_root'}/.git";
    return 1;
}

=head2 $vc-E<gt>_get_source_repo()

Sets the source repo for an existing repository.

=cut

sub _get_source_repo {
    my ($self) = @_;

    my $run = $self->_run_git(
        'args'  => [ 'remote', '-v' ],
        'fatal' => 0
    );

    my @origins = grep /^origin\s+/, split( /\n/, $run->stdout() ) if $run;
    if (@origins) {
        $self->{'source_repository'} = {};
        my ( $name, $url, $action ) = split( /\s+/, $origins[0] );

        $self->{'source_repository'}{'remote_name'} = $name;
        $self->{'source_repository'}{'url'}         = $url;
    }

    return;
}

=head2 $vc-E<gt>_update_repo_config()

Set the repository to automatically fast-forward when commits are
pushed into the checked-out branch, and turn off automatic garbage
collection.  Also sets file and directory permissions of the database
directory tree to user-accessible only.

=head3 Dies

If the git command fails, a Cpanel::Exception is generated.

=head3 Notes

The updateInstead option for receive.denyCurrentBranch was added to
git in version 2.3.0, so any older version of git will not work
properly.

=cut

sub _update_repo_config {
    my ($self) = @_;

    my @config     = ( 'config',                    '--local' );
    my @auto_ffwd  = ( 'receive.denyCurrentBranch', 'updateInstead' );
    my @no_auto_gc = ( 'gc.auto',                   '0' );

    for my $option ( \@auto_ffwd, \@no_auto_gc ) {
        $self->_run_git( 'args' => [ @config, @$option ] );
    }

    for my $file ( File::Find::Rule->in( $self->_repo_db_directory() ) ) {
        my $perms = ( stat $file )[2] & 07700;
        chmod $perms, $file;
    }

    $self->_add_htaccess();

    return;
}

=head2 $vc-E<gt>_add_htaccess()

Add an .htaccess to a repository.

We do adjust permissions of the .git directory to prevent other system
users from probing them, but these measures do not prevent web
services from providing the contents of the repository directory.
We'll drop a 'deny everybody' .htaccess file to prevent such
retrievals.

=head3 Notes

We can't guarantee that servers are using Apache 2.4, so we can't use
the 'Require all denied' strings that 2.4 uses.  The 2.4 builds that
we provide do contain the 2.2 compat module, so we can mostly
guarantee that the 2.2 syntax will be accepted.

=cut

sub _add_htaccess {
    my ($self) = @_;

    my $path = $self->_repo_db_directory() . '/.htaccess';

    open my $fh, '>', $path
      or die Cpanel::Exception::create(
        'IO::FileOpenError',
        [ 'path' => $path, 'error' => $! ]
      );

    print $fh "Deny from all\n";

    close $fh
      or die Cpanel::Exception::create(
        'IO::FileCloseError',
        [ 'path' => $path, 'error' => $! ]
      );

    return;
}

=head2 $vc-E<gt>_repo_db_directory()

Returns the directory where the git repository's database resides.
For a bare repo, it's the repo root, and for a repo with a working
tree, it's the .git directory.

=cut

sub _repo_db_directory {
    my ($self) = @_;

    my $path = Encode::decode( 'UTF-8', $self->{'repository_root'} );
    $path .= '/.git' unless $self->_is_bare();
    return $path;
}

=head2 $vc-E<gt>_run_git()

Change directory into a git repository and run a command.

=head3 Arguments

A hash of the appropriate arguments.  Any of the keys that
Cpanel::SafeRun::Object accepts are valid, along with:

=over 4

=item fatal

If defined, the run object will die if the command fails or times out.

=back

=head3 Returns

A Cpanel::SafeRun::Object object.

=head3 Notes

This is a wrapper around _run_git_command, which eliminates some
boilerplate that's been creeping into the codebase.

=cut

sub _run_git {
    my ( $self, %args ) = @_;

    my $cr = delete $args{'before_exec'};
    return _run_git_command(
        'before_exec' => sub {
            chdir Encode::decode( 'UTF-8', $self->{'repository_root'} )
              or die Cpanel::Exception::create(
                'IO::ChdirError',
                [
                    'path'  => $self->{'repository_root'},
                    'error' => $!
                ]
              );
            $cr->() if $cr && ref $cr eq 'CODE';
        },
        %args
    );
}

=head1 PRIVATE FUNCTIONS

=head2 Cpanel::VersionControl::git::_run_git_command()

Run a git command using the supplied arguments.

=head3 Arguments

A hash of the appropriate arguments.  Any of the keys that
Cpanel::SafeRun::Object accepts are valid, along with:

=over 4

=item fatal

If defined, the run object will die if the command fails or times out.

=back

=head3 Returns

A Cpanel::SafeRun::Object object.

=head3 Dies

If the 'fatal' argument is passed in, a Cpanel::Exception will be
thrown if the command fails or times out.

=head3 Notes

If there is a fatal failure, the exception is logged.

=cut

sub _run_git_command {
    my (%args) = @_;

    my $fatal = defined $args{'fatal'} ? 1 : 0;

    my $prog = \&Cpanel::SafeRun::Object::new;
    if ($fatal) {
        $prog = \&Cpanel::SafeRun::Object::new_or_die;
        delete $args{'fatal'};
    }

    if ( exists $args{'stdout'} ) {
        my $fh = $args{'stdout'};
        print $fh 'Running command: ' . join( ' ', $GIT_CMD, @{ $args{'args'} } ) . "\n\n";
    }

    my $run;
    eval { $run = $prog->( 'Cpanel::SafeRun::Object', 'program' => $GIT_CMD, %args ); };

    if ($@) {
        my $err = Cpanel::Exception::get_string($@);
        _logger()->warn($err);
        die $err if $fatal;
    }

    return $run;
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

=head1 TODO

Use the C<Cpanel::VersionControl::Deployment> interface to handle the
C<last_deployment> field as a method, rather than storing it directly
in the cache file.

=head1 DEPENDENCIES

L<Cpanel::Config::LoadCpUserFile>,
L<Cpanel::Exception>, L<Cpanel::Hostname>, L<Cpanel::PwCache>,
L<Cpanel::SafeDir::MK>, L<Cpanel::SafeDir::RM>,
L<Cpanel::SafeRun::Object>, L<Cpanel::VersionControl>,
L<Cpanel::VersionControl::Cache>,
L<Cpanel::VersionControl::git::Remote>, and L<Find::File::Rule>

=head1 TODO

Move the C<last_deployment> key out of these objects.  It should be
queried from the C<Cpanel::VersionControl::Deployment> layer.  The
base class can provide a C<last_deployment> method to retrieve, and
add the method to its C<allowed_methods> list.

=head1 SEE ALSO

L<Cpanel::VersionControl>

=head1 LICENSE AND COPYRIGHT

Copyright (c) 2018, cPanel, Inc.  All rights reserved.  This code is
subject to the cPanel license.  Unauthorized copying is prohibited.

=cut

1;
