package Whostmgr::Mysql::Upgrade::Warnings;

# cpanel - Whostmgr/Mysql/Upgrade/Warnings.pm      Copyright 2022 cPanel, L.L.C.
#                                                           All rights reserved.
# copyright@cpanel.net                                         http://cpanel.net
# This code is subject to the cPanel license. Unauthorized copying is prohibited

use cPstrict;

use Cpanel::PwCache                      ();
use Cpanel::Exception                    ();
use Cpanel::MariaDB                      ();
use Cpanel::Filesys::Info                ();
use Cpanel::SafeRun::Errors              ();
use Cpanel::MysqlUtils::Check            ();
use Cpanel::MysqlUtils::Compat           ();
use Cpanel::MysqlUtils::Dir              ();
use Cpanel::MysqlUtils::TempDir          ();
use Cpanel::MysqlUtils::MyCnf::Full      ();
use Cpanel::MysqlUtils::MyCnf::Basic     ();
use Cpanel::MysqlUtils::MyCnf::Migrate   ();
use Cpanel::ConfigFiles                  ();
use Cpanel::MysqlUtils::Connect          ();
use Cpanel::OS                           ();
use Cpanel::Context                      ();
use Cpanel::Config::LoadCpConf           ();
use Cpanel::DiskCheck                    ();
use Cpanel::AccessIds::ReducedPrivileges ();
use Cpanel::FileUtils::Write             ();
use Cpanel::TempFile                     ();
use Cpanel::Update::InProgress           ();
use Cpanel::Database                     ();
use Cpanel::FindBin                      ();

use Try::Tiny;

our @SEVERITY_LEVELS = (qw/Fatal Critical Normal/);    # used for final sorting below

##
## TODO: this function was moved from Whostmgr::Mysql::Upgrade.  It should
## be refactored but that is outside the scope of the MariaDB problem.
##
## Returns: ( $fatal_yn, @warnings )
##  … where each @warnings is: {
##      severity => one of: 'Critical', 'Fatal', 'Normal'
##      message => '...',
##  }
##
sub get_upgrade_warnings ( $selected_version, $current_version ) {
    my @warnings         = ();
    my $fatal            = 0;
    my $version_warnings = [];

    # Each warning is a hashref with severity => (Fatal|Important|Normal) and message => warning text

    my $current_db                   = Cpanel::Database->new();
    my $current_version_product_name = $current_db->type;

    my $selected_version_product_name =
      Cpanel::MariaDB::version_is_mariadb($selected_version)
      ? 'MariaDB'
      : 'MySQL';

    # Resetting the singleton to ensure that we aren't recycling the singleton for the currently installed database version.
    # We will reset again afterwards to ensure that future instantiations don't get mixed up with this prospective database version.
    my $selected_db      = Cpanel::Database->new( { 'reset' => 1, 'db_type' => $selected_version_product_name, 'db_version' => $selected_version } );
    my @version_warnings = $selected_db->get_upgrade_warnings( 'from_version' => $current_version, 'from_type' => $current_version_product_name );
    my @config_warnings  = $selected_db->get_config_upgrade_warnings( 'from_version' => $current_version, 'from_type' => $current_version_product_name );
    Cpanel::Database::reset_singleton();

    push( @warnings, @version_warnings );
    push( @warnings, process_config_warnings(@config_warnings) );

    # Check root password for issues
    my ( $password_status, $password_error ) = check_root_mysql_pass();
    if ( !$password_status ) {
        push @warnings, { 'severity' => 'Fatal', 'message' => $password_error };
    }

    # Check for my.cnf migration issues
    my $possible_to_migrate;
    eval { $possible_to_migrate = Cpanel::MysqlUtils::MyCnf::Migrate::possible_to_migrate_my_cnf_file( $Cpanel::ConfigFiles::MYSQL_CNF, $selected_version, $current_version ); };
    if ( $@ || !$possible_to_migrate ) {
        require Cpanel::Logger;
        my $append = $@ ? ":\n" . join( "\n", map { "\t$_" } split( "\n", $@ ) ) : '.';
        Cpanel::Logger->new->info( "The system detected issues with the current “/etc/my.cnf” file. These issues may interfere with the upgrade to $selected_version_product_name $selected_version" . $append );
        push @warnings,
          {
            'severity' => 'Critical',
            'message'  => "The system detected issues with the current “/etc/my.cnf” file. These issues may interfere with the upgrade to $selected_version_product_name $selected_version" . ( $@ ? ":</br><pre>$@</pre>" : '.' ),
          };
    }

    my $mysqldatadir   = Cpanel::MysqlUtils::Dir::getmysqldir();
    my $database_files = _get_database_files($mysqldatadir);

    # ISAM tables
    if ( $database_files =~ /\.ISM$/m ) {
        push @warnings,
          {
            'severity' => 'Fatal',
            'message'  => 'ISAM tables are still in use on this system.  These tables must be manually upgraded to MyISAM before an upgrade of the MySQL server is possible.'
          };
    }

    # Disk space check
    my $usage = _get_datadir_usage($mysqldatadir);
    if ( $usage =~ m/^(\d+)\s+\Q$mysqldatadir\E/m ) {
        $usage = $1;
        my %dfout = Cpanel::Filesys::Info::filesystem_info($mysqldatadir);
        if ( !exists $dfout{'blocks_free'} ) {

            # Cant determine free space
            push @warnings,
              {
                'severity' => 'Critical',
                'message'  => "Unable to determine how much free space is available to $current_version_product_name.  Please ensure there is sufficient space for the $current_version_product_name database files to grow during the upgrade process."
              };
        }
        elsif ( $dfout{'blocks_free'} <= 0 ) {

            # 0% free is a fatal warning
            push @warnings,
              {
                'severity' => 'Fatal',
                'message'  => "The partition that contains the $current_version_product_name databases on this system has no free space.  No upgrade is possible until additional space is made available for $current_version_product_name."
              };
            $fatal = 1;
        }
        elsif ( $dfout{'blocks_free'} < ( $usage / 20 ) ) {

            # 5% free is a critical warning
            push @warnings,
              {
                'severity' => 'Critical',
                'message'  => "The partition that contains the $current_version_product_name databases on this system has very little free space compared to the size of the $current_version_product_name database files.  It is not recommended that you proceed without freeing additional drive space for $current_version_product_name."
              };
        }
        elsif ( $dfout{'blocks_free'} < ( $usage / 10 ) ) {

            # 10% free is a normal warning
            push @warnings,
              {
                'severity' => 'Normal',
                'message'  => "The partition that contains the $current_version_product_name databases on this system has free space totally less than 10% of the size of the $current_version_product_name database files.  It is recommended that you free additional space for $current_version_product_name before proceeding."
              };
        }
    }
    else {

        # Cant determine space usage of mysql data dir
        push @warnings,
          {
            'severity' => 'Normal',
            'message'  => "Unable to determine how much disk space the $current_version_product_name data directories are using.  Please ensure there is sufficient space for the $current_version_product_name database files to grow during the upgrade process."
          };
    }

    my $old_style_password_users = eval { _have_old_style_passwords() };
    if ($@) {
        push( @warnings, { 'severity' => 'Critical', 'message' => $@ } );
    }

    # Critical but not fatal because some administrators may prefer to ignore the problem for
    # abandoned / defunct accounts, or solve the problem later.
    if ( $selected_version >= 5.6 && $old_style_password_users && $old_style_password_users->@* ) {
        push @warnings, {
            'severity' => 'Critical',
            'message', => <<EOM
The following users use pre-4.1-style MySQL passwords: @{ $old_style_password_users || ['(unknown)'] }
<br /><br />
We recommend that you update all of your accounts to longer MySQL password hashes before you perform this
upgrade. Failure to do so could disrupt database access for accounts or applications that use pre-4.1-style
MySQL passwords.
EOM
        };
    }

    # CPANEL-15633: MariaDB now uses systemd hardening which would break upgrades on systems with non-standard datadir configurations.
    if ( $selected_version >= 10.1 && _maria_systemd_protected_path($mysqldatadir) ) {
        push @warnings, {
            'severity' => 'Fatal',
            'message'  => <<EOM
As of MariaDB 10.1.16, the data directory cannot reside in /home, /usr, /etc, /boot, or /root directories on systemd equipped systems.
<br /><br />
You must move your $current_version_product_name data directory outside of these directories before continuing with this upgrade.
EOM
        };
    }

    my $tmpdir = Cpanel::MysqlUtils::TempDir::get_mysql_tmp_dir();
    if ( Cpanel::PwCache::getpwnam_noshadow('mysql') ) {
        my ( $write_ok, $write_msg ) = _can_mysql_write_to_tmpdir($tmpdir);
        if ( !$write_ok ) {
            push @warnings, {
                'severity' => 'Fatal',
                'message'  => <<EOM
The user “mysql” cannot write to the configured temporary file directory “$tmpdir”: $write_msg
<br /><br />
“mysql” needs permission to create files in this directory, and enough free space must exist to write temporary files.
EOM
            };
        }
    }

    my ( $tmp_ok, $tmp_msg ) = _tmpdir_has_256M_free($tmpdir);
    if ( !$tmp_ok ) {
        push @warnings, {
            'severity' => 'Fatal',
            'message'  => <<EOM
The temporary file directory “$tmpdir” does not contain enough free space: $tmp_msg
<br /><br />
You must ensure that the temporary file directory contains at least 256MB of free space. It may corrupt your databases if the temporary file directory
becomes full during an update.
EOM
        };
    }

    if ( Cpanel::Update::InProgress->is_on() ) {
        push @warnings, {
            'severity' => 'Fatal',
            'message'  => <<EOM
A cPanel &amp; WHM update is in progress.
<br /><br />
You must wait until the update is complete before attempting to upgrade $current_version_product_name.
EOM
        };
    }

    # modifies @warnings by reference
    _sort_warnings_by_severity( \@SEVERITY_LEVELS, \@warnings );
    $fatal += scalar( grep { $_->{'severity'} eq 'Fatal' } @warnings );

    return $fatal, \@warnings;
}

sub _sort_warnings_by_severity ( $order_ref, $warnings_ref ) {
    my $ordered = {};

    # put in severity bins
    for my $warning_ref ( $warnings_ref->@* ) {
        push( $ordered->{ $warning_ref->{'severity'} }->@*, $warning_ref );
    }

    my @ordered = ();

    # flatten per severity bin based on $order_ref
    for my $severity ( $order_ref->@* ) {
        push( @ordered, $ordered->{$severity}->@* ) if ref( $ordered->{$severity} ) eq 'ARRAY';
    }

    $warnings_ref->@* = @ordered;

    return 1;
}

sub process_config_warnings (@conf_warnings) {
    my @warnings   = ();
    my $mysqld_cnf = Cpanel::MysqlUtils::MyCnf::Full::etc_my_cnf();

    return () unless defined($mysqld_cnf);
    $mysqld_cnf = $mysqld_cnf->{'mysqld'};

    for my $warn (@conf_warnings) {
        my ( $key, $value ) = ( $warn->{'config'}->@{ 'key', 'value' } );

        # This will ensure that settings with flexible names are captured
        # and will also validate that other settings are actually configured.
        $key = qr/^$key$/ unless ref($key) eq 'Regexp';
        ($key) = grep { m/$key/ } keys( $mysqld_cnf->%* );
        next unless $key;

        if ( !defined($value) ) {

            # If we reach this point, we are expecting the setting to be applied as a simple flag, and do not require a value to be assigned.
            push( @warnings, $warn->{'warning'} );
            next;
        }
        elsif ( ref($value) eq 'Regexp' ) {

            # If we reach this point, there's a chance the setting was applied as a flag without an explicit value assigned.
            # This is the same as enabling a setting, and thus we should consider it "ON"
            $mysqld_cnf->{$key} //= 'ON';

            # String values
            push( @warnings, $warn->{'warning'} ) if $mysqld_cnf->{$key} =~ m/$value/;
            next;
        }
        else {

            # The last remaining option is to handle the configured value as an integer, which is of dubious value.
            # Future revisions to this functionality will potentially want to include useful comparisons.
            push( @warnings, $warn->{'warning'} ) if $mysqld_cnf->{$key} == $value;
            next;
        }
    }
    return @warnings;
}

sub _get_database_files ($mysqldatadir) {
    return Cpanel::SafeRun::Errors::saferunnoerror( Cpanel::FindBin::findbin('find'), $mysqldatadir, '-type', 'f' );
}

sub _get_datadir_usage ($mysqldatadir) {
    return Cpanel::SafeRun::Errors::saferunallerrors(
        Cpanel::FindBin::findbin('du'), '-s', '-k',
        $mysqldatadir
    );
}

sub _tmpdir_has_256M_free ($tmpdir) {
    Cpanel::Context::must_be_list();
    return Cpanel::DiskCheck::target_has_enough_free_space_to_fit_source_sizes(
        'source_sizes'   => [ { 'raw_copy' => ( 256 * 1024**2 ) } ],
        'target'         => $tmpdir,
        'output_coderef' => sub { },
    );
}

sub _can_mysql_write_to_tmpdir ($tmpdir) {
    Cpanel::Context::must_be_list();
    my $access_ids = Cpanel::AccessIds::ReducedPrivileges->new('mysql');
    my $tf         = Cpanel::TempFile->new( { 'path' => $tmpdir } );

    my $err;
    try {
        my $file = $tf->file();
        Cpanel::FileUtils::Write::overwrite( $file, "mysql_test_data" x 1024, 0600 );
    }
    catch {
        $err = $_;
    };

    return ( 0, Cpanel::Exception::get_string($err) ) if $err;
    return ( 1, 'ok' );
}

sub check_root_mysql_pass {
    my $err_msg;
    my $password_found;

    if ( my $password = Cpanel::MysqlUtils::MyCnf::Basic::getmydbpass('root') ) {
        $password_found = 1;
        if ( $password =~ m/['"]/ ) {
            $err_msg = "The system found a malformed password (a password that contains quotes) in the /root/.my.cnf file. <A HREF=../scripts2/mysqlrootpass>Reset the root MySQL password</A> to proceed.";
        }
    }

    if ($password_found) {
        my ( $connection_ok, $connection_failure_reason, undef ) = Cpanel::MysqlUtils::Check::check_mysql_connection();
        if ( !$connection_ok && $connection_failure_reason eq 'access_denied' ) {
            $err_msg = "The system was unable to authenticate using the password in the /root/.my.cnf file. <A HREF=../scripts2/mysqlrootpass>Reset the root MySQL password</A> to proceed.";
        }

    }
    else {
        $err_msg = "The MySQL password was not found in the /root/.my.cnf file. <A HREF=../scripts2/mysqlrootpass>Reset the root MySQL password</A> to proceed.";
    }

    my $return_status = $err_msg ? 0 : 1;

    return wantarray ? ( $return_status, $err_msg ) : $return_status;
}

sub _have_old_style_passwords {
    local $SIG{__DIE__};    # We are handling any MySQL errors more gracefully,
                            # so suppress the ugly die handler.

    # Regardless of whether it's enabled, check whether any users have old-style passwords
    my @old_style;

    #There’s no point in checking this if the current DB server
    #doesn’t support old passwords to begin with.
    if ( Cpanel::MysqlUtils::Compat::has_old_password_support() ) {
        my $success = eval {
            my $dbh   = _get_dbh_handle();
            my $users = $dbh->selectall_arrayref("select distinct User,Password from mysql.user;");
            ref($users) eq 'ARRAY' or return;
            for my $row ( $users->@* ) {
                ref($row) eq 'ARRAY' or next;
                my ( $user, $pass ) = $row->@*;
                if ( $user && $pass ) {

                    # old style passwords
                    if ( length($pass) == 16 ) {
                        push( @old_style, $user );
                    }

                    # suspended old style passwords
                    elsif ( length($pass) == 17 ) {
                        push( @old_style, $user );
                    }

                    # suspended old style passwords with padded length
                    elsif ( ( length($pass) == 41 ) && ( $pass =~ /^!+([0-9a-f]{16})$/ ) ) {
                        push( @old_style, $user );
                    }
                }
            }
            1;
        };
        if ( !$success ) {
            my $exception_without_backtrace = Cpanel::Exception::get_string($@);
            die "The system failed to query the MySQL server to check for the presence of pre-4.1-style MySQL passwords. ($exception_without_backtrace) This issue could also hinder mysql_upgrade's ability to run, which could potentially leave MySQL in an unusable state if you proceed.\n";
        }
    }

    return \@old_style;
}

# for testing
*_get_dbh_handle = *Cpanel::MysqlUtils::Connect::get_dbi_handle;

sub _sys_database_exists {
    local $SIG{__DIE__};

    my $db_exists;

    eval {
        my $dbh = Cpanel::MysqlUtils::Connect::get_dbi_handle();
        $db_exists = $dbh->db_exists('sys') ? 1 : 0;
    };

    if ( $@ || !defined $db_exists ) {
        die "The update could not reach the MySQL server to check for the existence of a database named 'sys'. This issue could also hinder mysql_upgrade's ability to run, which could potentially leave MySQL in an unusable state if you proceed.\n";
    }

    return $db_exists ? 1 : 0;
}

sub _have_userstat_enabled {
    my $value = Cpanel::MysqlUtils::MyCnf::Basic::_getmydb_param(
        'userstat',
        $Cpanel::ConfigFiles::MYSQL_CNF
    );
    if ( $value && $value =~ m/^(1|on)$/i ) {
        return 1;
    }
    else {
        return 0;
    }
}

sub _have_usemysqloldpass_enabled {

    # Check whether the tweak setting is enabled
    my $conf = Cpanel::Config::LoadCpConf::loadcpconf();
    return $conf->{'usemysqloldpass'} ? 1 : 0;
}

sub _maria_systemd_protected_path {
    my $path = shift;

    return unless Cpanel::OS::is_systemd();

    return $path =~ m{^/(home|usr|etc|boot|root)/};
}

1;
