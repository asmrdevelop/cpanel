package Cpanel::Repo::Install::MysqlBasedDB;

# cpanel - Cpanel/Repo/Install/MysqlBasedDB.pm     Copyright 2022 cPanel, L.L.C.
#                                                           All rights reserved.
# copyright@cpanel.net                                         http://cpanel.net
# This code is subject to the cPanel license. Unauthorized copying is prohibited

use cPstrict;

use Cpanel::Debug                ();
use Cpanel::Exception            ();
use Cpanel::LoadModule           ();
use Cpanel::Logger               ();
use Cpanel::MysqlUtils::Install  ();
use Cpanel::MysqlUtils::Versions ();
use Cpanel::Repos                ();
use Cpanel::SysPkgs              ();
use Cpanel::SafeDir::MK          ();
use Cpanel::Install::MySQL       ();
use Cpanel::Database             ();
use Cpanel::OS                   ();
use Cpanel::RpmUtils::Parse      ();
use File::Basename               ();
use File::Temp                   ();

use Try::Tiny;

my $MY_CNF_PRESERVE_EXT = '.cpsave';

use parent 'Cpanel::Repo::Install';

=encoding utf-8

=head1 NAME

Cpanel::Repo::Install::MysqlBasedDB - A base class for installers using yum or apt and installing MySQL

=head1 SYNOPSIS

    use parent 'Cpanel::Repo::Install::MysqlBasedDB';

=head1 DESCRIPTION

This module is used as a base class for our new MySQL and MariaDB installers that use yum or apt.

=cut

=head2 new

This method instantiates a new Cpanel::Repo::Install::MysqlBasedDB derived class.

=head3 Input

=over 3

=item C<Cpanel::Output> output_obj

    An optional argument that is expected to be a Cpanel::Output derived object used for output.

=back

=head3 Output

=over 3

A new Cpanel::Repo::Install::MysqlBasedDB derived object.

=back

=head3 Exceptions

=over 3

None directly.

=back

=cut

# This is a stub, must be defined by kiddos
# Give reasonable defaults if not set.
sub upgrade_hook     { return 0 }
sub _get_vendor_name { return 'Mysql' }

sub new ( $class, %OPTS ) {

    my $output_obj = $OPTS{'output_obj'} || Cpanel::Logger->new();

    return bless {
        'output_obj' => $output_obj,
        #
        # We need a Mysql Install object so we can ensure that the compat rpms
        # are provided.
        #
        'vendor_install_obj' => Cpanel::MysqlUtils::Install->new( 'output_obj' => $output_obj ),
        'build_mysql_conf'   => $OPTS{'skip_build_mysql_conf'} ? 0 : 1,
        'skip_ensure_rpms'   => $OPTS{'skip_ensure_rpms'}      ? 1 : 0,
        'repos_obj'          => Cpanel::Repos->new(),
        'syspkgs_obj'        => Cpanel::SysPkgs->new( 'output_obj' => $output_obj ),
        'vendor_name'        => $class->_get_vendor_name(),
        'upgrade_hook'       => $class->upgrade_hook,
    }, $class;
}

=head2 install_rpms( VERSION )

This function will install the RPMs or debs for the selected version from the installed yum or repo.
Afterwards, it will run mysqlconnectioncheck on the newly installed/upgraded DB

=head3 Arguments

=over 4

=item version    - SCALAR - The selected version to install

=back

=head3 Returns

This function either returns 1 on success or dies.

=head3 Exceptions

None directly.

=cut

sub install_rpms {
    my ( $self, $version ) = @_;

    $self->SUPER::install_rpms($version);

    if ( Cpanel::OS::security_service() eq 'apparmor' ) {

        # Needs the file /etc/apparmor.d/usr.sbin.mysqld in place (by installing mysql package), so this must be done after installing the packages
        $self->configure_apparmor();
    }

    require Cpanel::MysqlUtils::Check;
    require Cpanel::MysqlUtils::MyCnf::Adjust;

    Cpanel::MysqlUtils::Check::check_mysql_password_works_or_reset();

    Cpanel::MysqlUtils::MyCnf::Adjust::auto_adjust();

    if ( Cpanel::OS::is_systemd() ) {
        require Cpanel::MysqlUtils::Systemd::ProtectHome;
        Cpanel::MysqlUtils::Systemd::ProtectHome::set_unset_protecthome_if_needed();
    }

    return 1;
}

# Configure apparmor so it will play nicely with the community mysql packages
# For now we just obliterate anything already there, in the future we may want to have this merge and remove dupes

sub configure_apparmor ($self) {
    return unless Cpanel::OS::security_service() eq 'apparmor';

    my $local_fh;
    if ( open( $local_fh, '>', '/etc/apparmor.d/local/usr.sbin.mysqld' ) ) {
        print $local_fh <<"EOF";
/etc/my.cnf r,
/root/.my.cnf r,
capability dac_read_search,
/sys/devices/system/node/ r,
/sys/devices/system/node/node*/meminfo r,
/sys/devices/system/node/*/* r,
/sys/devices/system/node/* r,
EOF
        close($local_fh);
    }

    # Edit the main apparmor config provided by the mysql-community-server package to enable our local include
    my $system_fh_read;
    if ( open( $system_fh_read, '<', '/etc/apparmor.d/usr.sbin.mysqld' ) ) {
        my @current_file = (<$system_fh_read>);
        close($system_fh_read);
        my @output_contents;
        if (@current_file) {
            my $found_include = 0;
            foreach my $line (@current_file) {
                chomp $line;

                # This line is included in the file provided by
                if ( $line =~ m/include\ \<local\/usr\.sbin\.mysqld\>/ ) {
                    $found_include++;
                    push( @output_contents, '  include <local/usr.sbin.mysqld>' );
                }
                else {
                    push( @output_contents, $line );
                }
            }

            # This shouldn't ever be needed, but might as well play it safe
            if ( !$found_include ) {
                push( @output_contents, '  include <local/usr.sbin.mysqld>' );
            }

            # Write the modified config
            if ( open( my $system_fh_write, '>', '/etc/apparmor.d/usr.sbin.mysqld' ) ) {
                foreach my $line (@output_contents) {
                    print $system_fh_write "$line\n";
                }
                close($system_fh_write);
            }
        }
    }

    # Reload the config
    system(qw{/usr/sbin/apparmor_parser -r /etc/apparmor.d/usr.sbin.mysqld});

    return;
}

sub mysql_apt_preseed_template {
    return <<'END___PRESEED';
# Preseed file for mysql ##ROOTSQLPASS## from community repo
mysql-community-server mysql-community-server/re-root-pass password ##ROOTSQLPASS##
mysql-community-server mysql-community-server/root-pass password ##ROOTSQLPASS##
# Choices: Use Strong Password Encryption (RECOMMENDED), Use Legacy Authentication Method (Retain MySQL 5.x Compatibility)
mysql-community-server mysql-server/default-auth-override select Use Legacy Authentication Method (Retain MySQL 5.x Compatibility)
mysql-community-server mysql-community-server/remove-data-dir boolean false
# Data directory found when no MySQL server package is installed
mysql-community-server mysql-community-server/data-dir note /var/lib/mysql
mysql-community-server mysql-server/lowercase-table-names select
# Enable or disable MySQL tools and utilities
mysql-apt-config mysql-apt-config/select-tools select Enabled
mysql-apt-config mysql-apt-config/repo-distro select ubuntu
# Enable or disable MySQL preview packages
mysql-apt-config mysql-apt-config/select-preview select Disabled
mysql-apt-config mysql-apt-config/repo-codename select focal
# Choices: mysql-8.0, mysql-cluster-8.0, None
mysql-apt-config mysql-apt-config/select-server select mysql-8.0
mysql-apt-config mysql-apt-config/preview-component string
# Provide MySQL repo location:
mysql-apt-config mysql-apt-config/repo-url string http://repo.mysql.com/apt
mysql-apt-config mysql-apt-config/unsupported-platform select abort
# Which MySQL product do you wish to configure?
# Choices: MySQL Server & Cluster (Currently selected: mysql-8.0), MySQL Tools & Connectors (Currently selected: Enabled), MySQL Preview Packages (Currently selected: Disabled), Ok
mysql-apt-config mysql-apt-config/select-product select Ok
mysql-apt-config mysql-apt-config/tools-component string mysql-tools
END___PRESEED
}

sub write_preseed_file ( $self, $version ) {
    my $tmp_obj = File::Temp->new( TEMPLATE => 'mysql_preseed.XXXXX', DIR => "/root", UNLINK => 0 );

    # Get a decent root pass to use for now, will be reset later but at least we have a secure pass from the start
    require Cpanel::MysqlUtils::ResetRootPassword;
    my $newpass = Cpanel::MysqlUtils::ResetRootPassword::get_root_password_that_meets_password_strength_requirements();

    my $preseed_contents = mysql_apt_preseed_template();
    $preseed_contents =~ s/\#\#ROOTSQLPASS\#\#/$newpass/g;
    print $tmp_obj $preseed_contents;
    my $file_path = $tmp_obj->filename();

    close($tmp_obj);

    require Cpanel::DB::Mysql::Files;
    my $mycnf = Cpanel::DB::Mysql::Files->new;
    $mycnf->write_my_cnf( { 'user' => 'root', 'pass' => $newpass } );

    return $file_path;
}

sub preseed_configuration {
    my ( $self, $preseed_path ) = @_;
    if ( !-f $preseed_path || !-r _ ) {
        die "Could not preseed configuration from “$preseed_path”";
    }
    require Cpanel::SafeRun::Object;
    my $run = Cpanel::SafeRun::Object->new(
        program => '/usr/bin/debconf-set-selections',
        args    => [ '-c', $preseed_path ],
    );
    if ( $run->stderr() ) {
        warn "Preseed config reported errors: \n\t" . $run->stderr() . "\n";
    }

    # Set the preconfigured options
    $run = Cpanel::SafeRun::Object->new(
        program => '/usr/bin/debconf-set-selections',
        args    => [$preseed_path],
    );

    # Remove the preseed file now
    unlink $preseed_path;
    return 1;
}

=head2 verify_can_be_installed

This function checks to see if the MySQL/MariaDB packages can be installed or dies.

=head3 Arguments

=over 4

=item C<SCALAR> target_version

    The version of MySQL/MariaDB to install. This object handles MySQL/MariaDB versions 5.7+.

=back

=head3 Returns

This function either returns 1 on success or dies.

=head3 Exceptions

- If the version isn't passed.
- If any of the packages cant be installed

=cut

sub verify_can_be_installed {
    my ( $self, $target_version, $opts_hr ) = @_;

    die "verify_can_be_installed requires a target_version" if !$target_version;

    my $vendor_name = $self->_get_vendor_name();

    $self->{'output_obj'}->out("Verifying that the system is in a state where $vendor_name packages can be installed.");

    # Skip this on base install. We don't fatpack the Warnings module and there probably isn't a malicious user already
    # on a new system
    if ( !$ENV{'CPANEL_BASE_INSTALL'} ) {
        Cpanel::LoadModule::load_perl_module('Whostmgr::Mysql::Upgrade::Warnings');
        Cpanel::LoadModule::load_perl_module('Cpanel::MysqlUtils::Version');

        my $current_version = eval { Cpanel::MysqlUtils::Version::current_mysql_version()->{'short'} } || do {
            Cpanel::Debug::log_warn("Failed to determine the current MySQL version! The system will assume, for the purposes of the current action, that $Cpanel::MysqlUtils::Version::DEFAULT_MYSQL_RELEASE_TO_ASSUME_IS_INSTALLED is the currently installed MySQL version. The last error was: $@");
            $Cpanel::MysqlUtils::Version::DEFAULT_MYSQL_RELEASE_TO_ASSUME_IS_INSTALLED;
        };

        my ( $fatal, $warnings_ar ) = Whostmgr::Mysql::Upgrade::Warnings::get_upgrade_warnings( $target_version, $current_version );

        if ($fatal) {
            Cpanel::LoadModule::load_perl_module('Cpanel::StringFunc::HTML');
            my $warnings_str = "\n" . join(
                '   ',
                map {
                    my $msg = $_->{'message'};
                    chomp($msg);
                    $msg .= "\n";
                    Cpanel::StringFunc::HTML::trim_html( \$msg );
                    $msg
                } grep { $_->{'severity'} eq 'Fatal' } @$warnings_ar
            );

            die "$vendor_name could not be updated due to the following: $warnings_str\n";
        }
    }

    $self->SUPER::verify_can_be_installed( $target_version, $opts_hr );
    return 1;
}

sub _get_pkg_targets {
    return Cpanel::MysqlUtils::Versions::get_rpm_target_names();
}

sub _call_before_final_hooks {
    my ($self) = @_;

    return if !$self->{'build_mysql_conf'};

    # Failing to build the config is likely non-fatal
    # as its inevitable that the system will have a DB
    # that has a corrupt table at some point
    try {
        $self->{'vendor_install_obj'}->build_mysql_conf();
    }
    catch {
        $self->{'output_obj'}->error( Cpanel::Exception::get_string($_) );
    };

    return;
}

sub _call_before_uninstall_incompatible_packages {
    my ($self) = @_;

    require Cpanel::MysqlUtils::MyCnf::Basic;
    my $my_cnf_path = $Cpanel::MysqlUtils::MyCnf::Basic::_SYSTEM_MY_CNF;

    # If the system my.cnf file exists, we want to back it up before
    # we uninstall incompatible packages, as switching between older versions of
    # MySQL and community, or MySQL and MariaDB will remove the system my.cnf
    # and we'll lose any customizations the user might have made.
    require Cpanel::Autodie::More::Lite;
    if ( Cpanel::Autodie::More::Lite::exists($my_cnf_path) ) {
        require Cpanel::FileUtils::Copy;
        my ( $res, $err ) = Cpanel::FileUtils::Copy::copy( $my_cnf_path, "${my_cnf_path}$MY_CNF_PRESERVE_EXT" );
        die $err if !$res;
    }

    return;
}

sub _call_after_uninstall_incompatible_packages {

    require Cpanel::MysqlUtils::MyCnf::Basic;
    my $my_cnf_path = $Cpanel::MysqlUtils::MyCnf::Basic::_SYSTEM_MY_CNF;

    # If we saved a copy of my.cnf in _call_before_uninstall_incompatible_packages
    # we need to restore it to the real path here.
    require Cpanel::Autodie::More::Lite;
    if ( Cpanel::Autodie::More::Lite::exists("${my_cnf_path}$MY_CNF_PRESERVE_EXT") ) {
        require Cpanel::Autodie::File;
        Cpanel::Autodie::File::rename( "${my_cnf_path}$MY_CNF_PRESERVE_EXT", $my_cnf_path );
    }

    return;
}

=head2 install_upgrade_hook

Puts a hook in for the relevant package upgrade to run build_mysql_conf.

=cut

sub install_upgrade_hook {
    my ($self) = @_;

    return unless $self->upgrade_hook;    #This should be set by child objects
    return if -e $self->upgrade_hook;     #Nothing to do

    my $path_to_hook = File::Basename::dirname( $self->upgrade_hook );

    unless ( Cpanel::SafeDir::MK::safemkdir( $path_to_hook, '0700' ) ) {
        $self->{output_obj}->error("Could not create directory to install yum or apt hook ($path_to_hook) into ($!)");
        return 0;
    }

    #XXX Note for future - if we ever support win32 this will need to be eval()d.
    unless ( symlink( q{/usr/local/cpanel/bin/build_mysql_conf}, $self->upgrade_hook ) ) {
        $self->{output_obj}->error("Could not install yum or apt hook ($self->upgrade_hook) ($!)");
        return 0;
    }

    return 1;
}

=head2 install_repo

This function installs the yum or apt repository for the version specified and enables the repo.

On modular yum-based systems the mysql and mariadb system modules are disabled so that the upstream/community/non-modular
packages can be installed.

=head3 Input

=over 3

=item C<SCALAR> target_version

    The version to install. This object handles versions 5.7+ on yum-based-systems and 8.0+ on apt-based systems..

=back

=head3 Output

=over 3

This function returns 1 on success or dies.

=back

=head3 Exceptions

=over 3

If target_version isn't passed.

=back

=cut

sub install_repo {
    my ( $self, $target_version ) = @_;

    if ( Cpanel::OS::is_apt_based() ) {    ## no critic qw(Cpanel::CpanelOS) -- pre-existing use

        # Ensure the repo key is known to apt.
        Cpanel::Install::MySQL::install_mysql_keys();

        # We want to mimic the behavior (all lowercase) the deb conf configure script uses for mysql, ie 'mysql.list'
        $self->{vendor_name} = lc( $self->{vendor_name} );

        $Cpanel::REPOS::TARGET_REPOS_DIR = '/etc/apt/sources.list.d/';
    }

    my $db_obj = Cpanel::Database->new( { db_type => $self->{vendor_name}, db_version => $target_version, reset => 1 } );

    # MySQL uses release rpm's. Lets update it to be sure we have the most recent version of the repo.
    if ( $db_obj->uses_release_rpm() && Cpanel::OS::is_yum_based() ) {

        # Remove any old release rpm's, otherwise we will conflict.
        $self->{syspkgs_obj}->uninstall_packages( packages => ['mysql*-community-release'] );

        # Install the release rpm
        $self->SUPER::install_repo($target_version);

        # Update the release rpm for possible GPG key updates. We need figure out the actual package name.
        my $rpm_file        = $self->_get_repo_rpm_filename($target_version);
        my $file            = ( split( m{\/}, $rpm_file ) )[-1];
        my $parsed_rpm_name = Cpanel::RpmUtils::Parse::parse_rpm_arch($file);
        my $pkg_name        = $parsed_rpm_name->{'name'};

        # Update the package, if it fails log the error. The upstream repo could be broken
        # and we don't want to completely bail out in that case.
        try {
            $self->{syspkgs_obj}->install_packages( packages => [$pkg_name], command => ['update'] );
        }
        catch {
            $self->{output_obj}->error( Cpanel::Exception::get_string($_) );
        };
    }
    else {
        # Retrieve the repo and send it along to be installed.
        my $repo_contents = $db_obj->get_repo();

        $self->SUPER::install_repo( $target_version, $repo_contents );
    }

    if ( Cpanel::OS::is_yum_based() ) {

        if ( $db_obj->uses_release_rpm() ) {

            # We need to ensure the newest version of the file is put into place. The repo is marked as
            # config(noreplace) meaning it will in most cases be saved with a ".rpmnew" suffix.
            my ($repo) = $self->{'repos_obj'}->_get_repo_matching('mysql-community.repo.rpmnew');

            if ($repo) {
                my $rpmnew_full_path = $Cpanel::Repos::TARGET_REPOS_DIR . '/' . $repo;
                my $rpmnew_mtime     = ( stat($rpmnew_full_path) )[9];
                my $diff             = time - $rpmnew_mtime;

                # Only move the .rpmnew file into place if it has been changed recently ( 5 mins ).
                if ( $diff < 300 ) {
                    my $overwrite_target = $Cpanel::Repos::TARGET_REPOS_DIR . '/mysql-community.repo';
                    require Cpanel::FileUtils::Write;
                    require Cpanel::LoadFile;
                    Cpanel::FileUtils::Write::overwrite( $overwrite_target, Cpanel::LoadFile::load($rpmnew_full_path) );
                }
            }

            require Cpanel::MysqlUtils::Versions;
            my @mysql_versions      = Cpanel::MysqlUtils::Versions::get_supported_mysql_versions();
            my @versions_to_disable = grep { $_ ne $target_version } @mysql_versions;
            foreach my $version (@versions_to_disable) {
                $self->{'repos_obj'}->disable_repo_target( target_name => $self->_repo_id($version) );
            }
        }

        # install_repo disables the last repo section in a .repo file. Make sure the repo id we need is
        # enabled.
        $self->{'repos_obj'}->enable_repo_target( target_name => $self->_repo_id($target_version) );

        # on systems with modular packages (like CentOS 8) if a system module is enabled that provides the same packages
        # then dnf will filter out packages in the module from all repos. We disable the module so that the
        # community RPMs can be installed from the repo we just enabled above.
        # See: man dnf.modularity
        $self->{'syspkgs_obj'}->disable_module('mysql');

        # Some MariaDB-* RPMs declares that they provide "mysql*" dependencies too, and this causes the
        # community MariaDB RPMs to be filtered if the _mysql_ module is active.
        # `dnf repoquery --provides mariadb-server --repo MariaDB103`
        $self->{'syspkgs_obj'}->disable_module('mariadb');
    }

    return 1;
}

sub _get_repo_rpm_filename ( $self, $target_version ) {
    my $rpm_file = $self->{repos_obj}->_find_pkg( $self->_repo_name_from_version($target_version) );
    if ( -l $rpm_file ) {
        require Cwd;
        $rpm_file = Cwd::abs_path($rpm_file);
    }
    return $rpm_file;
}

sub _repo_id {
    my ( $self, $target_version ) = @_;
    return $self->_repo_name_from_version($target_version);
}

1;
