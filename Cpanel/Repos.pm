package Cpanel::Repos;

# cpanel - Cpanel/Repos.pm                         Copyright 2022 cPanel, L.L.C.
#                                                           All rights reserved.
# copyright@cpanel.net                                         http://cpanel.net
# This code is subject to the cPanel license. Unauthorized copying is prohibited

use cPstrict;

use Cpanel::Async::EasyLock              ();
use Cpanel::Autowarn                     ();
use Cpanel::Binaries                     ();
use Cpanel::Debug                        ();
use Cpanel::Exception                    ();
use Cpanel::FileUtils::Copy              ();
use Cpanel::FileUtils::Dir               ();
use Cpanel::OS                           ();
use Cpanel::Pkgr                         ();
use Cpanel::PromiseUtils                 ();
use Cpanel::Repos::Utils                 ();
use Cpanel::SafeRun::Object              ();
use Cpanel::SysPkgs::YUM                 ();
use Cpanel::Transaction::File::Raw       ();
use Cpanel::Validate::FilesystemNodeName ();
use Cpanel::Validate::FilesystemNodeName ();
use Cpanel::Version::Compare::Package    ();

#Made a global for testing.
our $REPOS_DIR        = "/usr/local/cpanel/etc/rpm";
our $TARGET_REPOS_DIR = '/etc/yum.repos.d';

=head1 NAME

Cpanel::Repos

=head1 SYNOPSIS

  my $repos = Cpanel::Repos->new();
  $repos->install_repo( name => 'MyRepo' );

=head1 DESCRIPTION

Cpanel::Repos handles the installation of YUM repo files for cPanel-provided software to /etc/yum.repos.d.

=head1 SETTING UP A REPO

There are two types of repo files that you can provide using this tool.

=head2 Platform-specific:

In order for the B<install_repo()> method to work on a given system, there needs to be a set of subdirectories
under B</usr/local/cpanel/etc/rpm> that correspond to the attributes of that system. At the deepest level, there
should be a single file called "yumrepo" that has the repo file contents for that combination of system attributes.

The directory structure looks like this:

  * OS
    * OS version
      * Package
        * Arch
          * "yumrepo"

Example:

  /usr/local/cpanel/etc/rpm/centos/6/MyRepo/x86_64/yumrepo
    would be the repo file for MyRepo on CentOS 6 x86_64.

  The "yumrepo" file would be copied to /etc/yum.repos.d/MyRepo.repo

Notes:

- "centos" and "rhel" are maintained as separate OS types in the directory tree (not symlinked), so make sure to
populate both.

- If you don't need to support a given platform (e.g. 32-bit OSes), it's OK to leave some segments of the
directory tree missing. If such a system attempts to install the repo file via this module, an exception will
be thrown.

=head2 Platform-independent:

If you have a single repo file that works correctly on all supported platforms (either through use of YUM
variables to adjust the URL or because the package itself is truly platform-agnostic), you can provide it
under the B<generic> directory to avoid duplicating it per combination of platform attributes.

With this configuration, the directory tree is simplified

  * "generic"
    * Package
      * "yumrepo"

Example:

  /usr/local/cpanel/etc/rpm/generic/MyRepo/yumrepo
    would be the repo file for MyRepo regardless of platform.

  The "yumrepo" file would be copied to /etc/yum.repos.d/MyRepo.repo

=head1 CONSTRUCTION

=head2 Parameters

   none

=head2 Returns

   A Cpanel::Repos object

=cut

sub new {
    my ($class) = @_;

    my $self = {
        'yum.conf' => $Cpanel::SysPkgs::YUM::YUM_CONF,
    };

    bless $self, $class;

    return $self;
}

=head1 METHODS

=head2 $repos->install_repo( name => ..., obsoletes => ... )

Creates a Cpanel::Repos object

=head3 Parameters

=over

=item * name - String - The name of the repo to install from ULC/etc/rpm. See the section above called
B<SETTING UP A REPO> for more information on how this nedes to be structured.

=item * 'obsoletes' - Regexp (qr//) - (Optional) A stored regular expression for matching repos that should be
removed because they conflict with the one being installed.

=item * 'repo_contents' - String - (Optional) The yum repo file as a string. If this string is passed in, other lookups
will be ignored and this string will be used as the yum repo file. This string should be the entire yum repo file.
It can contain newlines.

=back

=head3 Returns

  A truthy value upon successful install on the repo
    1: The repo was installed
    2: The repo was already installed

  On failure this function generates an exception

=head3 Throws

- Cpanel::Exception::IO::FileCopyError will be thrown if the repo file can't be installed
due to a file copy failure.

- Cpanel::Exception::IO::DirectoryOpenError or Cpanel::Exception::IO::DirectoryReadError if
there is a problem reading from /etc/yum.repos.d.

- Generic exceptions

=cut

sub install_repo ( $self, %OPTS ) {

    my $name = $OPTS{name} or die "The name of the repo is required";
    Cpanel::Validate::FilesystemNodeName::validate_or_die($name);

    # do not use a global lock using Cpanel::Pkgr::lock_for_external_install
    #   or this voids the advantage of installing MySQL in background on fresh installation

    my $p    = Cpanel::Async::EasyLock::lock_exclusive_p( "InstallRepo", timeout => 3_600 );
    my $lock = Cpanel::PromiseUtils::wait_anyevent($p)->get();                                 # can die on failure

    return int $self->_install_repo_under_lock(%OPTS);
}

sub _install_repo_under_lock ( $self, %OPTS ) {

    my $name          = delete $OPTS{name} or die "The name of the repo is required";
    my $repo_contents = delete $OPTS{'repo_contents'};
    my $obsoletes     = delete $OPTS{'obsoletes'};
    my $logger        = delete $OPTS{'logger'} // Cpanel::Debug::logger();

    if ( scalar %OPTS ) {
        die qq[install_repo: unknown options: ] . join( ', ', sort keys %OPTS );
    }

    # Start out looking for a platform-specific repo file.
    my $repo_file = "$REPOS_DIR/" . Cpanel::OS::distro() . '/' . Cpanel::OS::major() . '/' . "$name/" . Cpanel::OS::arch() . '/yumrepo';    ## no critic(Cpanel::CpanelOS) repo template

    if ( !$repo_contents ) {

        # If that doesn't exist, try looking for a platform-independent repo file.
        # This repo file should contain any necessary YUM variables to automatically
        # adjust the URL as needed.
        if ( !-e $repo_file ) {
            $repo_file = "$REPOS_DIR/generic/$name/yumrepo";
        }

        if ( !-e $repo_file ) {
            my $pkg_file = $self->_find_pkg($name);

            if ( !length $pkg_file || !-e $pkg_file ) {
                die "No repository exists for “$name” at “$repo_file”.";
            }

            if ( !$self->_handle_pkg_repo_file( $pkg_file, $name, $obsoletes ) ) {
                die "Failed to install repo from “$pkg_file”";
            }

            return 1;
        }
    }

    $self->_remove_obsoletes( $name, $obsoletes );

    my $target = "$TARGET_REPOS_DIR/$name.repo";

    # If the file exists and is the same do nothing
    # so that we can avoid calling the post install
    # task that clears the yum plugins cache when
    # there are no changes
    if ( -e $target ) {
        if ( keep_existing_yum_repos() ) {
            Cpanel::Debug::log_info("Install of yum repo: $name is already installed and requested to preserve it");
            return 1;
        }

        require Cpanel::LoadFile;
        my $content = $repo_contents ? $repo_contents : Cpanel::LoadFile::load($repo_file);
        if ( $content eq Cpanel::LoadFile::load($target) ) {
            Cpanel::Debug::log_info("Install of yum repo: $name is already installed and up to date");
            return 1;
        }
    }

    if ($repo_contents) {
        require Cpanel::FileUtils::Write;
        local $@;
        eval { Cpanel::FileUtils::Write::overwrite( $target, $repo_contents ) };
        if ($@) {
            die Cpanel::Exception::create(
                'IO::FileWriteError',
                [
                    'path'  => $target,
                    'error' => $@,
                ]
            );
        }
    }
    else {
        my ( $copy_ok, $copy_err ) = Cpanel::FileUtils::Copy::safecopy( $repo_file, $target );
        if ( !$copy_ok ) {
            die Cpanel::Exception::create(
                'IO::FileCopyError',
                [
                    'source'      => $repo_file,
                    'destination' => $target,
                    'error'       => $copy_err,
                ]
            );
        }
    }

    Cpanel::Debug::log_info("Install of yum repo: $name completed");
    $self->_set_post_installed_needed();
    return 1;
}

sub disable_repo_target ( $self, %OPTS ) {
    $OPTS{action} = '--disable';
    return $self->_do_repo_target(%OPTS);
}

sub enable_repo_target ( $self, %OPTS ) {
    $OPTS{action} = '--enable';
    return $self->_do_repo_target(%OPTS);
}

sub _do_repo_target {
    my ( $self, %OPTS ) = @_;

    die "The parameter target_name is required" if !$OPTS{'target_name'};

    my @extra = ('--dump');

    my $run = $self->_run_yum_config( $OPTS{'target_name'}, @extra );

    # If we have to enable the repo here this means
    # we have to call the post install task which
    # clears the yum mirror cache.  Since MySQL installs
    # will blindly enable the repo target we do not want
    # to have to pay for a yum mirror cache in the middle
    # of an install if the repo target is already enabled.
    #
    # To avoid this problem we return here if it is already
    # enabled.
    my $is_enabled = $run->stdout() =~ m{^[ \t]*enabled[ \t]*=[ \t]*(?:1|[tT]rue)}m;

    if ( $OPTS{'action'} eq '--enable' && $is_enabled ) {
        Cpanel::Debug::log_info("Enable of yum target: $OPTS{'target_name'} is already enabled");
        return 1;
    }
    elsif ( $OPTS{'action'} eq '--disable' && !$is_enabled ) {
        Cpanel::Debug::log_info("Disable of yum target: $OPTS{'target_name'} is already disabled or does not exist.");
        return 1;
    }

    $self->_run_yum_config( $OPTS{'target_name'}, $OPTS{'action'} );

    my $action = $OPTS{'action'} eq '--enable' ? 'Enable' : 'Disable';
    Cpanel::Debug::log_info("$action of yum target: $OPTS{'target_name'} completed");
    $self->_set_post_installed_needed();
    return 1;
}

sub _run_yum_config ( $self, $repo, @args ) {

    my $yum_config = Cpanel::Binaries::path('yum-config-manager');
    die "Failed to find the yum-config-manager binary." if !$yum_config;

    # dnf is case sensitive on repo targets, while yum is not.
    # It is common for mysql repos to be named "Mysql80-community" or
    # "mysql80-community". Lowercase the target and try again before
    # we give up.
    #
    my @targets = ( $repo, lc($repo) );

    my $run;
    for my $target (@targets) {
        local $@;
        $run = Cpanel::SafeRun::Object->new(
            'program' => $yum_config,
            'args'    => [ '--config', $self->{'yum.conf'}, @args, $target ],
        );

        $run->CHILD_ERROR() ? next : last;
    }

    if ( $run->CHILD_ERROR() ) {
        my $message = "Failed to run $yum_config on the repository named $repo: ";
        my $out     = $run->stdout() . $run->stderr();

        # We want to ignore this error. It is only emitted as an error on dnf systems.
        return $run if $out =~ m/No matching repo to modify/;
        die $message . $out;
    }

    return $run;
}

sub keep_existing_yum_repos {
    return -e '/var/cpanel/keep_existing_yum_repos';
}

sub _remove_obsoletes ( $self, $name, $obsoletes ) {

    return unless $obsoletes;

    my @repos_to_disable = $self->_get_repo_matching($obsoletes);
    foreach my $repo (@repos_to_disable) {
        next if $repo eq $name;
        $self->_disable_repo($repo);
    }

    return 1;
}

# _handle_pkg_repo_file:
# Returns 2 if the repo is already installed
# Returns 1 on successful install of the repo
# Returns 0 on failure
#
sub _handle_pkg_repo_file ( $self, $pkg_file, $name = undef, $obsoletes = undef ) {

    return 2 if $self->_pkg_repo_is_already_installed($pkg_file);

    # only remove obsoletes after checking if the package is installed...
    #   otherwise we remove ourself
    $self->_remove_obsoletes( $name, $obsoletes );

    Cpanel::Pkgr::install_or_upgrade_from_file($pkg_file);
    my @list_files = Cpanel::Pkgr::list_files_from_package_path($pkg_file);
    return 0 if !@list_files;

    # XXX TODO tag: ubuntu-followup
    my @gpg_files = grep { Cpanel::Autowarn::exists($_) }    #
      grep { m{^/etc/pki/rpm-gpg/} } @list_files;
    return 1 unless scalar @gpg_files;

    return Cpanel::Pkgr::add_repo_keys(@gpg_files);
}

sub _pkg_repo_is_already_installed ( $self, $pkg_file ) {

    # This is only valid for one link and it must point to the actual file name
    # See HB-6357
    if ( my $dest = readlink($pkg_file) ) {
        $pkg_file = $dest;
    }
    elsif ( !defined $dest && !$!{'EINVAL'} ) {
        die Cpanel::Exception::create( 'IO::SymlinkReadError', [ error => $!, path => $pkg_file ] );
    }
    my $filename = ( split( m{\/}, $pkg_file ) )[-1];

    # XXX TODO tag: ubuntu-followup
    require Cpanel::RpmUtils::Parse;

    my $name_version_parse = Cpanel::RpmUtils::Parse::parse_rpm_arch($filename);
    my $pkgname            = $name_version_parse->{'name'};
    my $pkgversion_release = $name_version_parse->{'version'} . '-' . $name_version_parse->{'release'};
    local $@;
    my $installed_version = Cpanel::Pkgr::get_package_version($pkgname);

    return 0 unless defined $installed_version;

    # consider it installed if the installed version is greater than the current one (repo was updated)
    return 1 if Cpanel::Version::Compare::Package::version_cmp( $installed_version, $pkgversion_release ) >= 0;

    return 0;
}

sub _find_pkg {
    my ( $self, $name ) = @_;

    my $repo_dir = $self->_get_pkg_repo_dir($name);
    return if !-d $repo_dir;

    # Only get pkgs that have the repo name in it, then get the newest one via a schwartzian transform
    # XXX TODO tag: ubuntu-followup
    my @files = map { $_->[0] } sort { $b->[1] <=> $a->[1] } map { [ $_, ( stat "$repo_dir/$_" )[9] ] } grep { substr( $_, -4 ) eq '.rpm' && /$name/i } @{ Cpanel::FileUtils::Dir::get_directory_nodes($repo_dir) };
    return if !@files;
    return "$repo_dir/$files[0]";
}

sub _get_pkg_repo_dir {
    my ( $self, $name ) = @_;

    return "$REPOS_DIR/" . Cpanel::OS::distro() . '/' . Cpanel::OS::major() . "/$name/" . Cpanel::OS::arch();    ## no critic(Cpanel::CpanelOS) repo dir template
}

sub _disable_repo {
    my ( $self, $repo ) = @_;

    local $!;
    my $repo_file = "$TARGET_REPOS_DIR/$repo";

    my $trans = Cpanel::Transaction::File::Raw->new(
        path        => $repo_file,
        permissions => 0644,
    );

    if ( ${ $trans->get_data() } !~ m{\n[ \t]*enabled[ \t]*=[ \t]*0}s ) {
        if ( !$trans->length() || $trans->substr(-1) !~ m{\n$} ) {
            $trans->substr( $trans->length(), 0, "\n" );
        }
        $trans->substr( $trans->length(), 0, "enabled=0\n" );

        my ( $ok, $err ) = $trans->save_and_close();
        die Cpanel::Exception->create_raw($err) if !$ok;
    }
    else {
        my ( $ok, $err ) = $trans->abort();
        die Cpanel::Exception->create_raw($err) if !$ok;
    }

    return 1;
}

sub _get_repo_matching {
    my ( $self, $regex ) = @_;

    opendir( my $repo_dh, $TARGET_REPOS_DIR ) || die Cpanel::Exception::create( 'IO::DirectoryOpenError', [ path => $TARGET_REPOS_DIR, error => $! ] );
    local $!;

    my @matches = grep { $_ =~ $regex } readdir($repo_dh);

    if ($!) {
        die Cpanel::Exception::create( 'IO::DirectoryReadError', [ path => $TARGET_REPOS_DIR, error => $! ] );
    }

    return @matches;

}

sub _set_post_installed_needed {
    my ($self) = @_;

    # we set it to the pid so forking children do not run it on DESTROY
    $self->{'needs_post_install'} = $$;
    return 1;
}

sub DESTROY {
    my ($self) = @_;

    # Only if needs_post_install and the pid matches
    # the current process do we clear the cache so we avoid
    # doing this if not needed or in forked children
    return if !$self->{'needs_post_install'} || $self->{'needs_post_install'} != $$;

    # Clear the fastestmirror plugin cache
    Cpanel::Repos::Utils::post_install();
    return 1;
}
1;
