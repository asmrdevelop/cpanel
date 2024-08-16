package Cpanel::Update::Now;

# cpanel - Cpanel/Update/Now.pm                    Copyright 2022 cPanel, L.L.C.
#                                                           All rights reserved.
# copyright@cpanel.net                                         http://cpanel.net
# This code is subject to the cPanel license. Unauthorized copying is prohibited

use cPstrict;

use utf8;

use Try::Tiny;

use Cpanel::Carp                   ();
use Cpanel::LoadModule             ();
use Cpanel::Locale::Context        ();
use Cpanel::SafeDir::RM            ();
use Cpanel::Hostname               ();
use Cpanel::Config::Merge          ();
use Cpanel::Config::Sources        ();
use Cpanel::Crypt::GPG::VendorKeys ();
use Cpanel::FileUtils::Copy        ();
use Cpanel::Binaries               ();
use Cpanel::ForkAsync              ();
use Cpanel::Exception              ();
use Cpanel::FileUtils::TouchFile   ();

use Cpanel::OS                  ();
use Cpanel::RPM::Versions::File ();
use Cpanel::SafeDir::MK         ();
use Cpanel::SafeFile            ();
use Cpanel::SafeRun::Object     ();
use Cpanel::Server::Type        ();
use Cpanel::Sync::v2            ();
use Cpanel::Sysup               ();
use Cpanel::LoadFile            ();
use Cpanel::Signal              ();
use Cpanel::TempFile            ();
use Cpanel::Themes::Get         ();
use Cpanel::Update::Blocker     ();
use Cpanel::Update::Config      ();
use Cpanel::Update::Logger      ();
use Cpanel::Update::Tiers       ();
use Cpanel::Usage               ();
use Cpanel::Version::Compare    ();
use Cpanel::Version::Tiny       ();
use Cpanel::iContact            ();
use File::Basename              ();
use IO::Handle                  ();
use Cpanel::Sys::Hostname       ();

# This would ideally go in scripts/updatenow, but adding it there
# creates other complexities that are best deferred.
use Cpanel::PwCache::Build ();    # PPI NO PARSE - needed for install

# ACTIVATION: remove this activation piece when cPanel on CentOS 7 is officially available #
use Cpanel::ConfigFiles::RpmVersions ();

our $FASTEST_MIRROR_CNF_FILE = '/etc/yum/pluginconf.d/fastestmirror.conf';

# Setup max threads to be aware of the
# large number of EA4 mirrors
our $FASTEST_MIRROR_MAX_THREADS = 65;

# The default of 3 seconds is far too long
# to not end up with high latency mirrors
our $FASTEST_MIRROR_SOCKET_TIMEOUT = 2;

=head1 NAME

Cpanel::Update::Now - manages updates along cpanel releases

=head1 USAGE

    # This code is called from scripts/updatenow
    my $options = Cpanel::Update::Now::parse_argv(@ARGV);

    # Man option is outside C:U:N
    if ( $options->{'man'} ) {
        exec( 'perldoc', $0 );
        exit;
    }

    # New with options from parse_argv
    my $update_now = Cpanel::Update::Now->new($options);

    # Eval and call terminate so testing can happen outside this script.
    eval { $update_now->run(); } or $update_now->terminate($@);


=head1 DESCRIPTION

NOTE: Under most circumstances, you should never call this script directly. B</usr/local/cpanel/scripts/upcp>, called with an optional [--force]
should be all you need. --sync is only intended to be called by other cpanel scripts when it appears that cpanel managed files
have been deleted.

The normal usage of this script is to update cpanel to the latest version of your TIER I<(see /etc/cpupdate.conf)>.
By default, no update is done by default if you are already on that version. The UPDATES setting in cpupdate.conf
is also honored when the environment variable CPANEL_IS_CRON is set (usually from upcp).

If an HTTPUPDATE= setting is present in /etc/cpsources.conf with a hostname, this will be the preferred source to sync from.

=head1 METHODS

=over 4

=item B<new>

Called from updatenow mostly, with $options from returned from parse_argv

=cut

sub new {
    my $class = shift;

    my $self = shift || {};
    ref($self) eq 'HASH' or die("Options hash ref not passed to new");

    $self = bless $self, $class;

    my $default_ulc = '/usr/local/cpanel';
    $self->{'ulc'} ||= $default_ulc;

    if ( !$self->{'staging_dir'} ) {
        $self->{'staging_dir'} = $self->determine_staging_dir();
        $self->{'staging_dir'} = $self->{'ulc'} if $self->{'ulc'} ne $default_ulc;
    }

    $self->{'dnsonly'} //= Cpanel::Server::Type::is_dnsonly();
    $self->{'update_is_available_exit_code'} = 42;
    $self->{'cpanel_config_file'} ||= '/var/cpanel/cpanel.config';
    $self->{'firstinstall'} = ( $ENV{'CPANEL_BASE_INSTALL'} && !-e '/usr/local/cpanel/cpanel' ) ? 1 : 0;

    # Track the starting spot in the existing log file so we can suck it in later if we need to iContact it.
    if ( $self->{'log_file_path'} && -e $self->{'log_file_path'} ) {
        $self->{'log_tell'} = ( stat( $self->{'log_file_path'} ) )[7];
    }

    $self->{'logger'} ||= Cpanel::Update::Logger->new( { $self->{'log_file_path'} ? ( 'logfile' => $self->{'log_file_path'} ) : ( 'to_memory' => 1 ), 'stdout' => 1, 'log_level' => ( $self->{'verbose'} ? 'debug' : 'info' ) } );

    return $self;
}

sub determine_staging_dir {
    my $self = shift         or die;
    ref $self eq __PACKAGE__ or die("Must be called as a method");

    my $staging_dir = $self->upconf->{'STAGING_DIR'};

    if ( $staging_dir !~ m{^/usr/local/cpanel/?$} ) {
        $self->{using_custom_staging_dir} = 1;
        my $hostname = Cpanel::Sys::Hostname::gethostname();
        $hostname =~ s/\./_/g;
        $staging_dir .= ( substr( $staging_dir, -1 ) eq '/' ? ".cpanel__${hostname}__upcp_staging" : "/.cpanel__${hostname}__upcp_staging" );
        return $staging_dir;
    }
    return $staging_dir;
}

sub validate_staging_dir {
    my $self = shift         or die;
    ref $self eq __PACKAGE__ or die("Must be called as a method");

    if ( $self->{'staging_dir'} !~ m{^/usr/local/cpanel/?$} ) {

        eval { Cpanel::Update::Config::validate_staging_dir( $self->{'staging_dir'}, 'die_on_failure' ); } or do {
            my $error_as_string = Cpanel::Exception::get_string($@);
            $self->logger->fatal("Failed to validate staging directory: “$error_as_string”.");
            die( { 'exit' => 1, 'remove_blocker_file' => 0 } );
        };
    }
    return 1;
}

# use a sub for easier testing
sub advertise_startup {
    my $self = shift         or die;
    ref $self eq __PACKAGE__ or die("Must be called as a method");

    my $suffix = $0 =~ qr{\.static(-cpanelsync)?$} ? '.static' : '';
    $self->logger->info("Running version '$Cpanel::Version::Tiny::VERSION_BUILD' of updatenow${suffix}.");

    return;
}

=item B<logger>

Helper function to ease logging in subroutines below.

=cut

sub logger {
    my $self = shift         or die;
    ref $self eq __PACKAGE__ or die("Must be called as a method");

    return $self->{'logger'};
}

=item B<dry_run>

Helper function to check if we're in dry run mode.

=cut

sub dry_run {
    my $self = shift         or die;
    ref $self eq __PACKAGE__ or die("Must be called as a method");

    return $self->{'dry_run'} ? 1 : 0;
}

=item B<upconf>

Helper function to cache Cpanel::Update::Config::load();

=cut

sub upconf {
    my $self = shift         or die;
    ref $self eq __PACKAGE__ or die("Must be called as a method");

    $self->{'upconf'} ||= Cpanel::Update::Config::load();
    return $self->{'upconf'};
}

=item B<tiers>

Helper function to access a Cpanel::Update::Tiers object.

=cut

sub tiers {
    my $self = shift         or die;
    ref $self eq __PACKAGE__ or die("Must be called as a method");

    $self->{'tiers'} ||= Cpanel::Update::Tiers->new( logger => $self->{'logger'} );
    return $self->{'tiers'};
}

=item B<cpsrc>

Helper function to cache the results of Cpanel::Config::Sources::loadcpsources();

=cut

sub cpsrc {
    my $self = shift         or die;
    ref $self eq __PACKAGE__ or die("Must be called as a method");

    $self->{'CPSRC'} ||= Cpanel::Config::Sources::loadcpsources();
    return $self->{'CPSRC'};
}

=item B<parse_argv>

Takes an array copy, presumably from @ARGV and parses for known options this class wants for new() calls.
Requrns a hash ref, able to be passed to new.

=cut

sub parse_argv {
    my %options = (
        'sync'               => 0,
        'force'              => 0,
        'upcp'               => 0,
        'log_file_path'      => undef,
        'man'                => 0,
        'verbose'            => 0,
        'checkremoteversion' => 0,
        'skipreposetup'      => 0,
        'dry_run'            => 0,
        'upgrade_to_main'    => 0,
    );

    Cpanel::Usage::wrap_options(
        \@_,
        \&_usage,
        {
            'sync'               => \$options{'sync'},
            'force'              => \$options{'force'},
            'upcp'               => \$options{'upcp'},
            'verbose'            => \$options{'verbose'},
            'checkremoteversion' => \$options{'checkremoteversion'},
            'log'                => \$options{'log_file_path'},
            'man'                => \$options{'man'},
            'dry_run'            => \$options{'dry_run'},
            'skipreposetup'      => \$options{'skipreposetup'},
            'upgrade_to_main'    => \$options{'upgrade_to_main'},
        }
    );

    return \%options;
}

=item B<rebuild_argv>

Uses the objects' configuration to construct a set of options useable to exec
into an alternate version of updatenow.static.

=cut

sub rebuild_argv {
    my $self = shift         or die;
    ref $self eq __PACKAGE__ or die("Must be called as a method");

    my @argv = (
        $self->{'sync'}               ? ('--sync')                                            : (),
        $self->{'force'}              ? ('--force')                                           : (),
        $self->{'upcp'}               ? ('--upcp')                                            : (),
        $self->{'verbose'}            ? ('--verbose')                                         : (),
        $self->{'checkremoteversion'} ? ('--checkremoteversion')                              : (),
        $self->{'dry_run'}            ? ('--dry_run')                                         : (),
        $self->{'skipreposetup'}      ? ('--skipreposetup')                                   : (),
        $self->{'log_file_path'}      ? ( '--log=' . $self->{'log_file_path'} )               : (),
        $self->{'upgrade_to_main'}    ? ( '--upgrade_to_main=' . $self->{'upgrade_to_main'} ) : (),
    );
    return @argv;
}

=item B<setup_rpms_targets>

Mark some targets as uninstalled if needed.
Only for DNSONly servers for now

=cut

sub setup_rpms_targets {
    my $self = shift         or die;
    ref $self eq __PACKAGE__ or die("Must be called as a method");

    # for now only set uninstall targets on dnsonly servers
    return unless $self->{'dnsonly'};

    # these targets should always be uninstalled on dnsonly
    foreach my $target (qw{mailman munin analog awstats roundcube clamav composer proftpd pure-ftpd webalizer ng-cpanel-jupiter-apps}) {
        $self->logger->info(qq[Mark target '$target' as 'uninstalled'.]);

        # Note: during a fresh install we run this command using a minimal bootsrap version of cPanel Perl
        $self->_uninstall_rpm_target($target);
    }

    $self->rpms()->save();

    return;
}

#
# This function set the local target for rpm.versions to 'uninstalled'
# so that the next check_cpanel_pkgs or upcp run will remove the target
#
sub _uninstall_rpm_target {
    my ( $self, $target ) = @_;
    $self->rpms()->set_target_settings( { 'key' => [$target], 'value' => 'uninstalled' } );
    return;
}

=item B<run>

Called by updatenow. Provides an outline of how the program is to be run.

NOTE: This run block is evaled from updatenow. There are multiple points throughout
the code which call die as a means to tell the parent script or testing
infrastructure that an exit is supposed to happen at that point.

=cut

sub run {
    my $self = shift         or die;
    ref $self eq __PACKAGE__ or die("Must be called as a method");

    # Ensure that any locale formatting is for terminals rather than
    # for HTML or plain text.
    local $Cpanel::Locale::Context::DEFAULT_OUTPUT_CONTEXT = 'ansi';
    local $Cpanel::Carp::OUTPUT_FORMAT                     = q<>;

    # log what version this program is running as.
    $self->advertise_startup();

    # We will soon be downloading files, lets make sure we have up to date public keys.
    Cpanel::Crypt::GPG::VendorKeys::download_public_keys( 'logger' => $self->{'logger'} );

    # Determine our current version if possible.
    $self->set_initial_starting_version();

    # Validate the staging dir to use.
    $self->validate_staging_dir();

    # Validate the object's current configuration is valid.
    $self->validate_config();

    # If the max threads is set
    # low it can take a long time to check all the EA4 mirrors
    $self->_ensure_yum_fastest_mirror_optimized();

    # Determine our target_version
    $self->set_tier_or_sync_version();

    # We haven't allowed downgrades for years. Let's just block this the second we have a start and target.
    $self->block_if_downgrade();

    # If this is a major version change, see if we need to switch to the LTS version before proceeding
    # outside of this major version.
    my $final_target = 0;
    $self->current_lts_first() or $self->next_lts_before_target() or $final_target = 1;

    if ( $self->_current_updatenow_version ne $self->target_version ) {
        $self->logger->info("Switching to version $self->{target_version} of updatenow to determine if we can reach that version without failure.");
        $self->become_a_new_updatenow();
    }

    # Determines if our ultimate goal is reachable.
    # Shorts if it sees we've done the check already ( $ENV{'UPDATE_IS_ALLOWED'} eq $self->target_version )
    $self->can_update();

    # Make sure scripts/sysup has effectively been run
    # while we are staging files
    my $assure_all_distro_packages_pid = $self->assure_all_distro_packages();

    # make webmail jupiter into a real directory
    # this needs to happen before staging files
    my $webmail_jupiter = $self->{'ulc'} . '/base/webmail/jupiter';
    if ( -l $webmail_jupiter ) {
        my $webmail_paper_lantern = "$self->{'ulc'}/base/webmail/paper_lantern";
        Cpanel::FileUtils::Copy::safecopy( $webmail_paper_lantern, "${webmail_jupiter}_tmp" );
        unlink $webmail_jupiter                              or warn "Couldn't unlink ${webmail_jupiter}: $!";
        rename( "${webmail_jupiter}_tmp", $webmail_jupiter ) or warn "Couldn't rename ${webmail_jupiter}_tmp to $webmail_jupiter: $!";
    }

    # Download all of the new files we'll be needing for this update.
    $self->stage_files();

    $self->check_for_all_distro_packages_error($assure_all_distro_packages_pid);

    # Pre-install the MOST of the new perl rpms which switching a major version of perl
    # we have to install with --nodeps to pull this off but it reduces the window that
    # the system is unstable.
    $self->preinstall_perlmajor_upgrade();

    # Test staged rpms to ensure they won't blow up when we try to install them.
    my $need_rpms_update = $self->test_rpm_transaction();

    # Sleep until 10 seconds after the minute so we can "try" to avoid cron being triggered
    # before we get perl and the new binaries in place.
    sleep( ( 70 - ( time % 60 ) ) % 60 ) if $self->{'did_preinstall'};

    # need to be done before installing files (compiled binaries) and updating RPMs
    $self->disable_services($need_rpms_update);

    # Do the work. This call should always throw a die up to updatenow.
    $self->install_files();

    $self->log_update_completed();

    # Remove blocker file for delayed upgrade if we reached out final target.
    unlink Cpanel::Update::Blocker->upgrade_deferred_file if $final_target;

    # Throw a signal that we completed successfully.
    die( { 'exit' => 0, 'remove_blocker_file' => 1 } );
}

sub block_if_downgrade {
    my $self = shift         or die;
    ref $self eq __PACKAGE__ or die("Must be called as a method");

    # You can't go down a major version.
    my $target_major   = Cpanel::Version::Compare::get_major_release( $self->target_version );
    my $starting_major = Cpanel::Version::Compare::get_major_release( $self->starting_version );
    return 0 if Cpanel::Version::Compare::compare( $target_major, '>=', $starting_major );

    return $self->block_from_updatenow( "A major version downgrade from $self->{starting_version} to $self->{target_version} is not allowed.", 5 );
}

sub assure_all_distro_packages {
    my $self = shift         or die;
    ref $self eq __PACKAGE__ or die("Must be called as a method");

    $self->logger->info("Ensuring required distro packages are installed.");

    return Cpanel::ForkAsync::do_in_child(
        sub {
            # Make sure all updates provided by yum are in place
            my $want_supplemental_packages = $ENV{'CPANEL_BASE_INSTALL'} ? 0 : 1;
            my $sysup                      = Cpanel::Sysup->new( { 'logger' => $self->logger() } );

            my $upgrade_or_install = $ENV{'CPANEL_BASE_INSTALL'} ? q[install] : q[upgrade to];

            $sysup->run(
                'skipreposetup'       => ( $self->{'skipreposetup'} ? 1 : 0 ),
                supplemental_packages => $want_supplemental_packages
            ) or die "Cannot $upgrade_or_install $self->{'target_version'} until needed system packages are installed.";

            return 1;
        }
    );
}

=item B<check_for_all_distro_packages_error>

Waits for the pid returned from assure_all_distro_packages() to exit
and blocks update if it exits with an error.

This function takes one argument:

=over 3

=item $assure_all_distro_packages_pid C<SCALAR>

    The pid to wait for.

=back

=cut

sub check_for_all_distro_packages_error {
    my ( $self, $assure_all_distro_packages_pid ) = @_;
    $self                    or die;
    ref $self eq __PACKAGE__ or die("Must be called as a method");

    local $?;
    _waitpid($assure_all_distro_packages_pid);
    if ( $? != 0 ) {
        my $upgrade_or_install = $ENV{'CPANEL_BASE_INSTALL'} ? q[install] : q[upgrade to];
        $self->block_from_updatenow( "Cannot $upgrade_or_install $self->{'target_version'} until needed system packages are installed.", 18 );
    }
    return 1;
}

sub block_from_updatenow {
    my ( $self, $msg, $exit_num ) = @_;
    $self                    or die;
    ref $self eq __PACKAGE__ or die("Must be called as a method");

    # We need to generate a blocker file for this so it shows up in the UI.
    my $blocker_object = Cpanel::Update::Blocker->new(
        {
            'logger'           => $self->logger,
            'starting_version' => 1,                  # We don't need starting version to block_version_change and we might not have a vaild one.
            'target_version'   => 1,                  # We also don't need a target version to block.
            'upconf_ref'       => 1,
            'tiers'            => 1,
            'force'            => $self->{'force'},
        }
    );

    $blocker_object->block_version_change($msg);
    $blocker_object->generate_blocker_file();
    die( { 'exit' => $exit_num || 254, 'remove_blocker_file' => 0, 'message' => $msg } );
}

=item B<preinstall_perlmajor_upgrade>

    Pre-install the MOST of the new perl rpms which switching a major version of perl
    we have to install with --nodeps to pull this off but it reduces the window that
    the system is unstable.

=cut

sub preinstall_perlmajor_upgrade {
    my $self = shift         or die;
    ref $self eq __PACKAGE__ or die("Must be called as a method");

    # If this is a fresh install then we don't need to pre-install the RPMs.
    # There's no outage window we need to reduce.
    return if $self->{'initial_install'};

    # If the new perl is already in place, then we're not switching to it for the first time.
    return if -x Cpanel::Binaries::path("perl");

    $self->logger->info("This upgrade is a major perl version change. Pre-installing some packages to reduce the window where cPanel is unstable.");
    return if ( $self->dry_run );

    $self->{'did_preinstall'} = eval { $self->rpms->preinstall_perlmajor_upgrade() };

    if ($@) {
        my $error_as_string = Cpanel::Exception::get_string($@);
        $self->logger->fatal("Error pre-installing Perl packages when switching major versions: $error_as_string. Aborting upgrade to avoid an unstable system.");
        die( { 'exit' => 1, 'remove_blocker_file' => 1, 'message' => "Error pre-installing Perl packages when switching major versions: $error_as_string. see https://go.cpanel.net/perlmajorupgradefailure for more information" } );
    }

    return;
}

=item B<test_rpm_transaction>

utilize rpm in test mode to see if the RPMS will be allowed to install when we start putting things in place later.

=cut

sub test_rpm_transaction {
    my $self = shift         or die;
    ref $self eq __PACKAGE__ or die("Must be called as a method");

    $self->logger->info("Testing if the newly downloaded packages can be installed without conflict");
    return if ( $self->dry_run );

    eval { $self->rpms->test_rpm_install() };

    if ($@) {
        my $error_as_string = Cpanel::Exception::get_string($@);
        $self->logger->fatal("Error testing if the packages will install: $error_as_string  see https://go.cpanel.net/rpmcheckfailed for more information");
        die( { 'exit' => 1, 'remove_blocker_file' => 1, 'message' => "Error testing if the packages will install: $error_as_string  see https://go.cpanel.net/rpmcheckfailed for more information" } );
    }
}

=item B<current_lts_first>

If target is past the current LTS version, we need to upgrade to the latest LTS for this major before proceeding further.

=cut

sub current_lts_first {
    my $self = shift         or die;
    ref $self eq __PACKAGE__ or die("Must be called as a method");

    my $starting_version     = $self->starting_version;
    my $starting_lts_version = $self->tiers->get_lts_for($starting_version) or return 0;
    my $target_lts_version   = $self->tiers->get_lts_for( $self->{target_version} );

    # The target is the same LTS as the current.
    return 0 if $target_lts_version && $target_lts_version eq $starting_lts_version;

    # We're actually newer than the $starting_lts_version. That's good enough.
    return 0 if Cpanel::Version::Compare::compare( $starting_version, '>=', $starting_lts_version );

    $self->logger->info("First upgrading to $starting_lts_version before upgrading to final version.");
    $self->{target_version} = $starting_lts_version;

    return 1;
}

=item B<next_lts_before_target>

Dermine if we need to upgrade to a neighbor tier before trying to upgrade to the ultimate target_version.

=cut

sub next_lts_before_target {
    my $self = shift         or die;
    ref $self eq __PACKAGE__ or die("Must be called as a method");

    my $starting_version = $self->starting_version;    # We can assume this is an LTS or better version
    my $target_version   = $self->target_version;

    my $next_lts_version = $self->tiers->get_lts_for( $starting_version, 1 ) or return 0;

    my $target_major   = Cpanel::Version::Compare::get_major_release($target_version);
    my $next_lts_major = Cpanel::Version::Compare::get_major_release($next_lts_version);

    return 0 if ( Cpanel::Version::Compare::compare( $target_major, '<=', $next_lts_major ) );

    $self->{target_version} = $next_lts_version;
    $self->logger->info("Upgrade requested to a version more than 1 LTS away. Will upgrade to next LTS first ($next_lts_version).");

    return 1;
}

sub try_update_to_main {
    my $self = shift         or die;
    ref $self eq __PACKAGE__ or die("Must be called as a method");

    # --upgrade_to_main was already passed. There's no reason to try it again.
    return 1 if $self->{'upgrade_to_main'};

    # The updatenow logic is significantly different below 76. It can't support --upgrade_to_main
    my $starting_major = Cpanel::Version::Compare::get_major_release( $self->starting_version );
    return 2 if Cpanel::Version::Compare::compare( $starting_major, '<', '11.78' );

    # Don't upgrade to main when CPANEL==11.76.0.3
    return 3 if $self->tiers->is_explicit_version( $self->tiers->get_current_tier );

    # Get the main version for us and return if we can't determine it.
    my $try_version = $self->tiers->get_main_for_version( $self->starting_version ) or return 4;

    # make sure that try_version is greater than our current version.
    return 5 unless Cpanel::Version::Compare::compare( $try_version, '>', $self->starting_version );

    # Tell the customer what we're going to do.
    $self->logger->info("An attempt to upgrade to $self->{target_version} was blocked. Attempting to upgrade to the latest $starting_major version ($try_version).");

    # At the moment upgrade_to_main is a boolean value. We're setting it to the explicit version as it might be needed in the future.
    $self->{'upgrade_to_main'} = $self->target_version($try_version);

    $self->become_a_new_updatenow();    #exec.

    return;                             # Unreachable code.
}

=item B<can_update>

Decides if the target_version is reachable. Exits with an appropriate exit code if checkremoteversion is set.

=cut

sub can_update {
    my $self = shift         or die;
    ref $self eq __PACKAGE__ or die("Must be called as a method");

    # If the env set is our target version then a previous updatenow instance already blessed us.
    # So there's no need to check.
    if ( $ENV{'UPDATE_IS_ALLOWED'} && $ENV{'UPDATE_IS_ALLOWED'} eq $self->target_version ) {
        $self->logger->debug("\$ENV{UPDATE_IS_ALLOWED} = $ENV{UPDATE_IS_ALLOWED}");
        return 1;
    }

    # Create a blocker object, used regardless of version change type.
    my $blocker_object = Cpanel::Update::Blocker->new(
        {
            'logger'           => $self->logger,
            'starting_version' => $self->starting_version,
            'target_version'   => $self->target_version,
            'upconf_ref'       => $self->upconf,
            'tiers'            => $self->tiers,
            'force'            => $self->{'force'},
        }
    );

    $blocker_object->is_upgrade_blocked();

    # Try the local LTS if blocked to my tier's target.
    if ( $blocker_object->is_fatal_block() ) {

        # We still want to upgrade to is_main for our major version if we were blocked getting to another major version.
        $self->try_update_to_main();

        $self->logger->warning("An attempt to upgrade to $self->{target_version} was blocked. Please review blockers.");
        die( { 'exit' => 0, 'remove_blocker_file' => 0, 'message' => "An attempt to upgrade to $self->{target_version} was blocked. Please review blockers." } );
    }

    if ( $self->{'checkremoteversion'} ) {
        $self->logger->info("$self->{target_version} is available for update.");
        die( { 'exit' => $self->{'update_is_available_exit_code'}, 'remove_blocker_file' => 1, 'message' => "$self->{target_version} is available for update.", 'success' => 1 } );
    }

    $ENV{'UPDATE_IS_ALLOWED'} = $self->target_version;
    return 2;
}

=item B<_current_updatenow_version>

Tracks the version of the current running updatenow

=cut

sub _current_updatenow_version { return $Cpanel::Version::Tiny::VERSION_BUILD }

sub target_version {
    my ( $self, $val ) = @_;
    $self                    or die;
    ref $self eq __PACKAGE__ or die("Must be called as a method");

    $self->{'target_version'} = $val if ( scalar @_ == 2 );
    return $self->{'target_version'};
}

sub starting_version {
    my ( $self, $val ) = @_;
    $self                    or die;
    ref $self eq __PACKAGE__ or die("Must be called as a method");

    $self->{'starting_version'} = $val if ( scalar @_ == 2 );
    return $self->{'starting_version'};
}

=item B<become_a_new_updatenow>

In charge of downloading and becoming a new version of updatenow.

=cut

sub become_a_new_updatenow {
    my ( $self, %opts ) = @_;
    $self                    or die;
    ref $self eq __PACKAGE__ or die("Must be called as a method");

    my $target_version = $self->target_version;
    if ( !$target_version ) {
        $self->logger->fatal("The target version not passed to become_a_new_updatenow");
        die( { 'exit' => 1, 'remove_blocker_file' => 0, 'message' => "The target version not passed to become_a_new_updatenow" } );
    }

    return 0 if ( $self->_current_updatenow_version eq $target_version );

    my $skip_signature_check = int( Cpanel::Version::Compare::get_major_release( $self->target_version ) <= 11.48 );
    my $static_script;

    if ( $self->dry_run() ) {
        $self->logger->debug( 'Cpanel::Sync::v2->new( ' . $target_version . ', ' . $self->{'ulc'} . ' )->sync_updatenow_static(' . $skip_signature_check . ');' );
        $self->logger->debug( q{exec(/scripts/updatenow.static } . join( ' ', $self->rebuild_argv ) . ')' );

        # Special majic to fake that we've downloaded and become the new version.
        $Cpanel::Version::Tiny::VERSION_BUILD = $target_version;
        return;
    }

    eval { $static_script = $self->cpanel->sync_updatenow_static($skip_signature_check) };

    if ( !$static_script ) {
        my $error_as_string = Cpanel::Exception::get_string($@);
        $self->logger->fatal("Failed to download updatenow.static from server: $error_as_string");
        die( { 'exit' => 0, 'remove_blocker_file' => 0, 'message' => "Failed to download updatenow.static from server: $error_as_string" } );
    }

    my $tmp          = Cpanel::TempFile->new( { path => q{/var/cpanel} } );
    my $tmp_cpupdate = $tmp->file;

    if ( $opts{'use_target_updatenow.static'} ) {
        $self->logger->info( 'Use target updatenow.static version: ' . $target_version );

        # create a temporary update.conf with a fake target ( next LTS )
        $self->create_temporary_update_conf( $tmp_cpupdate, $target_version );

        # update updatenow.static script with the temporary update.conf file
        $self->update_script_with_update_conf( $static_script, $tmp_cpupdate );

    }
    else {

        # The temp file is not used since we are not using it as an alternate update.conf file
        $tmp->cleanup();
    }

    if ( !chmod( 0700, $static_script ) ) {
        $self->logger->fatal("Could not set downloaded updatenow.static to executable");
        die( { 'exit' => 0, 'remove_blocker_file' => 0, 'message' => "Could not set downloaded updatenow.static to executable" } );
    }

    $self->logger->info( 'Become an updatenow.static for version: ' . $target_version );

    # Close the log.
    $self->logger->close_log();

    # Exec into the downloaded script.
    if ( !exec( $static_script, $self->rebuild_argv ) ) {
        my $why = $!;
        my $msg = "Failed to run downloaded $static_script ($!)";
        $self->logger->fatal($msg);
        die( { 'exit' => 0, 'remove_blocker_file' => 0, 'message' => $msg } );
    }

    # Should never be able to get here (exec above)
    die( { 'exit' => 99, 'remove_blocker_file' => 0 } );
}

sub update_script_with_update_conf {
    my ( $self, $script, $tmp_cpupdate ) = @_;
    $self                    or die;
    ref $self eq __PACKAGE__ or die("Must be called as a method");

    my $fh   = IO::Handle->new();
    my $lock = Cpanel::SafeFile::safeopen( $fh, '+<', $script ) or do {
        $self->logger->fatal("Failed to open updatenow.static");
        die( { 'exit' => 0, 'remove_blocker_file' => 0, 'message' => "Failed to open updatenow.static" } );
    };
    my @lines = <$fh>;
    seek( $fh, 0, 0 );
    foreach my $line (@lines) {

        # very naive regexp which does the job
        $line =~ s{/etc/cpupdate.conf([,\s'"\}\)])}{$tmp_cpupdate$1};
        print {$fh} $line;
    }
    truncate( $fh, tell($fh) );
    Cpanel::SafeFile::safeclose( $fh, $lock );

    return;
}

sub create_temporary_update_conf {
    my ( $self, $tmp_cpupdate, $target_version ) = @_;
    $self                    or die;
    ref $self eq __PACKAGE__ or die("Must be called as a method");

    my @cpupdate_conf;
    {
        my $fh   = IO::Handle->new();
        my $lock = Cpanel::SafeFile::safeopen( $fh, '<', $Cpanel::Update::Config::cpanel_update_conf ) or do {
            $self->logger->fatal("Failed to open update.conf");
            die( { 'exit' => 0, 'remove_blocker_file' => 0, 'message' => "Failed to open update.conf" } );
        };
        @cpupdate_conf = <$fh>;
        Cpanel::SafeFile::safeclose( $fh, $lock );
    }
    {
        my $fh   = IO::Handle->new();
        my $lock = Cpanel::SafeFile::safeopen( $fh, '>', $tmp_cpupdate ) or do {
            $self->logger->fatal("Failed to open temporary update.conf: '$tmp_cpupdate'");
            die( { 'exit' => 0, 'remove_blocker_file' => 0, 'message' => "Failed to open temporary update.conf: '$tmp_cpupdate'" } );
        };
        foreach my $line (@cpupdate_conf) {
            if ( $line =~ m/^CPANEL=/ ) {
                $line = 'CPANEL=' . $target_version . "\n";
            }
            print {$fh} $line;
        }
        Cpanel::SafeFile::safeclose( $fh, $lock );
    }

    return;
}

=item B<validate_config>

This method is here to analyze the options the object was created with to look for
any undesireable / unsupported combination of features. It will throw a die object
if it sees such a case.

=cut

sub validate_config {
    my $self = shift         or die;
    ref $self eq __PACKAGE__ or die("Must be called as a method");

    unless ( $self->{'force'} or $self->{'sync'} or Cpanel::Update::Config::is_permitted( 'UPDATES', $self->upconf() ) ) {
        if ( $self->upconf->{'UPDATES'} eq 'never' ) {
            $self->logger->info('cPanel & WHM updates are disabled.');
        }
        if ( $self->upconf->{'UPDATES'} eq 'manual' ) {
            $self->logger->info('cPanel & WHM updates are disabled via cron because they are set to “manual” in /etc/cpupdate.conf');
        }

        $self->logger->info("No sync will occur.");

        # Do not remove the blocker file if we're blocked because of cron and local settings.
        die( { 'exit' => 0, 'remove_blocker_file' => 0 } );
    }

    # Must call the program with at least --upcp, --force, or --sync, or --checkremoteversion
    unless ( $self->{'checkremoteversion'} or $self->{'force'} or $self->{'sync'} or $self->{'upcp'} ) {
        $self->logger->fatal("This script is not designed to be called directly. Please use /usr/local/cpanel/scripts/upcp");
        die( { 'exit' => 1, 'remove_blocker_file' => 0, 'message' => "This script is not designed to be called directly. Please use /usr/local/cpanel/scripts/upcp" } );
    }

    # Prevent flags from accompanying checkremoteversion
    if ( $self->{'checkremoteversion'} && ( $self->{'force'} or $self->{'sync'} or $self->{'upcp'} ) ) {
        $self->logger->fatal("--checkremoteversion is not designed to be called with other flags.");
        die( { 'exit' => 1, 'remove_blocker_file' => 0, 'message' => "--checkremoteversion is not designed to be called with other flags." } );
    }

    # Prevent force and sync being passed at the same time.
    if ( $self->{'force'} && $self->{'sync'} ) {
        $self->logger->fatal("--force and --sync are mutually exclusive commands. Force is designed to update your installed version, regardless of whether it's already up to date. Sync is designed to update the version already installed, regardless of what is available.");
        die( { 'exit' => 1, 'remove_blocker_file' => 0, 'message' => "--force and --sync are mutually exclusive commands. Force is designed to update your installed version, regardless of whether it's already up to date. Sync is designed to update the version already installed, regardless of what is available." } );
    }

    $self->logger->info("--sync passed on command line. No upgrade will be allowed")
      if ( $self->{'sync'} );
    $self->logger->info("--force passed on command line. Upgrade will disregard update config settings.")
      if ( $self->{'force'} );

    return 1;
}

=item B<_version_is_invalid>

returns true/false if the passed version is a valid 3 dotted cpanel version number

=cut

sub _version_is_invalid {
    my $version = shift or return 1;

    return 0 if ( $version =~ m{^\d+\.\d+\.\d+\.\d+$} );

    return 1;
}

=item B<set_tier_or_sync_version>

Sets the target_version, based on command line (new) configuration
Mostly cares if --sync was passed.

=cut

sub set_tier_or_sync_version {
    my $self = shift         or die;
    ref $self eq __PACKAGE__ or die("Must be called as a method");

    # Determine new_version
    if ( $self->{'sync'} ) {
        $self->target_version( $self->starting_version );
        $self->logger->info("Setting target version to '$self->{target_version}' for --sync");
        return 1;
    }

    if ( $self->{'upgrade_to_main'} ) {
        if ( $self->tiers->is_explicit_version( $self->tiers->get_current_tier ) ) {
            die( { 'exit' => 1, 'remove_blocker_file' => 0, 'message' => "--upgrade_to_main passed when an explicit version was set in /etc/cpupdate.conf" } );
        }

        $self->logger->info("--upgrade_to_main=$self->{upgrade_to_main} passed on on command line");
        my $try_version = $self->tiers->get_main_for_version( $self->starting_version );
        $try_version or die( { 'exit' => 1, 'remove_blocker_file' => 0, 'message' => "could not determine 'is_main' version for $self->{starting_version}" } );
        $self->target_version($try_version);
        return 5;
    }

    $self->set_target_from_current_tier();

    # Just set start to target if we're installing.
    if ( $ENV{'CPANEL_BASE_INSTALL'} && !$self->starting_version ) {
        $self->starting_version( $self->target_version );
        $self->{'initial_install'} = 1;
        $self->logger->info("Initial cPanel installation detected as in progress.");
        return 2;
    }

    # updatenow should not exit when it detects being up to date if upgrade_in_progress.txt is present so partially completed updatenow runs can be completed
    return 3 if ( -e $self->get_upgrade_in_progress_lock_file_name() );

    # No action required if our version number matches the httpupdate TIERS.json file.
    if ( !$self->{'force'} && ( $self->target_version eq $self->starting_version ) ) {
        $self->logger->info("Up to date ($self->{starting_version})");
        die( { 'exit' => 0, 'remove_blocker_file' => 1, 'message' => "Up to date ($self->{starting_version})", success => 1 } );
    }

    return 4;
}

sub get_upgrade_in_progress_lock_file_name {
    my $self = shift         or die;
    ref $self eq __PACKAGE__ or die("Must be called as a method");

    return '/usr/local/cpanel/upgrade_in_progress.txt';
}

=item B<set_target_from_current_tier>

Looks at the remote tier and sets it to the tier that corresponds to CPANEL in cpupdate.conf

=cut

sub set_target_from_current_tier {
    my $self = shift         or die;
    ref $self eq __PACKAGE__ or die("Must be called as a method");

    my $target_tier = $self->tiers->get_current_tier() || '';

    my $target_tier_version = $self->tiers->get_remote_version_for_tier($target_tier);
    if ( !$target_tier_version ) {
        $self->logger->fatal("The version for tier '$target_tier' is not defined!");
        die( { 'exit' => 0, 'remove_blocker_file' => 0, 'message' => "The version for tier '$target_tier' is not defined!" } );
    }

    # Disabled tier handling is different for installs vs updates.
    if ( $ENV{'CPANEL_BASE_INSTALL'} && $target_tier_version eq 'disabled' ) {
        $target_tier_version = $self->tiers->get_remote_version_for_tier('install-fallback');

        # If we don't have an install-fallback tier.
        if ( !$target_tier_version ) {
            my $msg = "The tier '$target_tier' is currently disabled and no install-fallback exists!";
            $self->logger->fatal($msg);
            die( { 'exit' => 0, 'remove_blocker_file' => 0, 'message' => $msg } );
        }

        $self->logger->warning("$target_tier is currently disabled. Falling back to $target_tier_version for fresh installs.");
    }
    elsif ( $target_tier_version eq 'disabled' ) {
        $self->logger->warn("cPanel has temporarily disabled updates on the central httpupdate servers. Please try again later.");
        die( { 'exit' => 0, 'remove_blocker_file' => 0, 'message' => "cPanel has temporarily disabled updates on the central httpupdate servers. Please try again later." } );
    }

    # If the tier is actually a version.
    if ( $target_tier_version eq $target_tier ) {
        $self->logger->warning("version explicitly hardcoded to CPANEL=$target_tier in /etc/cpupdate.conf");
    }
    else {
        $self->logger->info("Target version set to '$target_tier_version'");
    }

    return $self->target_version($target_tier_version);
}

=item B<get_binary_sync_source>

Provides the string corresponding to the binary sync source directory.

=cut

sub get_binary_sync_source ($self) {

    return 'binaries/' . Cpanel::OS::binary_sync_source();

}

=item B<stage_files>

Download all files needed to upgrade to a temp location before making any changes to /usr/local/cpanel

=cut

sub stage_files {
    my $self = shift         or die;
    ref $self eq __PACKAGE__ or die("Must be called as a method");

    $self->logger->info( "Staging " . $self->target_version . " cpanelsync files prior to updating $self->{'staging_dir'}" );

    my $is_fresh_install = $ENV{'CPANEL_BASE_INSTALL'} ? 1 : 0;

    my %stage_opts_tree;
    foreach my $source ( 'cpanel', Cpanel::Themes::Get::get_list() ) {
        $stage_opts_tree{$source} = { no_download => $is_fresh_install };
    }

    # The install now calls upcp after updatenow so we don't want to do this twice
    my $tarball_download_pid;

    if ( $self->{firstinstall} ) {
        $self->logger->info('Staging first installation tarballs');
        my $tarbin = Cpanel::Binaries::path('tar');
        -x $tarbin or die( { 'exit' => 7, 'remove_blocker_file' => 1, 'message' => "Cannot find tar binary" } );

        my $want_cpanel              = !$self->cpanel()->already_done() ? 1 : 0;
        my $want_locale              = !-d '/var/cpanel/locale';
        my $needs_at_least_one_theme = grep { !$self->get_theme_synctree($_)->already_done() } Cpanel::Themes::Get::get_list();
        my $want_theme               = !$self->{'dnsonly'} && $needs_at_least_one_theme;
        my @tarballs;

        # if we are missing files from the cpanel or locale sync trees, we need to fetch the install/common tree #
        # and extract the missing subtrees; note that install/common contains both cpanel and locale #
        if ( $want_cpanel || $want_locale ) {
            if ($want_cpanel) {
                push @tarballs,
                  {
                    file   => q{cpanel.tar.xz},
                    syncto => '/',
                    from   => _install_common_root()
                  };
                $self->logger->debug('cpanel tarball will be staged and installed');
            }
            else {
                delete $stage_opts_tree{'cpanel'}->{'no_download'};
                $self->logger->debug('cpanel tarball is not required');
            }

            # install/common contains both cpanel and locale subtrees, we're getting both regardless of what we #
            # need because they're in the same tree #
            $self->call_stage( 'sync_target' => 'install_common', 'failure_exit_code' => 8 );
            $self->install_common->commit();
        }
        else {
            $self->logger->debug('cpanel and locale tarballs are not required');
        }

        # We need to extract the cpanel tarball so etc/rpm.versions is
        # available
        $self->_extract_tarballs( $tarbin, \@tarballs ) if @tarballs;
        @tarballs = ();

        if ( $want_locale || $want_theme ) {

            # Since locale and themes are not required to stage
            # RPMs so we can do this in the background
            $tarball_download_pid = Cpanel::ForkAsync::do_in_child(
                sub {
                    if ($want_locale) {
                        push @tarballs, {
                            file     => q{locale.tar.xz},         # cdb are no arch dependent...
                            syncto   => '/var/cpanel/locale',
                            absolute => 1,
                            from     => _install_common_root(),
                        };
                        $self->logger->debug('locale tarball will be staged and installed');
                    }
                    else {
                        $self->logger->debug('locale tarball is not required');
                    }

                    $self->logger->debug("detected $needs_at_least_one_theme theme tarballs that will be staged and installed");
                    if ($want_theme) {
                        $self->call_stage( 'sync_target' => 'install_themes', 'failure_exit_code' => 9 );
                        $self->install_themes->commit();
                        foreach my $theme ( Cpanel::Themes::Get::get_list() ) {
                            if ( !$self->get_theme_synctree($theme)->already_done() ) {
                                push @tarballs, {
                                    file   => qq{$theme.tar.xz},
                                    syncto => _theme_root_for($theme),
                                    from   => _install_themes_root(),
                                };
                                $self->logger->debug("$theme tarball will be staged and installed");
                            }
                            else {
                                delete $stage_opts_tree{$theme}->{'no_download'};
                                $self->logger->debug("$theme tarball will not be staged and installed");
                            }
                        }
                    }
                    else {
                        $self->logger->debug("no theme tarballs are required");
                    }

                    $self->_extract_tarballs( $tarbin, \@tarballs );
                    Cpanel::SafeDir::RM::safermdir( $self->{ulc} . '/firstinstall' );
                }
            );
        }
        else {
            Cpanel::SafeDir::RM::safermdir( $self->{ulc} . '/firstinstall' );

        }
    }

    # Make sure the 'cpanel' sync objects are aware that they are sharing
    # the responsibility of staging files under base, so it will not be possible to simply
    # rename base-cpanelsync to base. The dirs underneath will need their own stage suffixes.
    # See CPANEL-30053 and BWG-1666 for more info on this.
    if ( $self->{using_custom_staging_dir} ) {
        Cpanel::SafeDir::MK::safemkdir( $self->{'staging_dir'} . '/base/frontend', 0755 );
    }

    # Download /ULC noarch and binary sources.
    $self->call_stage( 'sync_target' => 'cpanel', 'failure_exit_code' => 12, 'message' => 'cpanel changes', 'stage_opts' => $stage_opts_tree{'cpanel'} );

    # setup RPMs targets before downloading RPMs
    $self->setup_rpms_targets();

    my $max_num_of_sync_children_this_system_can_handle = $self->cpanel()->calculate_max_sync_children();

    # Download rpms
    $self->call_stage(
        'message'           => 'new packages', 'sync_target' => 'rpms', 'failure_exit_code' => 13, 'help_message' => 'see https://go.cpanel.net/rpmcheckfailed for more information',
        'max_sync_children' => $max_num_of_sync_children_this_system_can_handle
    );

    _waitpid($tarball_download_pid) if $tarball_download_pid;

    # always download binaries for now: this would require an extra space of ~2Go per build to provide tarballs
    if ($is_fresh_install) {
        $self->call_stage( 'sync_target' => 'binaries', 'failure_exit_code' => 12, 'message' => 'cpanel binaries changes' );
    }

    # Only download themes if not dnsonly
    if ( !$self->{'dnsonly'} ) {

        # could also only download the default theme
        foreach my $theme ( Cpanel::Themes::Get::get_list() ) {
            $self->call_stage( message => qq{$theme theme changes}, 'sync_object' => $self->get_theme_synctree($theme), 'failure_exit_code' => 10, 'stage_opts' => $stage_opts_tree{$theme} );
        }
    }

    $self->logger->info("All files Staged");

    return;
}

sub _waitpid {
    my ($pid) = @_;
    return waitpid( $pid, 0 );
}

sub _extract_tarballs {
    my ( $self, $tarbin, $tarballs_ar ) = @_;
    foreach my $tb (@$tarballs_ar) {
        my $file = $self->{ulc} . '/' . $tb->{from} . '/' . $tb->{file};
        $self->logger->info( 'Extracting files from ' . $tb->{file} );
        my $extract_to = $self->{ulc} . '/' . $tb->{syncto};
        $extract_to = $tb->{syncto} if $tb->{absolute};
        Cpanel::SafeDir::MK::safemkdir( $extract_to, 0755 );
        system( $tarbin, '-x', '--no-same-owner', '--overwrite-dir', '-p', '--directory=' . $extract_to, '-f', $file, qw{ --use-compress-program xz } ) == 0
          or die( { 'exit' => 9, 'remove_blocker_file' => 1, 'message' => "Failed to extract tarball " . $tb->{file} } );
    }
    return;
}

sub call_stage {
    my ( $self, %OPTS ) = @_;
    $self                    or die;
    ref $self eq __PACKAGE__ or die("Must be called as a method");

    my $sync_target       = $OPTS{'sync_target'};
    my $message           = $OPTS{'message'} || $sync_target;
    my $sync_object       = $OPTS{'sync_object'};
    my $failure_exit_code = $OPTS{'failure_exit_code'};
    my $help_message      = $OPTS{'help_message'};
    my $max_sync_children = $OPTS{'max_sync_children'};
    my $suppress_message  = $OPTS{'suppress_message'};          # Remove this flag in 11.52, its only here to preserve 11.50 behavior
    my $stage_opts        = $OPTS{'stage_opts'} || {};
    my ( $ret, $err );

    $self->logger->info("Staging $message") unless $suppress_message;

    try {
        $sync_object ||= $self->$sync_target();
        $ret = $sync_object->stage(%$stage_opts);
    }
    catch {
        $err = $_;
    };

    if ( $err || !$ret ) {
        my $log_message = "Failed to stage “$message”" . ( $err ? " because of an error: " . Cpanel::Exception::get_string($err) : '' ) . ( $help_message ? " : $help_message" : '' );
        $self->logger->fatal($log_message);
        die( { 'exit' => $failure_exit_code, 'remove_blocker_file' => 1, 'message' => $log_message } );
    }

    # Uncomment for 11.52 or later (left commented to keep test changes smaller)
    # $self->logger->info("Completed staging $message");
    return 1;
}

=item B<install_files>

Install the files now they're all local and tested.

=cut

my $monitoring_disabled_from;
my @run_on_sevice_restore;

sub disable_services {
    my ( $self, $need_rpms_update ) = @_;

    $self                    or die;
    ref $self eq __PACKAGE__ or die("Must be called as a method");

    return if $ENV{'CPANEL_BASE_INSTALL'};    # nothing do do
    return if $self->dry_run();

    # We need to disable the monitoring before updating restartsrv scripts (chkservd internal engine might change)

    # 1/ we want to stop tailwatch, which will let chkservd finish if it's in the middle of a run #
    #   NOTE: this is a hard stop in case a graceful restart prevents unloading of the code #
    # 2/ then we want to suspend it #
    # 3/ and start it back up in case we explode before being able to activate new logic below #

    my @services_to_suspend = (
        {
            'name'           => q[tailwatchd],
            'restart_script' => '/usr/local/cpanel/scripts/restartsrv_tailwatchd',
            'custom_stop'    => sub {
                my ($service) = @_;
                die unless ref $service;

                if ( !Cpanel::Signal::send_usr1_tailwatchd() ) {
                    system(qq{$service->{restart_script} --stop --no-verbose 2>&1 | grep -v 'service is disabled'});
                }
                return;
            }
        },
        {
            'name'           => q[queueprocd],
            'restart_script' => '/usr/local/cpanel/scripts/restartsrv_queueprocd',

            # no need to stop queueprocd if no RPMs are updated
            'only_on_rpm_update' => 1,
        },
    );

    my $has_disabled_monitoring;

    foreach my $service (@services_to_suspend) {

        # do not stop the service when no RPMs are updated (old binary has no XS issues)
        next if $need_rpms_update && $service->{only_on_rpm_update};

        # check if the service was running, or ignore it
        my $service_status = qx{$service->{restart_script} --status 2>/dev/null} // '';    ## no critic qw(Cpanel::ProhibitQxAndBackticks)
        chomp($service_status);
        next unless $service_status =~ m/\brunning.+?PID\b/;

        # only disable checkservd if we have to stop one of the service
        if ( !$has_disabled_monitoring ) {
            $has_disabled_monitoring = 1;                                                  # disable checksrvd once

            $self->logger->info("Disabling service monitoring during update.");
            $monitoring_disabled_from = $$;

            # protection when something wrong happens
            #   whatever was the state of the suspend file on start,
            #   we restore the service and remove the suspend file
            eval q{ END { restore_services() } };    ## no critic qw(ProhibitStringyEval)

            Cpanel::FileUtils::TouchFile::touchfile('/var/run/chkservd.suspend');
        }

        $self->logger->info("    Stopping service '$service->{name}'.");
        if ( ref $service->{'custom_stop'} eq 'CODE' ) {
            $service->{'custom_stop'}->($service);
        }
        else {
            system(qq{$service->{restart_script} --stop --no-verbose 2>&1});
        }

        # run when restoring services
        push @run_on_sevice_restore,    # .
          qq[$service->{restart_script} --no-verbose 2>&1 | grep -v 'service is disabled'];
    }

    return;
}

sub restore_services {

    # only the main PID is restoring chkservd
    return unless $monitoring_disabled_from && $monitoring_disabled_from == $$;

    # restart the services before restoring the monitoring
    # use reverse to bring queueprocd alive before tailwatchd (but stop them in the other order)
    foreach my $action ( reverse @run_on_sevice_restore ) {
        system($action );
    }
    @run_on_sevice_restore = ();

    unlink '/var/run/chkservd.suspend';    # restore monitoring

    return;
}

sub install_files {
    my $self = shift         or die;
    ref $self eq __PACKAGE__ or die("Must be called as a method");

    $self->logger->info("Putting cpanelsync files into place.");

    return if ( $self->dry_run() );

    my $ulc = $self->{'ulc'} or die;

    if ( !$ENV{'CPANEL_BASE_INSTALL'} ) {

        # no need to copy the file during a fresh installation

        if ( -e "$ulc/etc/.js_files_in_repo_with_mt_calls" ) {
            $self->logger->info("    Preserving previous JS files list.");
            my $rv = Cpanel::FileUtils::Copy::safecopy( "$ulc/etc/.js_files_in_repo_with_mt_calls", "$ulc/etc/.js_files_in_repo_with_mt_calls.prev" );
            unless ($rv) {
                $self->logger->warning("Copy of $ulc/etc/.js_files_in_repo_with_mt_calls to $ulc/etc/.js_files_in_repo_with_mt_calls.prev failed: $!");
            }
        }
    }

    # Put the arch and noarch files in place, along with newdir, newlinks and unlinks

    $self->logger->info("    Committing cpanel.");
    eval { $self->cpanel->commit(); 1; } or do {
        my $error_as_string = Cpanel::Exception::get_string($@);
        my $message         = 'Failed to commit cpanel changes';
        $self->logger->fatal("$message: “$error_as_string”.");
        die( { 'exit' => 14, 'remove_blocker_file' => 1, 'message' => "$message." } );
    };

    if ( $ENV{'CPANEL_BASE_INSTALL'} ) {
        $self->logger->info("    Committing cpanel binaries.");
        eval { $self->binaries->commit(); 1; } or do {
            my $error_as_string = Cpanel::Exception::get_string($@);
            my $message         = 'Failed to commit cpanel binary changes';
            $self->logger->fatal("$message: “$error_as_string”.");
            die( { 'exit' => 14, 'remove_blocker_file' => 1, 'message' => "$message." } );
        };
    }

    my $cpkeyclt_exit_code = 1;
    my $cpkeyclt           = $self->{'ulc'} . '/cpkeyclt';

    if ( !$ENV{'CPANEL_BASE_INSTALL'} ) {

        # activate any new logic that may have resulted from updates (disable state)
        #   let the service in a suspended state
        # skip if this is a fresh install, as tailwatchd is missing cPanel perl
        if ( !Cpanel::Signal::send_usr1_tailwatchd() ) {
            system(q{/usr/local/cpanel/scripts/restartsrv_tailwatchd --no-verbose 2>&1 | grep -v 'service is disabled'});
        }
        #
        # Since we call this code multiple times during fresh install we do not want to
        # increase the number of hits on their license as such we only call it once
        #

        $self->logger->info('    Updating cpanel license for new binaries. This call may fail and that is ok.');
        $cpkeyclt_exit_code = Cpanel::SafeRun::Object->new( 'program' => $cpkeyclt, 'args' => ['--force-no-tty-check'] )->CHILD_ERROR();
    }

    # Only download themes if not dnsonly
    if ( $self->{'dnsonly'} ) {
        $self->logger->info("    Removing x3 themes.");

        my $ulc = $self->{'ulc'} or die;
        for my $_dir ( Cpanel::Themes::Get::get_list() ) {
            my $dir_path = "$ulc/base/frontend/$_dir";
            if ( -e $dir_path ) {
                my $rv = Cpanel::SafeDir::RM::safermdir($dir_path);
                unless ($rv) {
                    $self->logger->warning("Removal of theme directory $dir_path failed!");
                }
            }
        }
    }
    else {
        $self->logger->info("    Committing cPanel themes.");
        foreach my $theme ( Cpanel::Themes::Get::get_list() ) {
            eval { $self->get_theme_synctree($theme)->commit(); 1; } or do {
                my $error_as_string = Cpanel::Exception::get_string($@);
                my $message         = "Failed to commit $theme theme changes";
                $self->logger->fatal("$message: “$error_as_string”.");
                die( { 'exit' => 15, 'remove_blocker_file' => 1, 'message' => "$message." } );
            };
        }
    }

    $self->logger->info("    Updating / Removing packages.");
    eval { $self->rpms->commit_changes(); 1; } or do {
        my $error_as_string = Cpanel::Exception::get_string($@);
        $self->logger->fatal("Error committing changes: $error_as_string  see https://go.cpanel.net/rpmcheckfailed for more information");
        die( { 'exit' => 17, 'remove_blocker_file' => 1, 'message' => "Error committing changes: $error_as_string  see https://go.cpanel.net/rpmcheckfailed for more information" } );
    };

    if ($cpkeyclt_exit_code) {
        $self->logger->info('    Updating cpanel license for new binaries.');
        $cpkeyclt_exit_code = system( $cpkeyclt, '--force-no-tty-check' );
        $cpkeyclt_exit_code and $self->logger->warn("Received unexpected exit code ($cpkeyclt_exit_code) from $cpkeyclt");
    }

    # restore chkservd after RPM transaction ( not before )
    $self->logger->info('    Restoring service monitoring.');
    unlink '/var/run/chkservd.suspend';

    if ( !$ENV{'CPANEL_BASE_INSTALL'} && !Cpanel::Signal::send_hup_tailwatchd() ) {

        # implicitly attempt to start tailwatchd because we may be in a situation that upcp has failed multiple times #
        # if it's disabled, the restartsrv script will simply fail out (and we'll scrub that from the log) #
        system(q{/usr/local/cpanel/scripts/restartsrv_tailwatchd --no-verbose 2>&1 | grep -v 'service is disabled'});
    }

    $self->logger->info("All files have been updated.");

    return;
}

=item B<make_cpanelsync_object>

Private function to create the Cpanel::Sync::v2 objects needed for each sync target.

Currently the target list is (cpanel/binaries), x3, x3mail.

=cut

sub make_cpanelsync_object {
    my $self = shift         or die;
    ref $self eq __PACKAGE__ or die("Must be called as a method");

    my $source = shift     or die;
    ref $source eq 'ARRAY' or die;
    my $sync_to = shift || '';
    my $options = shift || {};

    # This sub should never get called without some sort of target. If it does, we'll inject something to make the sync fail in a more obvious sort of way.
    my $target_version = $self->target_version || 'no_target';

    my $staging_dir = $self->{'staging_dir'} or die;

    # Base options we always use to sync with.
    my %object_parameters = (
        'url'         => 'http://' . $self->cpsrc->{'HTTPUPDATE'} . '/cpanelsync/' . $target_version,
        'logger'      => $self->logger,
        'source'      => $source,
        'syncto'      => $staging_dir . ( $sync_to ? "/$sync_to" : '' ),
        'force'       => $self->{'force'},                                                              # Skip md5sum cache files if true.
        'staging_dir' => $self->{'staging_dir'},
        'ulc'         => $self->{'ulc'},
        'http_client' => $self->_http_client(),
        'options'     => $options,
    );

    my $object = Cpanel::Sync::v2->new( {%object_parameters} );
    ( $object && ref $object eq 'Cpanel::Sync::v2' ) or die("Can't create sync object for $source->[0]");
    return $object;
}

# cpanel on fresh install
sub _install_common_root {
    return "firstinstall/common";
}

sub install_common {
    my $self = shift         or die;
    ref $self eq __PACKAGE__ or die("Must be called as a method");

    $self->{'install_common_cpanelsync'} ||= $self->make_cpanelsync_object( ['install/common'], _install_common_root() );
    return $self->{'install_common_cpanelsync'};
}

sub _install_themes_root {
    return "firstinstall/themes";
}

# Jupiter on fresh install
sub install_themes {
    my $self = shift         or die;
    ref $self eq __PACKAGE__ or die("Must be called as a method");

    $self->{'install_themes_cpanelsync'} ||= $self->make_cpanelsync_object( ['install/themes'], _install_themes_root() );
    return $self->{'install_themes_cpanelsync'};
}

sub _theme_root_for {
    my $theme = shift or die;
    return "base/frontend/$theme";
}

# synctree for downloading a theme: jupiter
sub get_theme_synctree {
    my ( $self, $theme ) = @_;
    $self                    or die;
    ref $self eq __PACKAGE__ or die("Must be called as a method");

    my $cache_key = $theme . "_cpanelsync";

    $self->{$cache_key} ||= $self->make_cpanelsync_object( [$theme], _theme_root_for($theme) );
    return $self->{$cache_key};
}

=item B<cpanel>

Return or create and return the cpanel noarch cpanelsync object.

=cut

sub cpanel {
    my $self = shift         or die;
    ref $self eq __PACKAGE__ or die("Must be called as a method");

    if ( $ENV{'CPANEL_BASE_INSTALL'} ) {
        $self->{'cpanel_cpanelsync'} ||= $self->make_cpanelsync_object( ['cpanel'] );
    }
    else {
        $self->{'cpanel_cpanelsync'} ||= $self->make_cpanelsync_object( [ $self->get_binary_sync_source(), 'cpanel' ], undef, { 'ignore_xz' => 1 } );
    }

    return $self->{'cpanel_cpanelsync'};
}

sub binaries {
    my $self = shift         or die;
    ref $self eq __PACKAGE__ or die("Must be called as a method");

    $self->{'cpanelbinaries_cpanelsync'} ||= $self->make_cpanelsync_object( [ $self->get_binary_sync_source() ] );
    return $self->{'cpanelbinaries_cpanelsync'};
}

=item B<rpms>

Return or create and return the RPM management object (Cpanel::RPM::Versions::File)

=cut

sub rpms {
    my $self = shift         or die;
    ref $self eq __PACKAGE__ or die("Must be called as a method");

    return $self->{'rpm_manager'} if $self->{'rpm_manager'};

    my $rpm_versions_destination = $Cpanel::ConfigFiles::RpmVersions::RPM_VERSIONS_FILE;
    $self->{'new_rpm_versions_file'} ||= $self->cpanel()->get_staged_file($rpm_versions_destination);
    if ( $ENV{'CPANEL_BASE_INSTALL'} ) {
        $self->{'new_rpm_versions_file'} = $rpm_versions_destination;
    }

    # we are only going to merge one time, as we cache the object
    if ( $ENV{'CPANEL_BASE_INSTALL'} ) {
        my $config_defaults_file = $self->{'ulc'} . '/etc/cpanel.config';

        # avoid errors when the file is missing
        if ( defined $config_defaults_file && -e $config_defaults_file ) {
            Cpanel::Config::Merge::files(
                defaults_file => $config_defaults_file,
                config_file   => $self->{'cpanel_config_file'},
                logger        => $self->logger(),
            );
        }
    }

    # Fall back to what's already there.
    $self->{'new_rpm_versions_file'} ||= $rpm_versions_destination;
    $self->{'new_rpm_versions_file'} = $rpm_versions_destination if !-e $self->{'new_rpm_versions_file'};

    $self->{'rpm_manager'} = Cpanel::RPM::Versions::File->new(
        {
            'file'         => $self->{'new_rpm_versions_file'},
            'logger'       => $self->logger(),
            'temp_dir'     => $self->{'staging_dir'} . '/rpm_downloads',
            'firstinstall' => $self->{firstinstall},
            'http_client'  => $self->_http_client(),
        }
    );
    return $self->{'rpm_manager'};
}

=item B<cleanup_owned_objects>

This code is called during terminate to assure any objects that need cleanup are cleaned up prior to global destruction.

=cut

sub cleanup_owned_objects {
    my $self = shift         or die;
    ref $self eq __PACKAGE__ or die("Must be called as a method");

    delete $self->{'_http_client'};

    # Destroy all our cpanelsync objects so they don't shut down in global destruction.
    foreach my $key ( sort grep { m/_cpanelsync/ } keys %$self ) {
        delete $self->{$key};
    }

    return;
}

=item B<terminate>

Handle the eval trapping used throughout this module to exit and cleanup as desired.
This allows testing of all other subroutines which would otherwise need to exit and be untestable.

=cut

sub terminate {
    my $self = shift         or die;
    ref $self eq __PACKAGE__ or die("Must be called as a method");

    my $error = shift;

    # Make sure cpanelsync objects don't shut down in global destruction
    $self->cleanup_owned_objects();

    # If the log indicates there were errors, display a summary of the errors and notify.

    if ( $self->logger->get_need_notify ) {
        my $log    = $self->get_log_array_from_logger();
        my @errors = grep { /^\[\d+\.\d+\] (?:(?:\Q***** FATAL:\E)|(?:E)) / } @{$log};

        $self->notify();

        print "\nThere were errors when running updatenow:\n\n";
        print join( "\n", @errors ) . "\n\n" if @errors;
    }

    # We will retry on install, so it's not fatal.
    my $error_type = $ENV{'CPANEL_BASE_INSTALL'} ? 'an error' : 'a fatal error';

    # die({ 'exit' => 1, 'remove_blocker_file' => 0 });
    if ( ref($error) eq 'HASH' ) {
        my $blocker_file = Cpanel::Update::Blocker->update_blocks_fname;
        if ( $error->{'remove_blocker_file'} && -e $blocker_file ) {
            unlink $blocker_file;
        }
        if ( $error->{'message'} && !$error->{'success'} ) {
            $self->logger->error( "The install encountered $error_type: " . $error->{'message'} );
        }
        exit( $error->{'exit'} || 0 );
    }
    my $error_as_string = Cpanel::Exception::get_string($error);

    $self->logger->error( "The install encountered $error_type: " . ( $error_as_string || Carp::longmess() ) );

    die("$error_as_string\n");
}

=item B<notify>

Check if the logger indicates we need to nofiy and if so send out a message via iContact

=cut

sub notify {
    my $self = shift         or die;
    ref $self eq __PACKAGE__ or die("Must be called as a method");

    return if ( $self->dry_run() );
    return unless ( $self->logger->get_need_notify );

    # Notify if any major events happened worthy of notification.
    $self->logger->error("Detected events which require user notification during updatenow. Will send iContact the log");

    my $logger_ref = $self->get_log_array_from_logger();

    my $log = ref $logger_ref ? join( "\n", @$logger_ref ) : undef;

    if ( try( sub { Cpanel::LoadModule::load_perl_module("Cpanel::iContact::Class::Update::Now") } ) ) {

        # Remove URL from log output so it just goes to the blocker file.
        $self->send_icontact_class_notification($log);
    }
    else {

        # Remove URL from log output so it just goes to the blocker file.
        $self->send_icontact_noclass_notification($log);

    }

    return;
}

=item B<notify>

Read in all the lines we wrote to file (if there) and return it as an array ref with new lines stipped.

=cut

sub get_log_array_from_logger {
    my $self = shift         or die;
    ref $self eq __PACKAGE__ or die("Must be called as a method");

    # Purely used for testing to prevent temp files.
    return $self->logger->get_stored_log() if ( $self->logger->{'to_memory'} );

    # Short if we don't have a log file (testing?);
    return undef unless $self->{'log_file_path'} && -e $self->{'log_file_path'};

    $self->{'log_tell'} ||= 0;
    $self->logger->close_log();
    my $fh;
    if ( !open( $fh, '<', $self->{'log_file_path'} ) ) {
        warn "Failed to open log file: $self->{'log_file_path'}";
        return;
    }
    seek( $fh, $self->{'log_tell'}, 0 );

    # Read in all the lines and strip new lines.
    my @lines = <$fh>;
    $_ =~ s/\n$// foreach (@lines);

    return \@lines;
}

# separated to be able to be overridden during testing.
sub send_icontact_class_notification {
    my ( $self, $log ) = @_;
    $self                    or die;
    ref $self eq __PACKAGE__ or die("Must be called as a method");

    require Cpanel::Notify;
    return Cpanel::Notify::notification_class(
        'class'            => 'Update::Now',
        'application'      => 'Update::Now',
        'constructor_args' => [
            "origin"           => 'upcp',
            "host"             => Cpanel::Hostname::gethostname(),
            'starting_version' => $self->starting_version,
            'target_version'   => $self->target_version,
            'attach_files'     => [ { name => 'updatenow-failure-log.txt', content => \$log, number_of_preview_lines => 25 } ],
        ]
    );
}

sub send_icontact_noclass_notification {
    my ( $self, $log ) = @_;
    $self                    or die;
    ref $self eq __PACKAGE__ or die("Must be called as a method");

    my $msg = "An error was detected which prevented updatenow from completing normally.\n";
    $msg .= "Please review the enclosed log for further details\n";
    $msg .= "\n" . '-' x 100 . "\n\n";
    $msg .= $log;
    return Cpanel::iContact::icontact(
        'application' => 'upcp',
        'subject'     => 'cPanel update failure during updatenow',
        'message'     => $msg,
    );
}

=item B<_usage>

Helper subroutine for Cpanel::Usage

=cut

sub _usage {
    print qq{Usage: $0 [options]};
    print qq{

    Options:
      --help     Brief help message
      --man      Detailed help

     Note: This script is designed to be run by cPanel programs directly ONLY. Please see upcp instead. It's probably what you want.

};
    exit;
}

=item B<set_initial_starting_version>

Get local version from ulc/version

=cut

sub set_initial_starting_version {
    my $self = shift         or die;
    ref $self eq __PACKAGE__ or die("Must be called as a method");

    my $version = '';
    if ( open( my $fh, '<', $self->{'ulc'} . "/version" ) ) {
        $version = <$fh> || '';
        chomp $version;
        close $fh;
    }

    $self->logger->info("Detected version '$version' from version file.");

    if ( $ENV{'CPANEL_BASE_INSTALL'} && _version_is_invalid($version) ) {
        return $self->starting_version('');
    }

    # The only acceptable reason for no starting version is an installation.
    if ( _version_is_invalid($version) ) {

        # Attempt to guess via Cpanel::Version::Tiny.
        $self->logger->warning("Could not determine starting version from /usr/local/cpanel/version. Trying to guess starting version from Cpanel/Version/Tiny.pm");
        $version = $self->get_version_from_cv_tiny;

        # --sync needs a valid starting version)
        if ( _version_is_invalid($version) ) {
            $self->logger->fatal("Cannot determine a valid current cPanel & WHM version in order to sync. Please correct the contents of /usr/local/cpanel/version and re-try");
            die( { 'exit' => 1, 'remove_blocker_file' => 0, 'message' => "Cannot determine a valid current cPanel & WHM version in order to sync. Please correct the contents of /usr/local/cpanel/version and re-try" } );
        }
    }

    my $starting_major = Cpanel::Version::Compare::get_major_release($version);
    if ( Cpanel::Version::Compare::compare( $starting_major, '<', '11.68' ) ) {
        my $updatenow_version = $self->_current_updatenow_version();
        $self->block_from_updatenow( "Version $updatenow_version of updatenow cannot support upgrades starting from below version 11.68", 25 );
    }

    return $self->starting_version($version);
}

=item B<get_version_from_cv_tiny>

Get local version from ulc/Cpanel/Version/Tiny.pm

=cut

sub get_version_from_cv_tiny {
    my $self = shift         or die;
    ref $self eq __PACKAGE__ or die("Must be called as a method");

    open( my $fh, '<', $self->{'ulc'} . "/Cpanel/Version/Tiny.pm" ) or return;
    while ( my $version = <$fh> ) {
        next if ( $version !~ m/^our \$VERSION_BUILD\s+=\s+'/ );
        chomp $version;
        $version =~ s/^our \$VERSION_BUILD\s+=\s+'//;
        $version =~ s/';\s*//;

        $self->logger->info("Detected version '$version' from Tiny.pm");
        return $version;
    }
    return;
}

sub summary_logger {
    my $self = shift         or die;
    ref $self eq __PACKAGE__ or die("Must be called as a method");

    if ( !$self->{'summary_logger'} ) {
        $self->{'summary_logger'} = Cpanel::Update::Logger->new( { logfile => '/var/cpanel/updatelogs/summary.log', brief => 1, stdout => 0 } );
    }

    return $self->{'summary_logger'};
}

=item B<log_update_completed>

Record an entry in the concise log of updates that the update from
starting_version to target_version completed.

=cut

sub log_update_completed {
    my $self = shift         or die;
    ref $self eq __PACKAGE__ or die("Must be called as a method");

    $self->summary_logger->info( "Completed update " . $self->starting_version . ' -> ' . $self->target_version );

    return;
}

# This optimizes the fastest-mirror yum plugin for
# EA4's large number of mirrors.  Without this change
# each yum execution can take 9-20 seconds to startup
# because it spends a significant time calculating the
# fastest mirrors
sub _ensure_yum_fastest_mirror_optimized {
    my ($self) = @_;

    return if !-e $FASTEST_MIRROR_CNF_FILE;
    my $data = Cpanel::LoadFile::load($FASTEST_MIRROR_CNF_FILE);
    return if $data =~ m{\#cpanel modified};

    if ( open( my $fh, '>>', $FASTEST_MIRROR_CNF_FILE ) ) {
        if ( $data !~ m{^[ \t]*maxthreads[ \t]*=[ \t]*$FASTEST_MIRROR_MAX_THREADS}m ) {
            print {$fh} "\nmaxthreads = $FASTEST_MIRROR_MAX_THREADS\n";
        }
        if ( $data !~ m{^[ \t]*socket_timeout[ \t]*=[ \t]*$FASTEST_MIRROR_SOCKET_TIMEOUT}m ) {
            print {$fh} "\nsocket_timeout = $FASTEST_MIRROR_SOCKET_TIMEOUT\n";
        }
        print {$fh} "\n#cpanel modified\n";
    }

    return 1;
}

sub _http_client {
    my ($self) = @_;

    require Cpanel::HttpRequest;
    return $self->{'_http_client'} ||= Cpanel::HttpRequest->new(
        'die_on_404'      => 1,
        'retry_dns'       => 0,
        'hideOutput'      => 1,
        'logger'          => $self->logger(),
        'announce_mirror' => 1,
    );
}

=back

=cut

1;
