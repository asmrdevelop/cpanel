package Cpanel::SysPkgs::APT;

# cpanel - Cpanel/SysPkgs/APT.pm                   Copyright 2022 cPanel, L.L.C.
#                                                           All rights reserved.
# copyright@cpanel.net                                         http://cpanel.net
# This code is subject to the cPanel license. Unauthorized copying is prohibited

use cPstrict;

# NB: For now this module can’t have signatures because
# of the need for inclusion into updatenow.

use Try::Tiny;

use Cpanel::Binaries::Debian::Apt                      ();
use Cpanel::Binaries::Debian::AptCache                 ();
use Cpanel::Binaries::Debian::AptGet                   ();
use Cpanel::Binaries::Debian::AptMark                  ();
use Cpanel::Binaries::Gpg                              ();
use Cpanel::CPAN::IO::Callback::Write                  ();
use Cpanel::Debug                                      ();
use Cpanel::Exception                                  ();
use Cpanel::FileUtils::Write                           ();
use Cpanel::FileUtils::Copy                            ();
use Cpanel::Finally                                    ();
use Cpanel::OS                                         ();
use Cpanel::Parser::Callback                           ();
use Cpanel::Set                                        ();
use Cpanel::SysPkgs::APT::Preferences::ExcludePackages ();
use Cpanel::TimeHiRes                                  ();
use Cpanel::Validate::FilesystemNodeName               ();

use IO::Handle;

use parent 'Cpanel::SysPkgs::Base';

use constant _ENOENT => 2;
use constant GPG_DIR => '/etc/apt/trusted.gpg.d';    # /usr/share/keyrings instead (can only be .gpg?)?

our $APT_CONF      = '/etc/apt/apt.conf.d/01-cpanel';    # TODO: temporary guesstimate of what apt conf name we might use, if anything
our $VERSION       = '1.0';                              # TODO: This only appears to be used in a log message in one place, useless ?
our $FORCE_DRY_RUN = 0;                                  # For testing

=encoding utf-8

=head1 NAME

Cpanel::SysPkgs::APT;

=head1 SYNOPSIS

  use Cpanel::SysPkgs ();

  my $sysp = Cpanel::SysPkgs->new();

  $sysp->install(
        packages        => \@install_packages,
        disable_plugins => ['apluginidontlike'],
  );

=head1 DESCRIPTION

Wrapper around apt binary.

=head1 CONSTRUCTORS

=head2 new(ARGS)

Creates a Cpanel::SysPkgs::APT object used access the system 'apt-get' command

Notes:

The odd instantiation logic is because this function usually
receives a Cpanel::SysPkgs object and converts it to a
Cpanel::SysPkgs::APT object.

=head3 ARGUMENTS

Required HASHREF with the following properties:

=over

=item  output_obj

Optional: A Cpanel::Output object
If passed, all output will be sent to this object.

=item logger

Optional: A Cpanel::Update::Logger object
If passed and no output_obj has been passed,
all output will be sent to this object.

=item exclude_options

Optional: A hashref of apt excludes to enable:
Example:
 {
    'kernel'      => 1,
    'ruby'        => 1,
    'bind-chroot' => 1,
 }

=back

=head3 RETURNS

A Cpanel::SysPkgs::APT object

=cut

sub new ( $class, $self ) {

    $self = $class->SUPER::new($self);
    bless $self, $class;

    # TODO: See comment for parse_pkgmgr_conf(), as there is no "single" apt config file
    $self->{'apt.conf'} = $APT_CONF;

    $self->{'VERSION'} = $VERSION;

    return $self;
}

=head1 METHODS

=cut

#----------------------------------------------------------------------

sub haspkg {
    return;
}

# See install for a list of available options.
sub update ( $self, %opts ) {
    ref $self or Carp::croak("update() must be called as a method.");

    # CPANEL-38453: `apt install` can't be usefully called when giving it no
    # packages, so convert calls without a 'packages' or 'pkglist' key into an
    # `apt upgrade` invocation. If someone decides to shove an empty arrayref
    # into one of those two places, assume that they know what they're doing.
    my @command;
    if ( !$opts{'packages'} && !$opts{'pkglist'} ) {

        # If upgrading the kernel is allowed, this needs to be passed to
        # apt-get in order to allow it to install the new packages associated
        # with the new kernel version:
        @command = $self->should_block_kernel_updates ? ('upgrade') : ( 'upgrade', '--with-new-pkgs' );
    }
    else {
        @command = ( 'install', '--only-upgrade' );
    }

    return $self->install( %opts, 'command' => \@command, is_update => 1 );
}

# See install for a list of available options.
sub ensure ( $self, @args ) {
    ref $self or Carp::croak("ensure() must be called as a method.");

    return $self->install(@args);
}

# See install for a list of available options.
sub reinstall ( $self, @args ) {

    ref $self or Carp::croak("reinstall() must be called as a method.");

    return $self->install( @args, 'command' => [ 'reinstall', '-yf' ] );
}

# See _call_apt for a list of available options.

=head2 $self->install( %opts )

Install some packages.

Note: by default block/mask kernel updates

=cut

sub install ( $self, %opts ) {

    ref $self or Carp::croak("install() must be called as a method.");

    my ( $ret, $err );
    try {
        $ret = $self->install_packages(%opts);
    }
    catch {
        $err = $_;
    };

    if ($err) {
        my $error_as_string = Cpanel::Exception::get_string($err);
        $self->error($error_as_string);
        return 0;
    }

    return $ret;
}

# See _call_apt for a list of available options.
sub uninstall_packages ( $self, %opts ) {

    $opts{'extra_args'} = '-yf';

    # Run purge, as that mimicks what EA4 packages specify in specfile,
    # namely that the config files *should* be removed on uninstall.
    # Since we can't do that with .deb files, we have to compromise here
    # and do it blithely.
    return $self->_call_apt( %opts, 'command' => ['purge'] );
}

# See _call_apt for a list of available options.
sub install_packages ( $self, %opts ) {

    $opts{'extra_args'} = '-yf';

    return $self->_call_apt(%opts);
}

sub download_packages ( $self, %opts ) {

    $opts{'download_only'} = 1;
    $opts{'extra_args'}    = '-y';

    return $self->_call_apt( %opts, 'command' => ['install'] );
}

sub clean ($self) {
    return $self->_call_apt( 'command' => ['clean'] );
}

sub check_and_set_exclude_rules ($self) {

    # do not provide the ability to disable that setup
    #   the rules below also contain the blocker to Ubuntu 20.04 blocking base-files updates
    # return 1 unless $self->check_is_enabled;

    $self->validate_excludes();

    # package the customer can on demand exclude or not
    my $exclude_customized = {
        kernel => $self->exclude_kernel(),

        # perl & ruby do not make sense for ubuntu (we never blocked/corrupted these packages)
    };

    my $excludes      = $self->{'excludes'};
    my @current_rules = $self->list_exclude_rules;
    my @wanted_rules;

    foreach my $exclude_name ( sort keys $excludes->%* ) {

        # If there is an entry in $exclude_customized, and it is false, the rules are not wanted:
        next if exists $exclude_customized->{$exclude_name} && !$exclude_customized->{$exclude_name};

        my @rules = split( /\s+/, $excludes->{$exclude_name} );
        push @wanted_rules, @rules;
    }

    # Add rules that are not present but wanted, and drop rules that are present but not wanted:
    my @to_add  = Cpanel::Set::difference( \@wanted_rules,  \@current_rules );
    my @to_drop = Cpanel::Set::difference( \@current_rules, \@wanted_rules );

    $self->drop_exclude_rule_for_package($_) for @to_drop;
    $self->add_exclude_rule_for_package($_)  for @to_add;

    return 1;
}

sub checkdb {
    return 1;
}

sub checkconfig ($self) {
    ref $self or Carp::croak("checkconfig() must be called as a method.");

    my $res       = $self->_apt->cmd( info => 'libc6' );
    my $glibcinfo = $res->{output} // '';

    if ( $glibcinfo !~ m/^Package: libc6/m || $glibcinfo =~ m/No packages found/ ) {
        return 0;
    }

    return 1;
}

###########################################################################
#
# Method:
#   verify_package_version_is_available
#
# Description:
#   Verifies to see if specific version of a package is installable via apt
#
# Parameters:
#   'package'                 - The name of the package to check
#   'version'                 - The LEFT PART of the acceptable version.
#                               For example, if you put in “10.0”, this
#                               will match “10.0”, “10.01”, “10.0.0”,
#                               “10.0.99”, etc.
#
# Returns 1, or throws an exception.
#

sub verify_package_version_is_available ( $self, %opts ) {

    die Cpanel::Exception::create( 'MissingParameter', [ 'name' => 'package' ] ) if !defined $opts{'package'};
    die Cpanel::Exception::create( 'MissingParameter', [ 'name' => 'version' ] ) if !defined $opts{'version'};

    my $details = $self->_apt_cache->show_all_versions( $opts{'package'} ) // [];
    foreach my $record (@$details) {
        return 1 if $record->{'version'} =~ m/^([0-9]+:)?\Q$opts{'version'}\E/;
    }
    die "The package “$opts{'package'}” with version “$opts{'version'}” is not available via apt";
}

###########################################################################
#
# Method:
#   can_packages_be_installed
#
# Description:
#   Calls the system 'apt' command via _exec_apt
#
# Parameters:
#   'packages'                - An arrayref of packages for apt
#                               Example: ['MariaDB-server', 'MariaDB-client']
#   'exclude_packages'        - Optional: An arrayref of packages for apt to exclude
#                               Example: ['MariaDB-compat']
#   'ignore_conflict_packages_regexp'
#                             - Optional: A regex of package names to be used to ignore
#                               some package conflicts
#
# Returns:
#   true or an exception
#
sub can_packages_be_installed ( $self, %opts ) {

    if ( !defined $opts{'packages'} ) {
        die Cpanel::Exception::create( 'MissingParameter', [ 'name' => 'packages' ] );
    }

    my $ignore_conflict_packages_regexp = $opts{'ignore_conflict_packages_regexp'};

    my $apt_stderr = '';
    my $err;

    try {
        $self->_call_apt(
            %opts,
            'command'         => ['install'],
            'dry_run'         => 1,
            'stderr_callback' => sub {
                my ($data) = @_;
                $apt_stderr .= $data;
                return 1;
            }
        );
    }
    catch {
        $err = $_;
    };

    if ($err) {
        if (   UNIVERSAL::isa( $err, 'Cpanel::Exception::ProcessFailed' )
            && $ignore_conflict_packages_regexp
            && $self->_should_ignore_package_conflicts_in_apt_error_output( $apt_stderr, $ignore_conflict_packages_regexp ) ) {
            return 1;
        }

        $self->error( Cpanel::Exception::get_string($err) );
        return 0;
    }

    # Some errors (like a mirror being down) do not cause apt to end up in an error state during a dry run.
    # Parse through the stderr output here to check for certain ones, if a method to do so is passed in.
    return 0
      if ref( $opts{'check_apt_preinstall_stderr'} ) eq 'CODE'
      && $opts{'check_apt_preinstall_stderr'}->($apt_stderr);

    return 1;
}

=head2 add_repo_key(key)

=head3 ARGUMENTS

=over

=item key - String

Path to the GPG Key to import

=back

=head3 RETURNS

1 if installed, 0 if not installed.

=cut

sub add_repo_key ( $self, $key ) {

    # in 22.04 apt-key is deprecated in favor of this
    return 1 if Cpanel::FileUtils::Copy::safecopy( $key, GPG_DIR );

    $self->warn("Could not import the public key '$key'");
    return 0;
}

sub add_repo_key_by_id ( $self, $key_id ) {

    # In 20.02 `apt-key adv` is deprecated.
    # So this needs to get $key_id into a file in GPG_DIR w/out apt-key which is:
    #    1. gpg --recv-keys --keyserver keyserver.ubuntu.com $key_id
    #    2. gpg --export $key_id > GPG_DIR . "/keyserver.ubuntu.com-$key_id.gpg"
    my $gpg = Cpanel::Binaries::Gpg->new();

    # Step 1
    my $answer = $gpg->cmd( qw(--recv-keys --keyserver keyserver.ubuntu.com), $key_id );
    if ( $answer->{status} != 0 ) {
        $self->warn("gpg could not recv-keys “$key_id” from keyserver.ubuntu.com");
        return 0;
    }

    # Step 2
    $answer = $gpg->cmd( "--export" => $key_id );
    if ( $answer->{status} != 0 ) {
        $self->warn("gpg could not export “$key_id”");
        return 0;
    }

    my $file = GPG_DIR . "/keyserver.ubuntu.com-$key_id.gpg";

    # overwrite()’s default of 0600 causes this during normal transactions (i.e. not just apt-key calls):
    #    W: … keyring /etc/apt/trusted.gpg.d/keyserver.ubuntu.com-$key_id.gpg are
    #    ignored as the file is not readable by user '_apt' executing apt-key.
    if ( !Cpanel::FileUtils::Write::overwrite( $file, $answer->{output}, 0644 ) ) {
        $self->warn("Could not write “$file”: $!");
        return 0;
    }

    return 1;
}

sub _apt_mark ($self) {
    return $self->{_apt_mark} //= Cpanel::Binaries::Debian::AptMark->new();
}

sub _apt_cache ($self) {
    return $self->{_apt_cache} //= Cpanel::Binaries::Debian::AptCache->new();
}

sub _apt ($self) {
    return $self->{_apt} //= Cpanel::Binaries::Debian::Apt->new();
}

sub _apt_pref_exclude_packages ($self) {
    return $self->{_apt_pref_exclude_packages} //= Cpanel::SysPkgs::APT::Preferences::ExcludePackages->new();
}

# for now use apt-mark to hold/unhold package
#   there is more than one way to block pacages:
#       view https://www.tecmint.com/disable-lock-blacklist-package-updates-ubuntu-debian-apt/

=head2 $self->has_exclude_rule_for_package( $pkg )

Check if the package an exclude rule to block future updates.
Returns a boolean:
- true when an exclude rule exist for the package
- false when no exclude rules exist for the package

=cut

sub has_exclude_rule_for_package ( $self, $pkg ) {

    # check hold packages (note: only work for installed packages)
    my $exclude_list = $self->_apt_mark->showhold();

    my $has_exclude = grep { $_ eq $pkg } $exclude_list->@*;
    return 1 if $has_exclude;

    return $self->_apt_pref_exclude_packages->has_rule_for_package($pkg);
}

=head2 $self->drop_exclude_rule_for_package( $pkg )

Drop an exclude rule for the package.
Allowring future package updates.

Returns a boolean:
- true when the exclude was removed (or do not exist)
- false when failed to remove the exclude rule

=cut

sub drop_exclude_rule_for_package ( $self, $pkg ) {

    return unless $self->has_exclude_rule_for_package($pkg);

    # remove the hold if set
    $self->_apt_mark->unhold($pkg);

    return $self->_apt_pref_exclude_packages->remove($pkg);
}

=head2 $self->add_exclude_rule_for_package( $pkg )

Add an exclude rule for the package.
Allowring future package updates.

Returns a boolean:
- true when the exclude rule was added (or already exist)
- false when failed to remove the exclude rule

=cut

sub add_exclude_rule_for_package ( $self, $pkg ) {

    return if $self->has_exclude_rule_for_package($pkg);

    return $self->_apt_pref_exclude_packages->add($pkg);
}

=head2 $self->list_exclude_rules()

Return the list of current exclude rules.

=cut

sub list_exclude_rules ($self) {
    return keys $self->_apt_pref_exclude_packages->content->%*;
}

##################################################################################
#
#
# What follows is not a part of the SysPkgs interface and is for internal use only.
#
#
##################################################################################

sub reinit {
    my ( $self, $exclude_options ) = @_;
    $self->{'excludes'}        = $self->default_exclude_list();
    $self->{'exclude_options'} = $exclude_options || die;
    return;
}

# TODO: If we start needing to add ppa:// sources, we might need to parse
# /etc/apt/sources.list and everything in /etc/apt/sources.list.d/ .
# Something like:
#    grep -r --include '*.list' '^deb ' /etc/apt/sources.list /etc/apt/sources.list.d/
#
# There is also the package libapt-pkg-perl, which provides us with an interface to the apt system
#    perl -MAptPkg::Cache -MData::Dumper -E'say Dumper [AptPkg::Cache->new->files()]'
#
# NOTE: Currently this is only called via build-tools/sysup in a very centos-specific context (setting up epel),
#       so we no-op it for now

sub repolist ( $self, %opts ) {

    return 1;
}

###########################################################################
#
# Method:
#   _call_apt
#
# Description:
#   Calls the system 'apt' command via _exec_apt
#
# Parameters:
#   'packages'                - Optional: An arrayref of packages for apt
#                               Example: ['MariaDB-server', 'MariaDB-client']
#   'exclude_packages'        - Optional: An arrayref of packages for apt to exclude
#                               Example: ['MariaDB-compat']
#   'command'                 - Optional: An arrayref representing the apt command to run
#                               Default: ['install]
#                               Example: ['update']
#   'dry_run'                 - Optional: A boolean that will cause apt to only
#                               test to see if the transaction will succeed
#   'stdout_callback'         - Optional: A coderef that will receive everything apt writes
#                               to stdout
#   'stderr_callback'         - Optional: A coderef that will receive everything apt writes
#                               to stderr
#
# Returns:
#   true or an exception
#

my $updated;

sub _call_apt ( $self, %opts ) {

    my $packages         = $opts{'packages'}         || $opts{'pkglist'} || [];    # pkglist is for legacy calls
    my $exclude_packages = $opts{'exclude_packages'} || [];
    my $command          = $opts{'command'}          || ['install'];
    my $download_only    = $opts{'download_only'} ? 1 : 0;
    my $download_dir     = $opts{'download_dir'};
    my $dry_run          = $opts{'dry_run'} ? 1 : 0;
    my $disable_plugins  = $opts{'disable_plugins'} || [];
    my $is_base_install  = defined( $ENV{'CPANEL_BASE_INSTALL'} );
    my $extra_args       = $opts{'extra_args'} || '';

    my @args = $self->_base_apt_args();
    push @args, $extra_args       if $extra_args;
    push @args, '--assume-no'     if ( $dry_run || $FORCE_DRY_RUN );
    push @args, '--download-only' if $download_only;

    # This -o option overrides the default setting for apt and will download the .deb for packages not already installed.
    # Looks like we can call 'reinstall' and it will download for existing packages as well
    push @args, ( '-o', 'Dir::Cache=' . "$download_dir", '-o', 'Dir::Cache::archives=' . "$download_dir" ) if $download_dir;

    # Don't update more than once in same execution context
    if ( scalar( @{$command} ) && $command->[0] && grep { $command->[0] eq $_ } qw{install upgrade} ) {
        $updated = $self->_exec_apt( '_args' => ['update'] ) if !$updated;
        push @args, qw(
          -o Acquire::Retries=3
          -o Dpkg::Options::=--force-confdef
          -o Dpkg::Options::=--force-confold
        );
    }

    foreach my $package ( @{$exclude_packages} ) {
        Cpanel::Validate::FilesystemNodeName::validate_or_die($package);

        # TODO: not seeing obvious cli arg for this, might need to use `apt-mark hold` before running and removing it after
        # push @args, ( '--exclude', $package );
    }

    push @args, @{$command};
    foreach my $package ( @{$packages} ) {
        Cpanel::Validate::FilesystemNodeName::validate_or_die($package);
        push @args, $package;
    }

    my $restore_excludes_guard = $self->setup_excludes_file( $opts{'is_update'} );
    return $self->_exec_apt( %opts, '_args' => \@args );
}

sub setup_excludes_file ( $self, $is_update ) {

    $self->check_and_set_exclude_rules;

    my $kernel_rules    = Cpanel::OS::system_exclude_rules()->{'kernel'} or die;
    my @kernel_packages = split( /\s+/, $kernel_rules );

    if ( $is_update && $self->should_block_kernel_updates ) {
        my $f = Cpanel::Finally->new(
            sub {
                $self->out( '# Restoring updates for kernel packages: ' . join( ', ', @kernel_packages ) );
                $self->drop_exclude_rule_for_package($_) for @kernel_packages;
            }
        );
        $self->out( '# Excluding updates for kernel packages: ' . join( ', ', @kernel_packages ) );
        $self->add_exclude_rule_for_package($_) for @kernel_packages;
        return $f;
    }

    # Assure kernel excludes are not present since we're not updating.
    $self->drop_exclude_rule_for_package($_) for @kernel_packages;

    return;
}

sub _exec_apt ( $self, %opts ) {

    my $stdout_callback    = $opts{'stdout_callback'};
    my $stderr_callback    = $opts{'stderr_callback'};
    my $handle_child_error = $opts{'handle_child_error'} || \&_die_child_error;

    # Set ENV with local to avoid
    # having to use before_exec because
    # it prevents FastSpawn
    local @ENV{qw{LANG LANGUAGE LC_ALL LC_MESSAGES LC_CTYPE}} = qw{C C C C C};
    local @ENV{qw{DEBIAN_FRONTEND DEBIAN_PRIORITY}}           = qw{noninteractive critical};

    my $start_time = Cpanel::TimeHiRes::time();
    my $stderr     = '';

    # NOTE: Cpanel::Parser::Callback expects the callback(s) to return true when the callback is successful so it can update its data buffer appropriately.
    # Not all output objects that may be used here return true from the output call, so explicitly returning true after output allows the parser work correctly in all cases.
    my $callback_obj = Cpanel::Parser::Callback->new( 'callback' => sub { $self->out(@_); return 1; } );

    # stderr should not call ->error since it will trigger updatenow to think the update
    # has failed.
    my $callback_err_obj = Cpanel::Parser::Callback->new( 'callback' => sub { $self->warn(@_); return 1; } );

    $self->{'logger'}->info("Starting apt execution “@{$opts{'_args'}}”.") if $self->{'logger'};
    Cpanel::Debug::log_info("Starting apt execution “@{$opts{'_args'}}”.");

    my $apt_obj = Cpanel::Binaries::Debian::AptGet->new();
    my $result  = $apt_obj->run(
        'args'   => $opts{'_args'},
        'stdin'  => $opts{'stdin'},
        'stdout' => Cpanel::CPAN::IO::Callback::Write->new(
            sub {
                my ($data) = @_;
                $data .= "\n" if substr( $data, -1 ) ne "\n";    # ensure a newline here so we don't make Cpanel::Parser::Line’s buffer keep concatenating lines without a newline and repeating them over and over and …

                # remove backspace characters & co when running transaction
                if ( $data =~ m{\w+\s*:\s.*\d+/\d+}m ) {
                    $data =~ s/[\x00-\x0A]+//go;
                    $data .= "\n";                               # re-add the newline we just stripped out
                }

                if ($stdout_callback) {
                    $stdout_callback->($data);
                }
                else {
                    $callback_obj->process_data($data);
                }
                return;
            }
        ),
        'stderr' => Cpanel::CPAN::IO::Callback::Write->new(
            sub {
                my ($data) = @_;
                $data .= "\n" if substr( $data, -1 ) ne "\n";    # ensure a newline here so we don't make Cpanel::Parser::Line’s buffer keep concatenating lines without a newline and repeating them over and over and …

                $stderr .= $data;
                if ($stderr_callback) {
                    $stderr_callback->($data);
                }
                else {
                    $callback_err_obj->process_data($data);
                }
                return;
            }
        ),
        'timeout' => 7200,    # 2 hour timeout
    );

    $callback_obj->finish();
    $callback_err_obj->finish();
    my $end_time  = Cpanel::TimeHiRes::time();
    my $exec_time = sprintf( "%.3f", ( $end_time - $start_time ) );
    $self->{'logger'}->info("Completed apt execution “@{$opts{'_args'}}”: in $exec_time second(s).") if $self->{'logger'};
    Cpanel::Debug::log_info("Completed apt execution “@{$opts{'_args'}}”: in $exec_time second(s).");

    # Would be nice to put the various incantations of options, like --assumeno / --assume-no, somewhere we can reference them
    if ( $result->CHILD_ERROR() && !grep( /^(?:--assumeno|--assume-no)$/, @{ $opts{'_args'} } ) ) {
        return $handle_child_error->( $result, $stderr, %opts );
    }

    return 1;
}

sub _base_apt_args ($self) {

    # SysPkgs should always run apt with these arguments.
    # Currently there are no known options we always need that every apt sub command allows, things like -y need to be explicitly used
    # for install, but can not be used for list, for example.
    return;
}

sub _die_child_error ( $result, $stderr, %opts ) {

    # Skip Saferun failure if this is our stderr message
    if ( $stderr =~ m/does not have a stable CLI interface/ ) {
        return;
    }
    $result->die_if_error();

    return;    ## Just to satisfy cplint; we never actually get here.
}

sub _should_ignore_package_conflicts_in_apt_error_output ( $self, $apt_stderr, $ignore_conflict_packages_regexp ) {    ## no critic qw(Subroutines::ProhibitManyArgs)

    my @output = split( m{\n}, $apt_stderr );

    my ( $has_error_summary, $in_error_summary, $has_transaction_check_error, $in_transaction_check_error );

    # TODO: none of this is going to be valid for apt, need to figure out new error messages
    foreach my $line (@output) {
        if ( $line =~ m{^---} ) {
            next;
        }
        elsif ( $line =~ m/^[ \t]*Error Summary/i ) {
            $has_error_summary = $in_error_summary = 1;
        }
        elsif ( $line =~ m/^[ \t]*Transaction Check Error/i ) {
            $has_transaction_check_error = $in_transaction_check_error = 1;
        }
        elsif ( $line =~ m{^\s*$} ) {
            $in_error_summary = $in_transaction_check_error = 0;
        }
        elsif ($in_transaction_check_error) {
            if ( $line =~ m{conflicts with.*?package $ignore_conflict_packages_regexp} ) {

                #OK
                next;
            }
            else {
                return 0;
            }
        }
        elsif ($in_error_summary) {
            return 0;
        }
    }

    # We saw Transaction Check Error and did not trigger on any of the error lines
    if ($has_transaction_check_error) {
        $self->out("All Package conflicts matched allowed.");
        return 1;
    }

    return 0;
}

# TODO: There is currently no known plugins type thing needed for apt
sub ensure_plugins_turned_on {
    return 1;
}

# Search package by name, return the most recent version available, or all matches if $opts{'all'} is true
sub search ( $self, %opts ) {
    return $self->_search(%opts);
}

sub search_installed ( $self, %opts ) {
    my $result = $self->_search(%opts);
    return unless ref $result;

    return [ grep { $_->{installed} && $_->{installed} =~ qr{installed} } $result->@* ];
}

sub _search ( $self, %opts ) {

    my $bin = $self->_apt;
    my $got = $bin->cmd( 'search', $opts{'pattern'} );

    return if $got->{'status'};    # Non-zero exit code leads to no result.

    # Winnow results till it is what we want
    my $re = qr/$opts{'pattern'}/;

    my @lines = grep { $_ && $_ =~ $re } map { split( m/\n/, $_ ) } $got->{'output'};

    # So, I know this regexp is not 100% compliant with the rather... lax
    # naming rules for debian packages. Until such time as we get something
    # like Regexp::Common::debian in here I'm leery of going too crazy with
    # our regexes here. Anways, strings we get here look something like:
    # linux-image-5.8.0-55-lowlatency/focal-updates,focal-security 5.8.0-55.62~20.04.1 amd64
    # linux-image-5.8.0-53-generic/focal-updates,focal-security 5.8.0-53.60~20.04.1 amd64
    # linux-image-5.4.0-81-generic/focal-updates,focal-security,now 5.4.0-81.91 amd64 [installed,automatic]
    #          1            2          3                            4        5                    6
    $re = qr{^([a-zA-Z-]+)-([0-9.-]+)-([a-zA-Z]+)[/a-zA-Z,-]+\s\2\.(\d+).*\s([a-zA-Z0-9]+)\s{0,1}(\[.+\])?$}x;
    my @found = map {
        my $str = $_;
        $str =~ $re;
        {
            name      => $1,
            version   => $2,
            type      => $3,
            release   => $4,
            arch      => $5,
            installed => $6,
            package   => "$1-$2-$3"
        }
    } @lines;

    if (@found) {
        if ( $opts{'all'} ) {
            return \@found;
        }
        else {
            # We want to organize this by version if at all possible
            my @sorted = sort { $a->{'release'} <=> $b->{'release'} } @found;
            return [ ( $sorted[-1] ) ];
        }
    }
    else {
        return;
    }
}

sub add_repo ( $self, %opts ) {

    my ( $remote_path, $real_path ) = @opts{qw{remote_path local_path}};

    # mirror() chokes if $real_path exists, so let’s help that not to happen.
    # It could still happen if, e.g., $real_path gets created between this
    # rename() and the mirror() below, but that should be rare.
    my $renamed_to = $real_path . substr( rand, 1 ) . '-' . ( localtime =~ tr< ><_>r );

    if ( open my $rfh, '<', $real_path ) {
        require File::Copy;
        if ( File::Copy::copy( $rfh => $renamed_to ) ) {
            CORE::warn "“$real_path” is about to be rewritten. The old file has been copied to “$renamed_to”.\n";
        }
        else {
            die "The system failed to copy “$real_path” to “$renamed_to” ($!).\n";
        }
    }
    elsif ( $! != _ENOENT() ) {
        CORE::warn "open(< $real_path): $!";
    }

    # NOTE - If you change this to a use statement, run:
    # t/scripts-restartsrv_spamd_check-dependencies.t
    require Cpanel::HTTP::Tiny::FastSSLVerify;
    my $http = Cpanel::HTTP::Tiny::FastSSLVerify->new();
    my $ret  = $http->mirror( $remote_path, $real_path );

    return $ret;
}

sub reinstall_packages {
    die "Unimplemented!";
}

=head2 list_available(%opts)

List packages available from the upstream distro

    Cpanel::SysPkgs->new()->list_available( disable_epel => 1 )

=cut

sub list_available ( $self, %opts ) {
    my @args;

    my $pattern = $opts{'search_pattern'} // '.';    # This should be safe from a shell injection.

    my $apt_obj = $self->_apt;
    my $result  = $apt_obj->cmd( 'search', $pattern );
    $result->{'status'} == 0 or return {};           # Error should not happen.
    my @lines = split "\n", $result->{'output'};
    delete $result->{'output'};                      # Save some memory.

    my @packages;
    my $p = 0;
    while ( scalar @lines ) {
        my $line = shift @lines;

        # This will also strip off the noise at the header.
        $line =~ m{^(\S[^/]*)/(\S+)\s+(\S+)\s+(\S+)\s*$} or next;    # 0ad/focal 0.0.23.1-4ubuntu3 amd64
        my ( $package_name, $repo, $version, $arch ) = ( $1, $2, $3, $4 );

        my $description = '';
        while ( $lines[0] && $lines[0] =~ /^  (\S.+)/ ) {
            $description .= "$1\n";
            shift @lines;
        }
        chomp $description;

        next if $opts{'disable_ea4'} && $package_name =~ m/^ea-/i;

        push @packages, {
            'name'          => $package_name,            #
            'version'       => $version,                 #
            'repo'          => $repo,                    #
            'arch'          => $arch,                    #
            'name_and_arch' => "$package_name:$arch",    #
            'description'   => $description
        };
    }

    return \@packages;
}

# This is a rhel thing so no.
sub is_epel_installed {
    return 0;
}

# This is a rhel thing so no.
sub is_epel_enabled {
    return 0;
}

1;
