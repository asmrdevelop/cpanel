package Cpanel::Update::Blocker::MySQL;

# cpanel - Cpanel/Update/Blocker/MySQL.pm          Copyright 2022 cPanel, L.L.C.
#                                                           All rights reserved.
# copyright@cpanel.net                                         http://cpanel.net
# This code is subject to the cPanel license. Unauthorized copying is prohibited

use strict;
use warnings;

=encoding utf-8

=head1 NAME

Cpanel::Update::Blocker::MySQL

=head1 DESCRIPTION

Evaluate whether the cPanel update should be blocked
cause of an unsupported MySQL version.

This blocker can also autoupgrade MySQL 5.5 installs
to MySQL 5.7, given that the server meets the
following conditions:

    * Has a local MySQL server running version <= 5.5
    * Has no databases (outside of the 'system' ones)
    * The MySQL55 RPMS are cPanel-provided RPMs

Then the server administrator is notified about this
the soon-to-be unsupported MySQL instance, and given
30 days to act (either perform the upgrade themselves,
or create a database to no longer meet the conditions
for the automatic upgrade).

If they take no action, then an automatic upgrade
to MySQL 5.7 is attempted.

=cut

use Try::Tiny;

use Cpanel::Pkgr                              ();
use Cpanel::LoadFile                          ();
use Cpanel::Exception                         ();
use Cpanel::LoadModule                        ();
use Cpanel::Update::Logger                    ();
use Cpanel::Config::CpConfGuard               ();
use Cpanel::MysqlUtils::Versions              ();
use Cpanel::RPM::Versions::Directory          ();
use Cpanel::MysqlUtils::MyCnf::Basic          ();
use Cpanel::Update::Blocker::Constants::MySQL ();

use constant UPGRADE_TOUCHFILE => '/var/cpanel/mysql55_autoupgrade_time';

my @SUPPORTED_MYSQL_RELEASES          = Cpanel::Update::Blocker::Constants::MySQL::SUPPORTED_MYSQL_RELEASES();
my @SUPPORTED_MARIADB_RELEASES        = Cpanel::Update::Blocker::Constants::MySQL::SUPPORTED_MARIADB_RELEASES();
my $MINIMUM_RECOMMENDED_MYSQL_RELEASE = Cpanel::Update::Blocker::Constants::MySQL::MINIMUM_RECOMMENDED_MYSQL_RELEASE();

=head1 CLASS METHODS

=head2 new($args_hr)

Construtor.

=head3 INPUT

You can pass the following optional keys in C<$args_hr>:

=over

=item logger

A C<Cpanel::Update::Logger> object.

=item cpconfig

A hashref containing cpanel.config data, usually returned by

    Cpanel::Config::CpConfGuard->new( 'loadcpconf' => 1 )->config_copy();

=back

=head3 RETURNS

=over

=item C<Cpanel::Update::Blocker::MySQL> object

=back

=cut

sub new {
    my ( $class, $args ) = @_;

    my $self = $class->_init($args);
    return bless $self, $class;
}

sub _init {
    my ( $class, $args ) = @_;

    my $logger   = $args->{'logger'}   || Cpanel::Update::Logger->new( { 'stdout' => 1, 'log_level' => 'debug' } );
    my $cpconfig = $args->{'cpconfig'} || Cpanel::Config::CpConfGuard->new( 'loadcpconf' => 1 )->config_copy();

    my $rpmv          = Cpanel::RPM::Versions::Directory->new( { 'mysql_targets' => [ Cpanel::MysqlUtils::Versions::get_rpm_target_names( Cpanel::MysqlUtils::Versions::get_installable_versions() ) ] } );
    my $mysql_version = $cpconfig->{'mysql-version'} || '';

    return {
        'logger'          => $logger,
        'rpmv'            => $rpmv,
        'mysql_version'   => $mysql_version,
        'upgrade_started' => 0,
    };
}

=head1 OBJECT METHODS

=head2 mysql_version_in_cpconfig()

=head3 INPUT

None.

=head3 RETURNS

The C<mysql-version> value from the cpanel.config. This can
be a blank value if the key is missing from cpanel.config,
or if the value is left intentionally blank.

=cut

sub mysql_version_in_cpconfig { return $_[0]->{'mysql_version'}; }

=head2 is_mysql_version_valid()

This evaluates whether the system has a MySQL version that is
compatible with the product.

If the system meets the requirements for autoupgrade, then it will
also initialize the 'timer' and perform the autoupgrade at the end
of the timer.

=head3 INPUT

None.

=head3 RETURNS

Returns 1 (true) or 0 (false) to indicate whether or not
the version of MySQL configured on the system is valid or not.

=cut

sub is_mysql_version_valid {
    my $self = shift;

    return $self->base_install_check() if $ENV{'CPANEL_BASE_INSTALL'};
    return 1                           if Cpanel::MysqlUtils::MyCnf::Basic::is_remote_mysql();

    if ( $self->meets_conditions_for_autoupgrade_to_mysql57() ) {
        my ( $time_passed, $time_left ) = _is_time_to_autoupgrade();

        return $self->perform_autoupgrade_and_notify()
          if $time_passed;

        $self->notify_about_pending_autoupgrade($time_left);
        return 1;
    }
    elsif ( !$self->is_mysql_supported_by_cpanel() ) {    # block if we detect a legacy MySQL version
        return 0;
    }

    return 1;
}

=head2 base_install_check()

This evaluates whether the C<mysql-version> value configured in
cpanel.config is valid for new installs.

This method is invoked as part of the C<is_mysql_version_valid> checks
if the C<CPANEL_BASE_INSTALL> environment variable is set.

=head3 INPUT

None.

=head3 RETURNS

Returns 1 (true) or 0 (false) to indicate whether or not
the system configuration is valid or not.

=cut

sub base_install_check {
    my $self = shift;

    my $mysql_version = $self->mysql_version_in_cpconfig();

    # They just wanted the default on this.
    return 1 if $mysql_version eq '';

    # only accept a valid cPanel RPMs version to install
    return 1 if grep { $mysql_version eq $_ } (
        @SUPPORTED_MYSQL_RELEASES,
        @SUPPORTED_MARIADB_RELEASES,
    );

    return 0;
}

=head2 meets_conditions_for_autoupgrade_to_mysql57()

This method evaluates whether systems running MySQL 5.5
can be autoupgraded to MySQL 5.7.

It checks for the following conditions:

    * Is running a local MySQL instance that is version <= 5.5
    * Has cpanel.config configured to use 5.5
    * Does not have the MySQL55 target set in local rpm.versions
    * The MySQL55 RPMs were provided by cPanel
    * Has no databases (outside of the 'system' ones)

=head3 INPUT

None.

=head3 RETURNS

Returns 1 (true) or 0 (false) to indicate whether or not
the system meets the conditions to autoupgraded.

=cut

sub meets_conditions_for_autoupgrade_to_mysql57 {
    my $self = shift;

    # must be a local instance running mysql <= 5.5
    return 0 if not _is_runing_mysql_55();

    $self->{'logger'}->info('[*] Evaluating if system can autoupgrade MySQL 5.5 to MySQL 5.7...');

    # cpanel.config has mysql-version=5.5
    return 0 if not $self->_is_mysql_version_in_cpconfig_set_to_55();

    # MySQL55 target is *not* set in local rpm.versions.
    # If the MySQL55 target exists in local rpm.versions, then check_cpanel_pkgs
    # does *not* remove them, causing errors during the upgrade process.
    return 0 if $self->_is_mysql55_target_set_in_local_rpm_versions();

    # is the mysql55 rpm installed - a cpanel rpm?
    return 0 if not $self->_is_mysql55_cpanel_rpm();

    # must not have any databases
    return 0 if $self->_has_user_created_databases();

    # Ensure that no issues with /etc/my.cnf.
    # These are usually reported as 'critical' and not 'fatal' errors.
    return 0 if not $self->_can_migrate_my_cnf();

    $self->{'logger'}->info('[+] System can autoupgrade MySQL 5.5 to MySQL 5.7.');

    # TODO: no users check? Eval after BOO-878
    return 1;
}

=head2 perform_autoupgrade_and_notify()

Performs the autoupgrade, and notifies the admin about the operation.

=head3 INPUT

None.

=head3 RETURNS

Returns 1 (true) or 0 (false) to indicate whether or not
the system was successfully autoupgraded to MySQL 5.7.

=cut

sub perform_autoupgrade_and_notify {
    my $self = shift;

    if ( try { Cpanel::LoadModule::load_perl_module('Whostmgr::Mysql::Upgrade') } ) {
        my ( $failed_step, $err );
        try {
            # These modules should already be loaded by Whostmgr::Mysql::Upgrade
            # but these calls exist just to be complete.
            Cpanel::LoadModule::load_perl_module('Whostmgr::Mysql::Upgrade::Warnings');
            my ( $fatal, $warnings_ar ) = Whostmgr::Mysql::Upgrade::Warnings::get_upgrade_warnings( 5.7, 5.5 );
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

                die "MySQL could not be updated due to the following: $warnings_str\n";
            }

            # NOTE: This runs in the foreground during the upcp process as
            # running it in the background *will* cause rpmdb locking issues
            # which breaks the check_cpanel_pkgs run that happens after the
            # blockers are evaluated.
            $self->{'upgrade_started'} = 1;
            $self->{'logger'}->info("[*] Attempting to autoupgrade MySQL 5.5 to MySQL 5.7...");
            $failed_step = Whostmgr::Mysql::Upgrade::unattended_upgrade(
                {
                    upgrade_type     => 'unattended_automatic',
                    selected_version => '5.7',
                }
            );
        }
        catch {
            $err = $_;
        };
        if ($err) {
            $self->{'logger'}->error("[!] MySQL autoupgrade to 5.7 failed. Error: $err");
            return $self->notify_autoupgrade_failure($err);
        }

        if ( !$failed_step ) {
            $self->{'logger'}->info("[+] MySQL was autoupgraded to 5.7 successfully.");
            unlink UPGRADE_TOUCHFILE();
            return $self->notify_autoupgrade_success();
        }

        my $last_upgrade_logpath = $self->get_last_mysqlupgrade_logpath();
        $self->{'logger'}->error( "[!] MySQL autoupgrade to 5.7 failed. " . ( $last_upgrade_logpath ? "Review the mysql upgrade log for more details: $last_upgrade_logpath" : "" ) );
        return $self->notify_autoupgrade_failure();
    }

    return $self->notify_autoupgrade_failure('Failed to load Whostmgr::Mysql::Upgrade to perform upgrade.');
}

=head2 get_last_mysqlupgrade_logpath()

Looks in the C<Whostmgr::Mysql::Upgrade::LOG_BASE_DIR> directory, and
attempts to find the path to the 'latest' unattended_upgrade.log associated
with an mysql upgrade.

=head3 INPUT

None.

=head3 RETURNS

Returns the path to the latest mysql upgrade log.
If no such file is found, then it returns an empty string.

=cut

sub get_last_mysqlupgrade_logpath {
    my $self = shift;

    return '' if not $self->{'upgrade_started'};
    if ( opendir my $dh, $Whostmgr::Mysql::Upgrade::LOG_BASE_DIR ) {
        my ( $latest_path, $_time ) = ( undef, 2**31 - 1 );

        while ( defined( my $f = readdir($dh) ) ) {
            next if $f !~ m/^mysql_upgrade\./;

            my $path = $Whostmgr::Mysql::Upgrade::LOG_BASE_DIR . '/' . $f;
            next if !-d $path;

            ( $latest_path, $_time ) = ( $path, -M _ ) if ( -M $path < $_time );
        }

        return "$latest_path/unattended_upgrade.log"
          if $latest_path && -e "$latest_path/unattended_upgrade.log";
    }

    return '';
}

my $notification_args = {
    'origin'            => 'upcp',
    'service_name'      => 'MySQL 5.5',
    'replacement'       => 'MySQL 5.7',
    'last_version'      => '11.78',
    'days_left'         => undef,
    'hrs_left'          => undef,
    'failed_to_convert' => 0,
    'script_output'     => '',
};

=head2 notify_about_pending_autoupgrade()

Notify the administrator about the pending autoupgrade.

=head3 INPUT

None.

=head3 RETURNS

None.

=cut

sub notify_about_pending_autoupgrade {
    my ( $self, $time_left ) = @_;

    my $days_left = $notification_args->{'days_left'} = int( $time_left / ( 24 * 60 * 60 ) );
    my $hrs_left  = $notification_args->{'hrs_left'}  = ( $time_left / ( 60 * 60 ) ) % 24;

    $self->{'mysql-reason'} =
      qq{Future releases of cPanel & WHM may not be compatible with your local MySQL version. You can upgrade your local MySQL server to a version greater than $MINIMUM_RECOMMENDED_MYSQL_RELEASE using the <a href="../scripts/mysqlupgrade">MySQL/MariaDB Upgrade</a> interface. If you take no action, the system will automatically upgrade to MySQL 5.7 in $days_left day(s) and $hrs_left hour(s).};

    _notify($notification_args);
    return;
}

=head2 notify_autoupgrade_failure()

Sends a notification about a failed autoupgrade attempt.

=head3 INPUT

None.

=head3 RETURNS

Returns 0 (false) to indicate that the blocker *should*
be triggered.

=cut

sub notify_autoupgrade_failure {
    my ( $self, $reason ) = @_;

    undef $notification_args->{'days_left'};
    undef $notification_args->{'hrs_left'};
    $notification_args->{'failed_to_convert'} = 1;
    $notification_args->{'script_output'}     = $reason // 'Unknown Error. Review the upgrade log for details.';

    my $last_upgrade_logpath = $self->get_last_mysqlupgrade_logpath();
    $notification_args->{'script_output'} .= "Review the mysql upgrade log for more details: $last_upgrade_logpath"
      if $last_upgrade_logpath;

    _notify($notification_args);
    return 0;
}

=head2 notify_autoupgrade_success()

Sends a notification about a successful autoupgrade attempt.

=head3 INPUT

None.

=head3 RETURNS

Returns 1 (true) to indicate that the blocker should *not*
be triggered.

=cut

sub notify_autoupgrade_success {
    my ($self) = @_;

    undef $notification_args->{'days_left'};
    undef $notification_args->{'hrs_left'};
    $notification_args->{'failed_to_convert'} = 0;

    my $last_upgrade_logpath = $self->get_last_mysqlupgrade_logpath();
    $notification_args->{'script_output'} .= "Review the mysql upgrade log for more details: $last_upgrade_logpath"
      if $last_upgrade_logpath;

    _notify($notification_args);
    return 1;
}

sub _is_runing_mysql_55 {
    my $version;

    try {
        require Cpanel::MysqlUtils::Version;
        $version = Cpanel::MysqlUtils::Version::uncached_mysqlversion();
    };

    return 1 if $version <= 5.5;
    return 0;
}

sub _is_mysql_version_in_cpconfig_set_to_55 {
    my $self = shift;

    if ( $self->mysql_version_in_cpconfig() != 5.5 ) {
        $self->{'logger'}->info('[!] Unable to autoupgrade: "mysql-version" is not configured properly in /var/cpanel/cpanel.config');
        return 0;
    }

    return 1;
}

sub _is_mysql55_target_set_in_local_rpm_versions {
    my $self = shift;

    my $rpmv           = $self->{rpmv}                                                                               || return 0;
    my $target_setting = $rpmv->{'local_file_data'}->fetch( { 'section' => 'target_settings', 'key' => 'MySQL55' } ) || '';
    if ( $target_setting eq 'installed' or $target_setting eq 'unmanaged' ) {
        $self->{'logger'}->info("[!] Unable to autoupgrade: the MySQL55 target is set to '$target_setting' in the rpm.versions system");
        return 1;
    }

    return 0;
}

sub _is_mysql55_cpanel_rpm {
    my $self = shift;
    return 1 if $self->_target_setting('MySQL55-server');
    $self->{'logger'}->info('[!] Unable to autoupgrade: the MySQL55 packages installed are not provided cPanel');
    return 0;
}

sub _has_user_created_databases {
    my $self = shift;

    my %databases;
    my $fetched_dblist = 0;
    try {
        Cpanel::LoadModule::load_perl_module('Cpanel::MysqlUtils::Connect');
        my $dbh = Cpanel::MysqlUtils::Connect::get_dbi_handle();

        my $sth = $dbh->prepare('show databases;') or die $dbh->errstr;
        $sth->execute()                            or die $dbh->errstr;

        while ( my $db = $sth->fetchrow_array() ) {
            $databases{$db} = 1;
        }

        $sth->finish;
        $fetched_dblist++;
    }
    catch {
        $self->{'logger'}->warning("[!] Unable to autoupgrade: Errors encounterd when fetching list of MySQL databases.");
        $self->{'logger'}->warning( "[!] Errors: " . Cpanel::Exception::to_string_no_id($_) );
    };

    # if we can't fetch the dblist then
    # do *not* allow the autoupgrade.
    return 1 if !$fetched_dblist;

    my %mysql55_system_dbs = map { $_ => 1 } qw(information_schema performance_schema mysql);
    foreach my $db ( keys %databases ) {

        # if the db is not a 'system' db, then
        # prevent autoupgrade.
        if ( not exists $mysql55_system_dbs{$db} ) {
            $self->{'logger'}->info("[!] Unable to autoupgrade: there are user created databases present (ex: '$db')");
            return 1;
        }
    }

    return 0;
}

sub _can_migrate_my_cnf {
    my $self = shift;

    my ( $possible_to_migrate, $err );
    try {
        Cpanel::LoadModule::load_perl_module('Cpanel::ConfigFiles');
        Cpanel::LoadModule::load_perl_module('Cpanel::MysqlUtils::MyCnf::Migrate');
        $possible_to_migrate = Cpanel::MysqlUtils::MyCnf::Migrate::possible_to_migrate_my_cnf_file( $Cpanel::ConfigFiles::MYSQL_CNF, 5.5, 5.7 );
    }
    catch {
        $err = $_;
    };
    if ( $err || !$possible_to_migrate ) {
        $self->{'logger'}->info( "[!] Unable to autoupgrade: The system detected issues with the current “/etc/my.cnf” file. These issues may interfere with the upgrade process" . ( $err ? ":\n" . join( "\n", map { "\t$_" } split( "\n", $err ) ) : '.' ) );
        return 0;
    }

    return 1;
}

sub _is_time_to_autoupgrade {
    _set_autoupgrade_file();
    return _check_autoupgrade_time();
}

sub _check_autoupgrade_time {
    my $time_to_check = Cpanel::LoadFile::loadfile( UPGRADE_TOUCHFILE() );
    chomp $time_to_check;

    my $curtime = time();
    if ( $time_to_check <= $curtime ) {
        return ( 1, 0 );
    }

    return ( 0, $time_to_check - $curtime );
}

sub _set_autoupgrade_file {
    return if -e UPGRADE_TOUCHFILE();

    if ( open my $fh, '>', UPGRADE_TOUCHFILE() ) {
        print $fh time() + ( 30 * 86400 );    # 30 days from now.
        close $fh;
    }

    return;
}

=head2 is_mysql_supported_by_cpanel()

Checks the following conditions in the C<rpm.versions>:

    * No 'blocked' MySQL versions are configured to be installed.
    * If any of the 'supported' MySQL versions are configured to be installed.

=head3 INPUT

None.

=head3 RETURNS

Returns 0 (false) if any of the blocked MySQL versions are configured to be installed.
Returns 1 (true) if any of the supported MySQL versions are configured to be installed.

Return 1 if neither of those conditions are met (i.e., the MySQL rpms are shipped via yum, etc)

=cut

sub is_mysql_supported_by_cpanel {
    my $self = shift or die;

    # that rule can be simplified to:
    # BLOCK if cpanel.config < 5.5 && ( target ne 'unmanaged' && target ne 'uninstalled' )
    # view http://blog.cpanel.net/mysql-mariadb/

    # Note:
    # we just want to block customers using one of the unsupported cPanel MySQL RPMs
    # customer using their own RPMs are still allowed to upgrade
    # customers using old cPanel RPMs but setting the target as unmanaged are also authorized to upgrade

    # check if one of the unsupported MySQL rpm is installed
    my $rpmv = $self->{rpmv} || return 0;

    # manage cases where the current mysql-version is empty
    #   but we have data coming from the local.settings
    foreach my $version ( Cpanel::Update::Blocker::Constants::MySQL::BLOCKED_MYSQL_RELEASES() ) {
        my $target_number = $version;
        $target_number =~ s/\.//;
        my $target         = 'MySQL' . $target_number;
        my $target_setting = $rpmv->fetch( { 'section' => 'target_settings', 'key' => $target } ) || '';
        $target_setting = $self->_double_check_mysqltarget_setting( $target, $target_setting );

        if ( $target_setting eq 'installed' ) {
            $self->{'mysql-reason'} = 'Newer releases of cPanel & WHM are not compatible with your local MySQL version: ' . $version . '.' . ' You must upgrade your local MySQL server to a version greater or equal to ' . $MINIMUM_RECOMMENDED_MYSQL_RELEASE . ' using the <a href="../scripts/mysqlupgrade">MySQL/MariaDB Upgrade</a> interface.';
            return 0;
        }
    }

    foreach my $version (@SUPPORTED_MYSQL_RELEASES) {
        my $target_number = $version;
        $target_number =~ s/\.//;
        my $target_setting = $rpmv->fetch( { 'section' => 'target_settings', 'key' => 'MySQL' . $target_number } ) || '';
        return 1 if $target_setting eq 'installed';
    }

    return 1;
}

# we cannot trust the uninstalled value
#   cpanel.config will be corrected by Cpanel::CpConfGuard
#   we need to be sure that the RPM is not there
sub _double_check_mysqltarget_setting {
    my ( $self, $target, $target_setting ) = @_;

    # only auto correct the uninstalled value
    return $target_setting unless $target && $target_setting && $target_setting eq 'uninstalled';
    return $self->_target_setting("${target}-server") || $target_setting;
}

sub _target_setting {
    my ( $self, $target ) = @_;

    my $v = Cpanel::Pkgr::get_package_version($target);
    return 'installed' if $v && $v =~ m/\.cp\d+$/;

    return;
}

sub _notify {
    my $notification_args = shift;

    if ( try { Cpanel::LoadModule::load_perl_module('Cpanel::iContact::Class::Update::ServiceDeprecated') } ) {
        _send_icontact_class_notification(
            'class'            => 'Update::ServiceDeprecated',
            'application'      => 'Update::ServiceDeprecated',
            'constructor_args' => [%$notification_args],
        );
    }
    else {
        my ( $subject, $message ) = _fetch_legacy_autoupgrade_notification($notification_args);
        _send_icontact_noclass_notification( $subject, $message );
    }

    return 1;
}

sub _send_icontact_class_notification {
    my %notification_args = @_;

    require Cpanel::Notify;
    return Cpanel::Notify::notification_class(%notification_args);
}

sub _send_icontact_noclass_notification {
    my ( $subject, $message ) = @_;

    require Cpanel::iContact;
    return Cpanel::iContact::icontact(
        'application' => 'upcp',
        'subject'     => $subject,
        'message'     => $message,
    );
}

sub _fetch_legacy_autoupgrade_notification {
    my $notification_args = shift;

    my ( $subject, $message );
    if ( defined $notification_args->{'days_left'} || defined $notification_args->{'hrs_left'} ) {
        my $days_left = ( defined $notification_args->{'days_left'} ? $notification_args->{'days_left'} : 0 );
        my $hrs_left  = ( defined $notification_args->{'hrs_left'}  ? $notification_args->{'hrs_left'}  : 0 );

        $subject = "The system will automatically upgrade $notification_args->{'service_name'} to $notification_args->{'replacement'} in $days_left day(s) and $hrs_left hour(s) in order to continue receiving updates.";
        $message = <<END_OF_MESSAGE;
The system is running a deprecated and soon-to-be unsupported service: $notification_args->{'service_name'}

The last version of cPanel & WHM to support this service is $notification_args->{'last_version'}. To ensure that your system can upgrade to a newer version of cPanel & WHM, upgrade $notification_args->{'service_name'} to $notification_args->{'replacement'} with using the MySQL/MariaDB Upgrade interface in WHM.

If you take no action, cPanel & WHM will automatically upgrade $notification_args->{'service_name'} to $notification_args->{'replacement'} in $days_left day(s) and $hrs_left hour(s).

END_OF_MESSAGE
    }
    else {
        if ( $notification_args->{'failed_to_convert'} ) {
            $subject = $message = "The system failed to upgrade $notification_args->{'service_name'} to $notification_args->{'replacement'}";
        }
        else {
            $subject = $message = "The deprecated service, $notification_args->{'service_name'}, has been upgraded to $notification_args->{'replacement'}.";
        }

        $message .= "\n\nReview the log for further details:\n\n$notification_args->{'script_output'}\n\n"
          if ( $notification_args->{'script_output'} );
    }

    return ( $subject, $message );
}

1;
