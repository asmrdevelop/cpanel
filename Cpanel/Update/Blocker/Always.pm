package Cpanel::Update::Blocker::Always;

# cpanel - Cpanel/Update/Blocker/Always.pm         Copyright 2023 cPanel, L.L.C.
#                                                           All rights reserved.
# copyright@cpanel.net                                         http://cpanel.net
# This code is subject to the cPanel license. Unauthorized copying is prohibited

use cPstrict;

use Cpanel::iContact                      ();
use Cpanel::DIp::MainIP                   ();
use Cpanel::JSON                          ();
use Cpanel::LoadFile                      ();
use Cpanel::LoadModule                    ();
use Cpanel::NAT                           ();
use Cpanel::Pack                          ();
use Cpanel::SafeDir::MK                   ();
use Cpanel::SafeRun::Object               ();
use Cpanel::Sys::Uname                    ();
use Cpanel::Server::Type                  ();
use Cpanel::TempFile                      ();
use Cpanel::TimeHiRes                     ();
use Cpanel::Update::Blocker::Base         ();    # PPI USE OK - Used for inheritance of common blocker logic.
use Cpanel::Update::Blocker::CpanelConfig ();    # cpanel.config integrity checks.
use Cpanel::Update::Blocker::MySQL        ();
use Cpanel::Update::Blocker::RemoteMySQL  ();
use Cpanel::Update::Blocker::WorkerNodes  ();
use Cpanel::Update::Config                ();
use Cpanel::Version::Compare::Package     ();
use Cpanel::Version::Tiny                 ();    # PPI USE OK - used an heredoc later - cplint issue CPANEL-37939
use Cpanel::OS                            ();
use Cpanel::OS::All                       ();
use Cpanel::Pkgr                          ();

# Needed for testing of these subs.
use parent -norequire, qw{ Cpanel::Update::Blocker::Base };

use Try::Tiny;

=head1 NAME

Cpanel::Update::Blocker::Always - Provides the code which is always run before any version changes are allowed.

=head1 DESCRIPTION

This is a parent class of Cpanel::Update::Blocker. It provides the following methods for the child class:

perform_global_checks

=head1 METHODS

=head2 B<new>

As this is a Role type class, this class is not designed to be instantiated directly.

=cut

sub new {
    die("Try Cpanel::Update::Blocker->new");
}

=head2 B<global_checks>

    These checks are run on all version changes. If you are adding something here, it is assumed this check has no known expiration date.

=cut

sub perform_global_checks ($self) {

    $self->is_supported_distro() or return;    # No further checks need to be done if we fail here.

    $self->block_updates_cross_products() or return;

    # Tack on additional if blocks as the versions increase.
    $self->is_license_expired();               # See sub is_license_expired for the dangers of removing this line.

    # Verify enough disk space exists to stage new cPanel files
    $self->is_disk_full_staging();

    # verify enough disk space exists in ULC to install new cPanel files.
    $self->is_disk_full_ulc();

    # Verify directories can be written to
    $self->is_directory_ro();

    unless ( $ENV{'CPANEL_BASE_INSTALL'} ) {    # we will not get here if rpm is broken
        $self->is_package_manager_sane();
    }

    $self->is_cpanel_config_broken();

    unless ( $ENV{'CPANEL_BASE_INSTALL'} ) {    # yum will be running in the background
        if ( Cpanel::OS::is_yum_based() ) {
            $self->is_yum_locked();
        }
    }

    # Upgrades should be blocked until running or paused transfers finish
    $self->active_transfer_exists();

    $self->is_remote_mysql_supported();

    $self->is_litespeed_version_insufficient();

    $self->is_supported_openssl();

    $self->are_worker_nodes_ready();

    return 1;
}

sub block_updates_cross_products ($self) {

    return 1 if $ENV{'CPANEL_BASE_INSTALL'};    # no check on fresh installations

    my $current_type = readlink('/usr/local/cpanel/server.type') // 'cpanel';
    my $target_type  = Cpanel::Server::Type::SERVER_TYPE();

    return 1 if $current_type eq $target_type;

    my $from_v = $self->starting_version();
    my $to_v   = $self->target_version();

    $self->block_version_change( <<"EOS" );
Cannot update from version $from_v [$current_type] to version $to_v [$target_type].
Updates cross products are not supported.
Please perform a fresh installation of $to_v instead.
EOS

    return;
}

sub are_worker_nodes_ready ($self) {
    my $prob = Cpanel::Update::Blocker::WorkerNodes::get_workers_problem(
        logger         => $self->logger(),
        target_version => $self->_Target_version(),
    );

    $self->block_version_change($prob) if length $prob;

    return;
}

=head2 B<is_license_expired>

If you remove this check you will likely be installing a build that your current license file
is not licensed for and as a result your system will no longer function.

This check is only here as a safety check and does not perform the actual license test.

By removing the license file you are accepting the risk that your system will no longer
function properly. Any downtime seen as a result of that action is solely your responsibility.

=cut

sub is_license_expired {
    my ($self) = @_;
    ref $self eq 'Cpanel::Update::Blocker' or die('This is a method call.');

    $self->logger->info("Checking license\n");

    # We don't need to warn about the license during install.
    if ( $ENV{'CPANEL_BASE_INSTALL'} ) {
        $self->logger->info('Installation in progress. Skipping license check.');
        return;
    }

    # Deal with unstable systems where a license check does not make sense.
    if ( !-e '/usr/local/cpanel/version' && !-e '/usr/local/cpanel/cpanel' && !-e '/usr/local/cpanel/cpkeyclt' && !-e '/usr/local/cpanel/cpanel.lisc' ) {
        $self->logger->warning('Your system appears unstable. Bypassing license check.');
        return;
    }

    system '/usr/local/cpanel/scripts/rdate';
    my $now = time();

    # Refuse further updates after installation until the license file is created.
    if ( !-e '/usr/local/cpanel/cpanel.lisc' ) {
        system '/usr/local/cpanel/cpkeyclt' if -x '/usr/local/cpanel/cpkeyclt';    # Attempt to create the license file once before failing
        if ( !-e '/usr/local/cpanel/cpanel.lisc' ) {

            # Block but do not create the blocker file. The file is only used in the front end.
            # The front end is only reachable once this problem is solved. It just creates confusion to have a blocker file for this.
            $self->block_version_change( 'No license file found. Your cPanel software will not function properly. Updates will be blocked until you fix this.', 'quiet_error' );
            return;
        }
    }

    my $updates_expire_time = 0;

    # Try to open the license file for read.
    my $cplisc_fh;
    if ( !open( $cplisc_fh, '<', '/usr/local/cpanel/cpanel.lisc' ) ) {
        $self->block_version_change("Unable to read license file: $!\nYou may need to execute /usr/local/cpanel/cpkeyclt via the command line to rectify this issue.");
        return;
    }

    # Look for updates_expire_time so we can prevent an upgrade that will break the license.
    while ( my $line = readline($cplisc_fh) ) {
        if ( $line =~ m/^updates_expire_time:\s+(\d+)/ ) {
            $updates_expire_time = $1;
            last;
        }
    }
    close($cplisc_fh);

    # Update privilege has expired
    if ( $updates_expire_time && $now > $updates_expire_time ) {

        my $msg = <<'EOS';



!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!

cPanel software update unable to continue. This server's license is
no longer eligible for software updates. In order to update this
server's cPanel software, you will need to purchase an update
extension for this server. Please contact customer service for more
information on software updates and update extensions.

https://tickets.cpanel.net/submit/?reqtype=cs

!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!



EOS

        foreach my $line ( split( /\n/, $msg ) ) {
            $self->logger->warning($line);    # this could also be done as a single warning call
        }

        $self->block_version_change("Server's license is no longer eligible for updates.");
    }

    $self->logger->info("License file check complete\n");
    return;
}

=head2 B<is_supported_distro>

Determine if the distro is allowed supported.

=cut

sub is_supported_distro ($self) {

    return 1 if Cpanel::OS::is_supported();

    my $eol_advice = Cpanel::OS::eol_advice();

    my $distro_list = Cpanel::OS::All::advertise_supported_distros();

    my $upgrade_your_os = q[Upgrade your OS];

    my $minor = Cpanel::OS::support_needs_minor_at_least_at();
    if ( defined $minor ) {
        $upgrade_your_os .= sprintf( " to %d.%d or later", Cpanel::OS::major(), $minor );    ## no critic(Cpanel::CpanelOS)
    }

    my $legacy_message = <<"EOS";
Newer releases of cPanel & WHM are not compatible with your operating system.
$upgrade_your_os, or use the <a href="../scripts2/updateconf">Update Preferences screen</a>
to select a Long-Term Support release for use with your OS. cPanel & WHM $Cpanel::Version::Tiny::VERSION_BUILD
supports $distro_list only.
Please see our <a href="https://go.cpanel.net/eol" target="_blank">OS End of Life policy</a> for more information.
EOS
    $legacy_message .= "$eol_advice\n" if length $eol_advice;

    $legacy_message =~ s{\n}{ }g;

    $self->block_version_change($legacy_message);

    return 0;
}

sub _max {
    my ( $a, $b ) = @_;

    return $a > $b ? $a : $b;
}

sub _zip {
    my ( $a, $b ) = @_;

    my @ret;

    my $count = _max( scalar @{$a}, scalar @{$b} );

    for ( my $i = 0; $i < $count; $i++ ) {
        push @ret, defined $a->[$i] ? $a->[$i] : undef;
        push @ret, defined $b->[$i] ? $b->[$i] : undef;
    }

    return \@ret;
}

# Performs a statfs(2) system call, and returns a hash ref with the unpacked.
# Compatible with x86_64 and i386 architectures.
sub _statfs {
    my ( $self, $path ) = @_;

    my @MEMBERS = qw(
      f_type f_bsize f_blocks f_bfree f_bavail f_files
      f_ffree f_fsid f_namelen f_frsize f_flags f_spare
    );

    my %TEMPLATES = (
        'i386'   => [qw(L L L L L L L L L L L LLLL)],
        'x86_64' => [qw(Q Q Q Q Q Q Q Q Q Q Q QQQQ)]
    );

    my %SYSCALL_IDS = (
        'i386'   => 99,
        'x86_64' => 137
    );

    my @uname = Cpanel::Sys::Uname::get_uname_cached();

    unless ( defined $SYSCALL_IDS{ $uname[4] } ) {
        die "Unsupported platform '$uname[4]'";
    }

    my $struct = Cpanel::Pack->new( _zip( \@MEMBERS, $TEMPLATES{ $uname[4] } ) );
    my $buf    = $struct->malloc();

    return syscall( $SYSCALL_IDS{ $uname[4] }, $path, $buf ) < 0
      ? ()
      : $struct->unpack_to_hashref($buf);
}

=head2 B<is_disk_full_ulc>

Ensure ~1 GB of free space is available at C</usr/local/cpanel> to install new cPanel files.

=cut

sub is_disk_full_ulc {
    my ($self) = @_;
    ref $self eq 'Cpanel::Update::Blocker' or die('This is a method call.');

    my $path =
        -e '/usr/local/cpanel' ? '/usr/local/cpanel'
      : -e '/usr/local'        ? '/usr/local'
      :                          '/usr';

    my $statfs = $self->_statfs($path);
    my $space  = $statfs->{'f_bsize'} * $statfs->{'f_bavail'};
    my $inodes = $statfs->{'f_ffree'};

    my @ignore_free_inode_types = (
        0x9123683E,    # BTRFS_SUPER_MAGIC from include/linux/magic.h -- UNSUPPORTED, always reports 0 free, OK to ignore because inodes are effectively unlimited
    );
    my $ignore_free_inodes = ( grep { $statfs->{'f_type'} == $_ } @ignore_free_inode_types ) ? 1 : 0;

    if ( $space < 1073741824 ) {
        $space = sprintf( "%1.02f", $space / 1024 / 1024 );
        $self->block_version_change("cPanel & WHM cannot update due to insufficient disk space. The system detected $space MB free, but requires at least 1 GB free at '$path' in order to successfully update.");
        return;
    }

    if ( !$ignore_free_inodes && $inodes < 360000 ) {
        $self->block_version_change("cPanel & WHM cannot update due to insufficient available inodes. The system detected $inodes free inodes, but requires at least 360,000 free inodes at '$path' in order to successfully update.");
        return;
    }

    return 1;
}

=head2 B<is_disk_full_staging>

Ensure ~3G of free space is available in the STAGING_DIR configured in /etc/cpupdate.conf

=cut

sub is_disk_full_staging {
    my ($self) = @_;
    ref $self eq 'Cpanel::Update::Blocker' or die('This is a method call.');

    my $path;

    # If path is not the "default" path of ulc, then we'll simply use that as the path to check.
    if ( $self->{'upconf_ref'}->{'STAGING_DIR'} and $self->{'upconf_ref'}->{'STAGING_DIR'} ne '/usr/local/cpanel' ) {
        $path = $self->{'upconf_ref'}->{'STAGING_DIR'};
    }
    else {
        $path =
            -e '/usr/local/cpanel' ? '/usr/local/cpanel'
          : -e '/usr/local'        ? '/usr/local'
          :                          '/usr';
    }

    Cpanel::SafeDir::MK::safemkdir($path) if !-d $path;
    my $statfs = $self->_statfs($path) or return;
    my $space  = $statfs->{'f_bsize'} * $statfs->{'f_bavail'};

    if ( $space < 3221225472 ) {
        $space = sprintf( "%1.02f", $space / 1024 / 1024 / 1024 );
        my ( $public_ip, $subject, $message );
        eval { $public_ip = Cpanel::NAT::get_public_ip( Cpanel::DIp::MainIP::getmainip() ); };

        my $update_preferences_url = 'https://' . ( $public_ip ? $public_ip : 'SERVER_IP' ) . ':2087/scripts2/updateconf';
        my $new_staging_dir        = $self->_find_better_staging_location();
        if ($new_staging_dir) {
            $self->{'upconf_ref'}->{'STAGING_DIR'} = $new_staging_dir;
            Cpanel::Update::Config::save( $self->{'upconf_ref'} );

            $subject = "Upgrade blocked: Not enough disk space: '$path'. Automatically determined a new staging directory for the next upcp run.";
            $message = <<END_OF_MESSAGE;
cPanel & WHM cannot update due to insufficient disk space in the staging directory, "$path". The system requires 3 GB to update; this directory only has $space GB available.

The system automatically selected "$new_staging_dir" as a staging directory. All update data will be stored here. If you take no action, the system will continue to use this directory for future updates. To change the location of the staging directory, use $update_preferences_url .

END_OF_MESSAGE

            $self->block_version_change(
                "cPanel & WHM cannot update due to insufficient disk space in the staging directory, '$path'. The system requires 3 GB to update; this directory only has ${space} GB available. The system automatically selected '$new_staging_dir' as a staging directory. All update data will be stored here. If you take no action, the system will continue to use this directory for future updates. To change the location of the staging directory, use WHM's <a href=\"../scripts2/updateconf\">Update Preferences interface</a>."
            );
        }
        else {
            $subject = "Upgrade blocked: Not enough disk space: '$path'.";
            $message = <<END_OF_MESSAGE;
cPanel & WHM cannot update due to insufficient disk space in the staging directory, "$path". The system requires 3 GB to update; this directory only has $space GB available

The system failed to find a new staging directory with enough space to update. You can either clear enough disk space or select a new staging directory with enough disk space at $update_preferences_url .

END_OF_MESSAGE

            $self->block_version_change(
                "cPanel & WHM cannot update due to insufficient disk space in the staging directory, '$path'. The system requires 3 GB to update; this directory only has $space GB available. The system failed to find a new staging directory with enough space to update. You can either clear enough disk space or select a new staging directory with enough disk space at <a href=\"../scripts2/updateconf\">Update Preferences interface</a>."
            );
        }

        Cpanel::iContact::icontact(
            'application'              => 'upcp',
            'subject'                  => "[$public_ip] $subject",
            'message'                  => $message,
            'prepend_hostname_subject' => 1,
        );
        return;
    }

    return 1;
}

sub _find_better_staging_location {
    my ($self) = @_;
    ref $self eq 'Cpanel::Update::Blocker' or die('This is a method call.');

    my @home_mounts;
    eval {
        Cpanel::LoadModule::load_perl_module('Cpanel::Filesys::Home');
        @home_mounts = Cpanel::Filesys::Home::get_all_homedirs();
    };
    return if ( !scalar @home_mounts || $@ );

    # get_all_homedirs() already returns data in the sort order we want ( most free -> least free )
    foreach my $largest_mountpoint (@home_mounts) {
        if ( Cpanel::Update::Config::validate_staging_dir($largest_mountpoint) ) {
            my $statfs   = $self->_statfs($largest_mountpoint) or return;
            my $avail_gb = ( $statfs->{'f_bsize'} * $statfs->{'f_bavail'} ) / 1048576 / 1024;

            return $largest_mountpoint if $avail_gb > 3;
        }
    }
    return;
}

=head2 B<is_directory_ro>

Ensure that directories needed for update/upgrade can be written to

=cut

our @system_directories = qw{ /etc /var /usr/local /usr/bin /tmp /var/tmp };

our @optional_directories = qw{ /var/cpanel /usr/local/cpanel /usr/local/bin /var/lib/rpm };

sub is_directory_ro {
    my ($self) = @_;
    ref $self eq 'Cpanel::Update::Blocker' or die('This is a method call.');

    my $ok = 1;

    # check all directories permissions
    my @all_directories = @system_directories;
    push @all_directories, grep { -d $_ } @optional_directories;

    foreach my $dir (@all_directories) {
        unless ( $self->_test_path_is_rw($dir) ) {
            $self->block_version_change("Can not upgrade because $dir is not writable");
            $ok = 0;
        }
    }

    return $ok;
}

our $rw_testfile = '/CPANEL_TEST_FS_IS_RW';

# This exists to assist in mocking.
sub _create_temporary_directory {
    my ( $self, $path ) = @_;
    ref $self eq 'Cpanel::Update::Blocker' or die('This is a method call.');

    $path or return;

    my $temp = Cpanel::TempFile->new;
    $path = $temp->dir( { path => $path } ) . $rw_testfile;

    return ( $temp, $path );
}

sub _test_path_is_rw {
    my ( $self, $dir ) = @_;
    ref $self eq 'Cpanel::Update::Blocker' or die('This is a method call.');

    $dir or return;
    $dir =~ s/\/$//;    # Strip trailing slash.
    $dir = "/" if !$dir;

    return unless -d $dir;

    my ( $temp, $path );

    eval {
        ( $temp, $path ) = $self->_create_temporary_directory($dir);
        open( my $fh, '>', $path ) or die "failed to open $path: $!";
        print {$fh} 'abc'          or die "failed to print to $path: $!";
        close($fh)                 or die "failed to close $path: $!";
    };
    my $error = $@;

    my $file_size = -s $path // 0;
    unlink $path;
    return unless $file_size == 3;
    return if $error;
    return 1;
}

sub is_package_manager_sane ($self) {
    ref $self eq 'Cpanel::Update::Blocker' or die('This is a method call.');

    my ( $db_works, $msg ) = Cpanel::Pkgr::verify_package_manager_can_install_packages( $self->{'logger'} );
    return 1 if $db_works;

    $msg //= '';
    $self->block_version_change("Your Packaging System does not seem in a sane state at the moment: $msg");

    return;
}

sub is_cpanel_config_broken {
    my ($self) = @_;
    ref $self eq 'Cpanel::Update::Blocker' or die('This is a method call.');

    my $cpconfig = Cpanel::Update::Blocker::CpanelConfig->new( { 'logger' => $self->logger() } );

    # Clear away pesky white space on front and back of values we're about to check.
    $cpconfig->cleanse_cpanel_config_entries();

    my $mysql    = Cpanel::Update::Blocker::MySQL->new( { 'logger' => $self->logger(), 'cpconfig' => $cpconfig->cpconfig() } );
    my $mysql_ok = $mysql->is_mysql_version_valid();
    if ( !$mysql_ok ) {
        my $reason = $mysql->{'mysql-reason'} || 'The mysql-version value in /var/cpanel/cpanel.config either is invalid or references an unsupported MySQL/MariaDB version. Upgrade to a newer MySQL/MariaDB version, then attempt to update again. You can upgrade your system’s MySQL/MariaDB here: <a href="../scripts/mysqlupgrade">MySQL/MariaDB Upgrade</a>';
        $self->block_version_change($reason);
        $cpconfig->{'invalid'}++;
    }

    my $nameserver_ok = $cpconfig->is_local_nameserver_type_valid();
    if ( !$nameserver_ok ) {
        $self->block_version_change('The local_nameserver_type value in /var/cpanel/cpanel.config is invalid. Valid values are powerdns, bind or you can leave it blank. You can change the value here: <a href="../scripts/nameserverconfig">Nameserver Selection</a>');
    }

    my $mailserver_ok = $cpconfig->is_mailserver_valid();
    if ( !$mailserver_ok ) {
        $self->block_version_change('The mailserver value in /var/cpanel/cpanel.config is invalid. Valid values are dovecot or disabled. You can change the value here: <a href="../scripts/mailserverconfig">Mailserver Configuration</a>');
    }

    my $ftpserver_ok = $cpconfig->is_ftpserver_valid();
    if ( !$ftpserver_ok ) {
        $self->block_version_change('The ftpserver value in /var/cpanel/cpanel.config is invalid. Valid values are pure-ftpd or proftpd. You can change the value here: <a href="../scripts2/tweakftp">FTP Server Selection</a>');
    }

    return $cpconfig->is_legacy_cpconfig_invalid();
}

=head2 B<is_yum_locked>

Ensure that /var/run/yum.pid does not exist - the main purpose of this check is to look for yum being stuck - not worried about collisions.

=cut

our $YUM_WAIT_SLEEP_INTERVAL = 5;    # for testing

sub is_yum_locked {
    my ($self) = @_;
    ref $self eq 'Cpanel::Update::Blocker' or die('This is a method call.');

    my $timeout      = $self->_yum_lock_timeout;
    my $counter      = 0;
    my $yum_pid_file = '/var/run/yum.pid';
    while ( -e $yum_pid_file ) {
        my $pid_in_file = Cpanel::LoadFile::loadfile($yum_pid_file);
        if ( $pid_in_file && !kill( 0, $pid_in_file ) ) {
            unlink($yum_pid_file) && return 1;
        }
        elsif ( $counter > $timeout ) {
            $self->block_version_change("Cannot upgrade because yum is locked (/var/run/yum.pid has existed for 10+ minutes).");
            return;
        }
        Cpanel::TimeHiRes::sleep($YUM_WAIT_SLEEP_INTERVAL);
        $counter += $YUM_WAIT_SLEEP_INTERVAL;
    }
    return 1;
}

=head2 B<_yum_lock_timeout>

acessor support for the is_yum_locked test

=cut

sub _yum_lock_timeout {
    my ( $self, $timeout ) = @_;
    $self->{'_yum_lock_timeout'} = $timeout if defined $timeout;
    return $self->{'_yum_lock_timeout'} || 600;
}

=head2 B<active_transfer_exists>

Block updates if a transfer is currently running or pausing.

=cut

sub active_transfer_exists {
    my ($self) = @_;
    ref $self eq 'Cpanel::Update::Blocker' or die('This is a method call.');

    if ( Cpanel::Server::Type::is_dnsonly() ) {
        $self->logger->info('DNSONLY detected.');
        return;
    }

    return if $ENV{CPANEL_BASE_INSTALL};

    my $script_path = '/usr/local/cpanel/scripts/transfer_in_progress';

    return if !-e $script_path;

    my $saferun_obj = Cpanel::SafeRun::Object->new(
        program      => $script_path,
        timeout      => 86400,
        read_timeout => 86400,
        args         => ['--serialize_output'],
    );

    if ( $saferun_obj->CHILD_ERROR() ) {
        $self->logger->warn( "The script '$script_path' failed to check for active transfers due to an error: " . $saferun_obj->stderr() );
        return;
    }

    my $output = $saferun_obj->stdout();

    if ( !length $output ) {
        $self->logger->warn("The script '$script_path' failed to return any output.");
        return;
    }

    my $err;
    my $response;
    try {
        $response = Cpanel::JSON::Load($output);
    }
    catch {
        $err = $_;
    };

    if ($err) {
        $self->logger->warn("The script '$script_path' failed to return valid output: $err");
        return;
    }

    return if !$response->{transfer_exists};

    $self->block_version_change('There are active transfers to this server. The system will block updates until those transfers end or a user aborts them. Please read our <a href="https://go.cpanel.net/whmdocsTransferTool" target="_blank">Transfer Tool documentation</a> for more information.');

    return;
}

sub is_remote_mysql_supported {
    my ($self) = @_;
    ref $self eq 'Cpanel::Update::Blocker' or die('This is a method call.');

    # Do not check this on new installs since it would seem odd that you
    # would set up a remote mysql instance before installing cPanel
    return if $ENV{'CPANEL_BASE_INSTALL'};

    my $remote_mysql_obj = Cpanel::Update::Blocker::RemoteMySQL->new( { 'logger' => $self->logger } );

    # just return if they are not running a remote mysql server
    return unless $remote_mysql_obj->is_remote_mysql();

    $self->logger->info('Checking if remote mysql server is supported');

    my $err;
    try {
        $remote_mysql_obj->is_mysql_supported_by_cpanel();
    }
    catch {
        $err = $_ || 'cPanel & WHM does not support your remote MySQL/MariaDB version.';
    };

    if ($err) {
        $self->block_version_change($err);
        return;
    }

    $self->logger->info('Remote mysql server check is complete');
    return 1;
}

sub is_litespeed_version_insufficient {
    my ($self) = @_;

    require Cpanel::Config::Httpd::Vendor;
    my ( $is_lsws, $version ) = Cpanel::Config::Httpd::Vendor::httpd_vendor_info();

    return 0 unless grep { $_ eq $is_lsws } qw{litespeed};

    my ( $maj, $min, $build ) = split( /\./, $version );
    if ( $maj <= 5 && $min <= 3 && $build < 6 ) {
        $self->block_version_change("LiteSpeed WebServer version must be greater than 5.3.5");
        return 1;
    }
    $self->logger->info('LiteSpeed version check is complete');
    return 0;
}

=head2 is_supported_openssl

Block updates if running an outdated OpenSSL on CentOS/RHEL 7

=cut

sub is_supported_openssl ($self) {

    return if $ENV{'CPANEL_BASE_INSTALL'};

    my $minimum_required_version = Cpanel::OS::openssl_minimum_supported_version() or return;

    my $openssl_version = Cpanel::Pkgr::get_package_version('openssl');
    return unless length $openssl_version;    # We couldn't determine the openssl version. Let's not block over this.

    if ( Cpanel::Version::Compare::Package::version_cmp( $openssl_version, $minimum_required_version ) == -1 ) {
        $self->block_version_change(qq{This system is running an outdated version of OpenSSL ($openssl_version), which will need to be updated to at least $minimum_required_version to continue.});
        return;
    }

    return;
}

1;
