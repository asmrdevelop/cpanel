package Cpanel::SysPkgs::YUM;

# cpanel - Cpanel/SysPkgs/YUM.pm                   Copyright 2022 cPanel, L.L.C.
#                                                           All rights reserved.
# copyright@cpanel.net                                         http://cpanel.net
# This code is subject to the cPanel license. Unauthorized copying is prohibited

use cPstrict;

# NB: For now this module can’t have signatures because
# of the need for inclusion into updatenow.

use parent 'Cpanel::SysPkgs::Base';

use Try::Tiny;

use Cpanel::SafeFile                     ();
use Cpanel::Exception                    ();
use Cpanel::FileUtils::Write             ();
use Cpanel::TimeHiRes                    ();
use Cpanel::Debug                        ();
use Cpanel::Binaries                     ();
use Cpanel::CPAN::IO::Callback::Write    ();
use Cpanel::Parser::Callback             ();
use Cpanel::Validate::FilesystemNodeName ();
use Cpanel::StringFunc::Trim             ();
use Cpanel::OS                           ();
use Cpanel::Repos::Utils                 ();
use Cpanel::SafeRun::Errors              ();
use Cpanel::SafeRun::Object              ();
use Cpanel::SysPkgs                      ();
use Cpanel::Binaries::Yum                ();    # For locking. We should probably directly use it eventually.
use Cpanel::Finally                      ();
use Cpanel::Set                          ();

use IO::Handle;

use constant _ENOENT => 2;

our $VERSION       = '22.3';
our $YUM_BIN       = '/usr/bin/yum';
our $YUM_CONF      = '/etc/yum.conf';
our $FORCE_DRY_RUN = 0;                         # For testing

=encoding utf-8

=head1 NAME

Cpanel::SysPkgs::YUM;

=head1 SYNOPSIS

  use Cpanel::SysPkgs ();

  my $sysp = Cpanel::SysPkgs->new();

  $sysp->install(
        packages        => \@install_packages,
        disable_plugins => ['apluginidontlike'],
  );

=head1 DESCRIPTION

Wrapper around yum binary.

=head1 CONSTRUCTORS

=head2 new(ARGS)

Creates a Cpanel::SysPkgs::YUM object used access the system
'yum' command

Notes:

The odd instantiation logic is because this function usually
receives a Cpanel::SysPkgs object and converts it to a
Cpanel::SysPkgs::YUM object.

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

Optional: A hashref of yum excludes to enable:
Example:
 {
    'kernel'      => 1,
    'ruby'        => 1,
    'bind-chroot' => 1,
 }

=back

=head3 RETURNS

A Cpanel::SysPkgs::YUM object

=cut

sub new {
    my $class = shift;
    my $self  = shift or die;

    $self = $class->SUPER::new($self);
    bless $self, $class;

    $self->{'yum_tolerant'}   = 1;
    $self->{'yum_errorlevel'} = 1;           # default value is 2
    $self->{'yum.conf'}       = $YUM_CONF;

    $self->{'exe'}     = $YUM_BIN;
    $self->{'VERSION'} = $VERSION;

    return $self;
}

=head1 METHODS

=cut

# See _call_yum for a list of available options.
sub uninstall_packages ( $self, %opts ) {

    return $self->_call_yum( %opts, 'command' => ['erase'] );
}

# See _call_yum for a list of available options.
sub install_packages ( $self, %opts ) {

    my $exclude_rules = Cpanel::OS::system_exclude_rules();

    # never try to install/update kernel
    $opts{exclude} //= [];
    if ( $opts{'nasty_hack_to_exclude_kernel'} && $self->should_block_kernel_updates ) {
        foreach my $k (qw{kernel kmod-}) {
            push $opts{exclude}->@*, split( /\s+/, $exclude_rules->{$k} ) if $exclude_rules->{$k};
        }
    }

    return $self->_call_yum(%opts);
}

sub download_packages ( $self, %opts ) {

    return $self->_call_yum( %opts, 'download_only' => 1 );
}

sub _do_warn ($msg) {

    # Log to installer log if we're in that context.
    if ( $ENV{'CPANEL_BASE_INSTALL'} ) {
        require Cpanel::Install::Utils::Logger;
        return Cpanel::Install::Utils::Logger::WARN($msg);
    }
    return CORE::warn($msg);
}

sub add_repo_key {
    my ( $self, $key ) = @_;
    my $run = Cpanel::SafeRun::Object->new(
        program => Cpanel::Binaries::path('rpm'),
        args    => [ '--import', $key ],
    );

    _do_warn( "Could not import key $key: " . $run->autopsy() ) if $run->error_code();
    return !$run->error_code();
}

=head2 add_repo( remote_path => STR, local_path => STR )

Add a YUM repo from one URL or a local file defined by 'remote_path'
and store it to 'local_path' destination.

Returns one hash reference, using the following format.

    {
        success => 1 or 0, # boolean indicating success or not
        status  => 404,    # status code providing more details on the failure (optional)
        reason  => '...',  # string providing reason why it failed             (optional)
    }

=cut

sub add_repo ( $self, %opts ) {

    my ( $remote_path, $real_path ) = @opts{qw{remote_path local_path}};

    # mirror() chokes if $real_path exists, so let’s help that not to happen.
    # It could still happen if, e.g., $real_path gets created between this
    # rename() and the mirror() below, but that should be rare.

    if ( open my $rfh, '<', $real_path ) {
        require File::Copy;
        my $renamed_to = $real_path . substr( rand, 1 ) . '-' . ( localtime =~ tr< ><_>r );
        if ( File::Copy::copy( $rfh => $renamed_to ) ) {
            _do_warn("“$real_path” is about to be rewritten. The old file has been copied to “$renamed_to”.\n");
        }
        else {
            die "The system failed to copy “$real_path” to “$renamed_to” ($!).\n";
        }
    }
    elsif ( $! != _ENOENT() ) {
        _do_warn("open(< $real_path): $!");
    }

    my $response;
    if ( $remote_path =~ qr{^/} ) {

        # add repo from a local path
        my $success = 0;

        require File::Copy;
        $success = 1 if File::Copy::copy( $remote_path, $real_path );

        $response = { 'success' => $success };

        if ( !$success ) {
            $response->{status} = $!;
            if ( !-e $remote_path ) {
                $response->{reason} = qq[$remote_path missing];
            }
        }

    }
    else {
        # NOTE - If you change this to a use statement, run:
        # t/scripts-restartsrv_spamd_check-dependencies.t
        require Cpanel::HTTP::Tiny::FastSSLVerify;
        my $http = Cpanel::HTTP::Tiny::FastSSLVerify->new();
        $response = $http->mirror( $remote_path, $real_path );
    }

    # Clear the fastestmirror plugin cache
    Cpanel::Repos::Utils::post_install();

    return $response;
}

sub reinstall_packages {
    my ( $self, %OPTS ) = @_;

    return $self->_call_yum( %OPTS, 'command' => ['reinstall'] );
}

sub clean ($self) {
    return $self->_call_yum( 'command' => [ 'clean', 'all' ] );
}

=head2 $self->check_and_set_exclude_rules()

This call check_and_set_exclude_rules the /etc/yum.conf and adjust exclude list if needed.

sysup is running that call to ensure we use the correct exclude list

=cut

sub check_and_set_exclude_rules ( $self, %opts ) {

    return 1 unless $self->check_is_enabled;

    # A False return means we couldn't parse yum.conf
    $self->parse_pkgmgr_conf() or return;
    $self->write_pkgmgr_conf();

    return 1;
}

sub checkdb {
    return 1;
}

sub checkconfig {
    my $self = shift or Carp::croak('checkconfig() method called without arguments.');
    ref $self        or Carp::croak("checkconfig() must be called as a method.");

    my $yum       = Cpanel::Binaries::Yum->new;
    my $result    = $yum->cmd( 'info', 'glibc' );
    my $glibcinfo = $result->{'output'} || '';
    if ( $glibcinfo !~ m{ (?: Installed | Available) \s+ Packages }xmsi || $glibcinfo =~ /No\s+Repositories\s+Available/ ) {
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
#   Verifies to see if specific version of a package is installable via yum
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

sub verify_package_version_is_available {
    my ( $self, %OPTS ) = @_;

    die Cpanel::Exception::create( 'MissingParameter', [ 'name' => 'version' ] ) if !defined $OPTS{'version'};

    my $stdout = $self->_list_versions_for_package( $OPTS{'package'} );

    my $regexp = _get_regexp_to_match_yum_list(
        map { quotemeta } @OPTS{ 'package', 'version' },
    );

    foreach my $line ( split m{\n+}, $stdout ) {
        return 1 if $line =~ $regexp;
    }

    die "The package “$OPTS{'package'}” with version “$OPTS{'version'}” is not available via yum: $stdout";
}

sub _get_regexp_to_match_yum_list {
    my ( $pkg_re, $version_re ) = @_;

    return qr/
        ^
        [ \t]*
        $pkg_re         #e.g., MariaDB-server.i686
        (?:\.\S+)*
        [ \t]+
        $version_re     #e.g., 10.0.14-1.el6

        #We don’t do an exact match because MariaDB’s install
        #depends on passing in “10.0” to match “10.0.30”, etc.
        #[ \t]
                        #e.g., @mariadb
    /x;
}

sub _list_versions_for_package {
    my ( $self, $pkg ) = @_;

    Cpanel::Validate::FilesystemNodeName::validate_or_die($pkg);

    my $result = Cpanel::SafeRun::Object->new_or_die(
        'program' => $self->{'exe'},
        'args'    => [ $self->_base_yum_args(), 'list', $pkg ],
    );

    return $result->stdout();
}

###########################################################################
#
# Method:
#   can_packages_be_installed
#
# Description:
#   Calls the system 'yum' command via _exec_yum
#
# Parameters:
#   'packages'                - An arrayref of packages for yum
#                               Example: ['MariaDB-server', 'MariaDB-client']
#   'exclude_packages'        - Optional: An arrayref of packages for yum to exclude
#                               Example: ['MariaDB-compat']
#   'ignore_conflict_packages_regexp'
#                             - Optional: A regex of package names to be used to ignore
#                               some package conflicts
#
# Returns:
#   true or an exception
#
sub can_packages_be_installed {
    my ( $self, %OPTS ) = @_;

    if ( !defined $OPTS{'packages'} ) {
        die Cpanel::Exception::create( 'MissingParameter', [ 'name' => 'packages' ] );
    }

    my $ignore_conflict_packages_regexp = $OPTS{'ignore_conflict_packages_regexp'};

    my $yum_stderr = '';
    my $err;

    try {
        $self->_call_yum(
            %OPTS,
            'command'         => ['install'],
            'dry_run'         => 1,
            'stderr_callback' => sub {
                my ($data) = @_;
                $yum_stderr .= $data;
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
            && $self->_should_ignore_package_conflicts_in_yum_error_output( $yum_stderr, $ignore_conflict_packages_regexp ) ) {
            return 1;
        }

        $self->error( Cpanel::Exception::get_string($err) );
        return 0;
    }

    # Some errors (like a mirror being down) do not cause yum to end up in an error state during a dry run.
    # Parse through the stderr output here to check for certain ones, if a method to do so is passed in.
    if ( ref( $OPTS{'check_yum_preinstall_stderr'} ) eq 'CODE' && $OPTS{'check_yum_preinstall_stderr'}->($yum_stderr) ) {
        $self->error("The following error occurred while attempting to install the requested packages with yum:\n\n$yum_stderr\nThis error must be resolved in order to complete this upgrade.");
        return 0;
    }

    return 1;
}

sub has_exclude_rule_for_package ( $self, $pkg ) {

    $self->parse_pkgmgr_conf;

    my $is_excluded = grep {    # for readability
        $_ eq $pkg                     #
          || $_ eq '^' . $pkg . '$'    #
          || $_ eq '^' . $pkg          #
          || $_ eq $pkg . '$'          #
    } split /\s+/, $self->{original_exclude_string};

    return $is_excluded ? 1 : 0;
}

sub drop_exclude_rule_for_package ( $self, $pkg ) {

    return unless $self->has_exclude_rule_for_package($pkg);

    $self->{exclude_string} =~ s/(?:^$pkg$|^$pkg\s+|\s+$pkg\s+|\s+$pkg$)//g;

    return $self->write_pkgmgr_conf;
}

sub add_exclude_rule_for_package ( $self, $pkg ) {

    return if $self->has_exclude_rule_for_package($pkg);

    $self->{exclude_string} .= " $pkg";

    return $self->write_pkgmgr_conf;
}

##################################################################################
#
#
# What follows is not a part of the SysPkgs interface and is for internal use only.
#
#
##################################################################################

=head2 $self->_parse_existing_excludes( $pkgs = '' )

Internal helper to update the exclude list

=cut

sub _parse_existing_excludes ( $self, $pkgs = '' ) {

    $pkgs ||= '';
    my @PKGS = split( /\s+/, $pkgs );

    # Clean blank entries
    @PKGS = grep( !m/^\s*$/, @PKGS );

    my @remove_excludes = $self->_determine_remove_from_excludes();

    $self->{'excludes'} or die "No excludes found in " . __PACKAGE__;
    my %excludes = $self->{'excludes'}->%*;

    foreach my $excl ( sort keys %excludes ) {

        # Remove any item that matches the key for this exclude.
        @PKGS = grep( !m/$excl/, @PKGS );

        # Remove kmod when excluding kernel packages
        if ( $excl eq 'kernel' ) {
            @PKGS = grep( !m/^kmod$/, @PKGS );
        }

        # Push our exclude on the end.
        push @PKGS, $excludes{$excl};
    }

    # remove unwanted excludes
    foreach my $remove (@remove_excludes) {
        @PKGS = grep( !m/$remove/, @PKGS );
    }

    return ( $self->{'exclude_string'} = join( ' ', sort @PKGS ) );
}

=head2 $self->_determine_remove_from_excludes()

Returns a list of packages/patterns we should not list in the excludes string.

In other words, returns a list of packages we can safely update
and should not be excluded.

=cut

sub _determine_remove_from_excludes ($self) {

    $self->validate_excludes();

    # note: consider moving these rules to Cpanel::OS

    my @remove_excludes = qw[ apache wget mysql mysql* ];

    # ======== Kernel ===========================================================
    if ( !$self->exclude_kernel ) {
        push @remove_excludes, qw( ^kernel ^kmod );
    }

    # ======== Perl =============================================================
    push @remove_excludes, 'perl' unless $self->exclude_perl;

    # ======== Ruby =============================================================
    push @remove_excludes, 'ruby' unless $self->exclude_ruby;

    # ======== Bind Chroot ======================================================
    push @remove_excludes, 'bind-chroot' unless $self->exclude_bind_chroot;

    return @remove_excludes;
}

=head2 $self->parse_pkgmgr_conf()

Parse the exclude string from /etc/yum.conf

Returns 1 on succcess or if check is disabled
exists.

*Note*: This function is a 'private' helper and should not be used
outside of this package. It's a 'CentOS/RedHat' only helper.
Thus we should rename it to _parse_pkgmgr_conf

not possible as EA is still using it at this date: ZC-9239 / ZC-9315

=cut

sub parse_pkgmgr_conf ($self) {    # Please do not use outside of this package
    ref $self or Carp::croak("parse_pkgmgr_conf() must be called as a method.");

    return 1 unless $self->check_is_enabled();

    my $msg = "checkyum version $self->{VERSION}";
    if ( my @excluded_packages = grep { $self->{'exclude_options'}->{$_} } sort keys %{ $self->{'exclude_options'} } ) {
        $msg .= "  (excludes: @excluded_packages)";
    }

    $self->out($msg);

    # If yum.conf doesn't already exist, create it. Previously, function
    # returned.
    if ( !-e $self->{'yum.conf'} ) {
        require Fcntl;
        sysopen my $fh, $self->{'yum.conf'}, Fcntl::O_WRONLY() | Fcntl::O_CREAT() | Fcntl::O_EXCL() or die "Couldn't create $self->{'yum.conf'}: $!";
        close $fh;
    }

    my @YUM_CONF_CONTENTS;

    my $yum_conf_fh = IO::Handle->new();
    my $la          = Cpanel::SafeFile::safeopen( $yum_conf_fh, '<', $self->{'yum.conf'} );
    if ( !$la ) {
        $self->{'logger'}->fatal( "Could not read from " . $self->{'yum.conf'} ) if ( $self->{'logger'} );
        Cpanel::Debug::log_die( "Could not read from " . $self->{'yum.conf'} );
    }

    my @all_exclude_lines;
    my $saw_exclude = 0;
    while ( my $line = <$yum_conf_fh> ) {

        # These lines will be inserted during the write process and can be ignored here.
        next if ( $line =~ m/^\s*tolerant=/i );
        next if ( $line =~ m/^\s*errorlevel=/i );

        # Multiple exclude lines are not understood by yum and will cause bad things to happen.
        # To avoid this, make sure to merge all exclude lines into one if multiple exist.
        # It must also parse the next line as part of the exclude statement if it begins with whitespace.
        if ( $saw_exclude && ( $line =~ m/^[^\s]+/ ) ) { $saw_exclude = 0; }    #We have now left the Exclude statement.
        if ( $line =~ m/^\s*exclude\s*=/i )            { $saw_exclude = 1; }    #We have encountered the Exclude statement.
        if ( $saw_exclude && ( ( $line =~ m/^\s*exclude\s*=\s*(.*)/i ) || ( $line =~ m/^\s*(.*)/i ) ) ) {
            push @all_exclude_lines, $1;
            next;
        }
        push @YUM_CONF_CONTENTS, $line;                                         #If nothing was triggered, then
    }

    my $excludes = join ' ', @all_exclude_lines;

    $self->{'original_exclude_string'} = $excludes;

    # parse will store excludes into $self.
    $self->_parse_existing_excludes($excludes);
    Cpanel::SafeFile::safeclose( $yum_conf_fh, $la );

    $self->{'yum_conf_file_contents'} = \@YUM_CONF_CONTENTS;

    return 1;
}

=head2 $self->write_pkgmgr_conf()

Write /etc/yum.conf from the previously parsed
and memory values.

Returns 1 on succcess

*Note*: This function is a 'private' helper and should not be used
outside of this package. It's a 'CentOS/RedHat' only helper.
Thus we should rename it to _write_pkgmgr_conf

not possible as EA is still using it at this date: ZC-9239 / ZC-9315

=cut

sub write_pkgmgr_conf ($self) {    # Please do not use outside of this package
    ref $self or Carp::croak("write_pkgmgr_conf() must be called as a method.");

    my @temp_file_contents;

    # yum.conf contains non-whitespace data
    if ( grep { $_ =~ /[^\s]+/ } @{ $self->{'yum_conf_file_contents'} } ) {

        foreach my $line ( @{ $self->{'yum_conf_file_contents'} } ) {

            push @temp_file_contents, $line;

            if ( $line =~ m/^\[main\]/i ) {

                # add updated options
                push @temp_file_contents, 'exclude=' . $self->{'exclude_string'} . "\n";
                push @temp_file_contents, 'tolerant=' . $self->{'yum_tolerant'} . "\n";
                push @temp_file_contents, 'errorlevel=' . $self->{'yum_errorlevel'} . "\n";
            }
        }

    }
    else {
        # Default template.
        # This could be improved? There's a lot more that is in the yum.conf than this.

        my $yum_string = "[main]\n";
        $yum_string .= 'exclude=' . $self->{'exclude_string'} . "\n";
        $yum_string .= 'tolerant=' . $self->{'yum_tolerant'} . "\n" . 'errorlevel=' . $self->{'yum_errorlevel'} . "\n";
        push @temp_file_contents, $yum_string;
    }

    # We want this to be 644 so unprivileged users can use yum.
    if ( !Cpanel::FileUtils::Write::overwrite_no_exceptions( $self->{'yum.conf'}, join( '', @temp_file_contents ), 0644 ) ) {
        $self->{'logger'}->fatal( "Could not write to " . $self->{'yum.conf'} ) if ( $self->{'logger'} );
        Cpanel::Debug::log_die( "Could not write to " . $self->{'yum.conf'} );
    }

    return 1;
}

sub repolist {
    my ( $self, %OPTS ) = @_;
    return $self->_call_yum( %OPTS, 'command' => ['repolist'] );
}

###########################################################################
#
# Method:
#   _call_yum
#
# Description:
#   Calls the system 'yum' command via _exec_yum
#
# Parameters:
#   'packages'                - Optional: An arrayref of packages for yum
#                               Example: ['MariaDB-server', 'MariaDB-client']
#   'exclude_packages'        - Optional: An arrayref of packages for yum to exclude
#                               Example: ['MariaDB-compat']
#   'command'                 - Optional: An arrayref representing the yum command to run
#                               Default: ['install]
#                               Example: ['update']
#   'usecache'                - Optional: A boolean that will enable yum caching
#   'dry_run'                 - Optional: A boolean that will cause yum to only
#                               test to see if the transaction will succeed
#   'stdout_callback'         - Optional: A coderef that will receive everything yum writes
#                               to stdout
#   'stderr_callback'         - Optional: A coderef that will receive everything yum writes
#                               to stderr
#   'disable_plugins'         - Optional: An arrayref of yum plugins to disable for this call.
#                               Example: ['fastestmirror']
#
# Returns:
#   true or an exception
#

sub _call_yum ( $self, %OPTS ) {

    my $packages         = $OPTS{'packages'}         || $OPTS{'pkglist'} || [];    # pkglist is for legacy calls
    my $exclude_packages = $OPTS{'exclude_packages'} || [];
    my $command          = $OPTS{'command'}          || ['install'];
    my $usecache         = $OPTS{'usecache'}      ? 1 : 0;
    my $download_only    = $OPTS{'download_only'} ? 1 : 0;
    my $download_dir     = $OPTS{'download_dir'};
    my $dry_run          = $OPTS{'dry_run'} ? 1 : 0;
    my $disable_plugins  = $OPTS{'disable_plugins'} || [];
    my $is_base_install  = defined( $ENV{'CPANEL_BASE_INSTALL'} );

    # On el7 keepcache defaults to 1, on el8 it defaults to 0
    # On el8 we have to take steps to preserve the cache, otherwise the optimizations to pre-download
    # packages are useless.
    my $keepcache = $OPTS{'keepcache'} // ( $is_base_install ? 1 : undef );

    my @args = $self->_base_yum_args();
    my @post_args;

    push @args, '--cacheonly' if $usecache;

    if ( $dry_run || $FORCE_DRY_RUN ) {
        push @args, '--assumeno';
    }

    push @args, '--downloadonly' if $download_only;
    push @args, ( '--downloaddir' => $download_dir ) if $download_dir;

    if ( defined($keepcache) ) {
        push @args, '--setopt', sprintf( 'keepcache=%d', $keepcache ? 1 : 0 );
    }

    foreach my $package ( $exclude_packages->@* ) {
        if ( $command eq 'erase' ) {

            # DWIM for erase action requires doing `-- -PACKAGENAME`
            # at the end to exclude.
            push @post_args, "-$package";
        }
        else {
            push @args, '--exclude', $package;
        }
    }

    foreach my $plugin ( $disable_plugins->@* ) {
        push @args, '--disableplugin', $plugin;
    }

    push @args, @{$command};
    foreach my $package ( @{$packages} ) {
        Cpanel::Validate::FilesystemNodeName::validate_or_die($package);
        push @args, $package;
    }

    # Enable relevant repos. Treat EPEL as a special case below.
    my @repos = grep { $_ ne 'epel' } Cpanel::OS::package_repositories()->@*;
    foreach my $repo (@repos) {
        push @args, '--enablerepo=' . $repo;
    }

    if ( is_epel_installed() ) {
        push @args, '--enablerepo=epel';
    }

    # Make sure that original_exclude_string doesn't have kernel excludes (ever)
    my $finally;
    if ( exists $self->{'original_exclude_string'} ) {
        my @exclude_rules     = map { split /\s+/, Cpanel::OS::system_exclude_rules()->{$_} } qw(kernel kmod-);
        my @orig_excludes     = split /\s+/, $self->{'original_exclude_string'} // '';
        my @filtered_excludes = Cpanel::Set::difference( \@orig_excludes, \@exclude_rules );
        $finally = Cpanel::Finally->new( sub { $self->{'exclude_string'} = join( ' ', @filtered_excludes ); $self->write_pkgmgr_conf(); } );
    }

    push @args, '--', @post_args if @post_args;

    return $self->_exec_yum( %OPTS, '_args' => \@args );
}

sub _exec_yum ( $self, %OPTS ) {

    my $stdout_callback    = $OPTS{'stdout_callback'};
    my $stderr_callback    = $OPTS{'stderr_callback'};
    my $handle_child_error = $OPTS{'handle_child_error'} || \&_die_child_error;

    # Set ENV with local to avoid
    # having to use before_exec because
    # it prevents FastSpawn
    local $ENV{'LANG'}   = 'C';
    local $ENV{'LC_ALL'} = 'C';

    my $start_time = Cpanel::TimeHiRes::time();
    my $stderr     = '';

    # NOTE: Cpanel::Parser::Callback expects the callback(s) to return true when the callback is successful so it can update its data buffer appropriately.
    # Not all output objects that may be used here return true from the output call, so explicitly returning true after output allows the parser work correctly in all cases.
    my $callback_obj = Cpanel::Parser::Callback->new( 'callback' => sub { $self->out(@_); return 1; } );

    # stderr should not call ->error since it will trigger updatenow to think the update
    # has failed.
    my $callback_err_obj = Cpanel::Parser::Callback->new( 'callback' => sub { $self->warn(@_); return 1; } );

    $self->{'logger'}->info("Starting yum execution “@{$OPTS{'_args'}}”.") if $self->{'logger'};
    Cpanel::Debug::log_debug("Starting yum execution “@{$OPTS{'_args'}}”.");

    # only holds the lock on some specific commands
    my $lock = Cpanel::Binaries::Yum->new->get_lock_for_cmd( $self->{'logger'}, $OPTS{'_args'} );

    my $result = Cpanel::SafeRun::Object->new(
        'program' => $self->{'exe'},
        'args'    => $OPTS{'_args'},
        'stdin'   => $OPTS{'stdin'},
        'stdout'  => Cpanel::CPAN::IO::Callback::Write->new(
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
    $self->{'logger'}->info("Completed yum execution “@{$OPTS{'_args'}}”: in $exec_time second(s).") if $self->{'logger'};
    Cpanel::Debug::log_debug("Completed yum execution “@{$OPTS{'_args'}}”: in $exec_time second(s).");

    if ( $result->CHILD_ERROR() && !grep( /^--assumeno$/, @{ $OPTS{'_args'} } ) ) {
        return $handle_child_error->( $result, $stderr, %OPTS );
    }

    return 1;
}

sub _base_yum_args ($self) {

    # SysPkgs should always run yum with these arguments.
    return ( '--assumeyes', '--color=never', '--config', $self->{'yum.conf'} );
}

sub _die_child_error {
    my ( $result, $stderr, %opts ) = @_;

    $result->die_if_error();

    return;    ## Just to satisfy cplint; we never actually get here.
}

sub _should_ignore_package_conflicts_in_yum_error_output ( $self, $yum_stderr, $ignore_conflict_packages_regexp ) {    ## no critic qw(Subroutines::ProhibitManyArgs)

    my @output = split( m{\n}, $yum_stderr );

    my ( $has_error_summary, $in_error_summary, $has_transaction_check_error, $in_transaction_check_error );
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

sub is_epel_installed {
    return -e '/etc/yum.repos.d/epel.repo' ? 1 : 0;
}

sub is_epel_enabled {
    my $repo_file = '/etc/yum.repos.d/epel.repo';
    open( my $fh, '<', $repo_file ) or return 0;

    # Assume that the first enabled= seen is for the primary repo settings.
    while ( my $line = <$fh> ) {
        next unless $line =~ m{^enabled\s*=};
        my ($enabled) = $line =~ m{enabled\s*=\s*(\d*)}a;
        return $enabled ? 1 : 0;
    }

    return 0;    # Couldn't find the enabled=1 setting!
}

sub ensure_plugins_turned_on ($self) {

    if ( !exists $self->{'yum_conf_file_contents'} ) {

        return unless $self->parse_pkgmgr_conf();
    }

    # scenarios, plugins=0, plugins=1 or no plugins
    # plugins will be undef if not present, or the value of present if we
    # found it

    my $plugins;

    my @yum_conf;

    foreach my $line ( @{ $self->{'yum_conf_file_contents'} } ) {
        if ( $line =~ m/^plugins=(.*)\n$/ ) {
            $plugins = Cpanel::StringFunc::Trim::ws_trim($1);
            if ( $plugins == 0 ) {
                push( @yum_conf, "plugins=1\n" );
            }
            else {
                push( @yum_conf, $line );
            }
        }
        else {
            push( @yum_conf, $line );
        }
    }

    if ( !defined $plugins ) {
        $plugins  = 0;
        @yum_conf = ();
        foreach my $line ( @{ $self->{'yum_conf_file_contents'} } ) {
            if ( $line =~ m/^\[main\]/ ) {
                push( @yum_conf, $line );
                push( @yum_conf, "plugins=1\n" );
            }
            else {
                push( @yum_conf, $line );
            }
        }
    }

    if ( !$plugins ) {
        $self->{'yum_conf_file_contents'} = \@yum_conf;
        $self->write_pkgmgr_conf();
    }

    return 1;
}

=head2 search(%opts)

note: by default only search the available packages

Returns LIST of HASHREFS containing what looks like the below:

    Cpanel::SysPkgs->new()->search( pattern => [ qw/list of packages or pattern/ ] )

    [
      {
        'release' => '1160.31.1.el7',
        'name' => 'kernel',
        'version' => '3.10.0',
        'arch' => 'x86_64',
        'package' => 'kernel-3.10.0-1160.31.1.el7.x86_64'
      }
    ];

Empty list is returned when no matches exist, dies on other failures.

=cut

sub search ( $self, %opts ) {

    return $self->_search( 'available', %opts );
}

# Moved from Cpanel::Kernel::Status
# opts: force, all, pattern

=head2 search(%opts)

Search installed packages

    Cpanel::SysPkgs->new()->search_installed( pattern => [ qw/list of packages or pattern/ ] )

=cut

sub search_installed ( $self, %opts ) {

    return $self->_search( 'installed', %opts );
}

sub _search ( $self, $state, %opts ) {

    my @args = ();
    push @args, '--disableexcludes=all' if $opts{force};
    push @args, '--showduplicates'      if $opts{all};     # By default, only the latest one is shown

    my $syspkgs = Cpanel::SysPkgs->new();
    my $proc    = Cpanel::SafeRun::Object->new(
        program => scalar Cpanel::Binaries::path('yum'),
        args    => [ @args, '-q', 'info', $state, $opts{pattern} ],
    );
    return if $proc->stderr() =~ m/^Error: No matching Packages to list/mi;
    $proc->die_if_error();

    my $re = qr/
        ^Name\s*:\s*(?<name>\S*)\s*
        ^Arch\s*:\s*(?<arch>\S*)\s*
        ^Version\s*:\s*(?<version>\S*)\s*
        ^Release\s*:\s*(?<release>\S*)\s*
    /imx;
    my $stdout = $proc->stdout();
    my @found;
    while ( $stdout =~ m/$re/g ) {
        push @found, { %+, package => "$+{name}-$+{version}-$+{release}.$+{arch}" };
    }
    return \@found;
}

=head2 list_available(%opts)

List packages available from the upstream distro

    Cpanel::SysPkgs->new()->list_available( disable_epel => 1 )

=cut

sub list_available ( $self, %opts ) {
    my $pattern = $opts{'search_pattern'} // '';    # This should be safe from a shell injection.

    my @args;
    if ( $opts{'disable_epel'} && is_epel_enabled() ) {
        push @args, '--disablerepo=epel';
    }

    my @rpms = split /\n/, Cpanel::SafeRun::Errors::saferunallerrors( $YUM_BIN, '-d', '0', @args, 'list', 'available' );
    shift @rpms;                                    # Strip the header.
    my @packages;
    while ( my $rpm = shift @rpms ) {
        while ( length $rpms[0] && $rpms[0] =~ m/^ / ) {    # yum does strange column wrapping. we're fixing that here.
            $rpm .= shift @rpms;
        }
        my ( $package, $version, $repo ) = split( " ", $rpm );
        length $repo or next;

        next if $opts{'disable_ea4'} && $repo =~ m/^ea4-/i;

        my ( $name, $arch ) = $package =~ m{^(.+)\.([^.]+)$};

        next if length $pattern && index( $name, $pattern ) == -1;

        push @packages, {
            'name'          => $name,       #
            'version'       => $version,    #
            'repo'          => $repo,       #
            'arch'          => $arch,       #
            'name_and_arch' => $package
        };    #, 'description' => $description };
    }

    return \@packages;
}

1;
