package Whostmgr::Config::Restore::System::Mysql;

# cpanel - Whostmgr/Config/Restore/System/Mysql.pm Copyright 2022 cPanel, L.L.C.
#                                                           All rights reserved.
# copyright@cpanel.net                                         http://cpanel.net
# This code is subject to the cPanel license. Unauthorized copying is prohibited

use strict;
use warnings;

use parent qw( Whostmgr::Config::Restore::Base );

use Whostmgr::Config::Mysql     ();
use Whostmgr::Mysql::Upgrade    ();
use Cpanel::Config::LoadCpConf  ();
use Cpanel::Config::LoadConfig  ();
use Cpanel::Config::Httpd::EA4  ();
use Cpanel::MysqlUtils::Restart ();
use Cpanel::MysqlUtils::Running ();

use constant _version => '1.0.0';

sub restore {
    my ( $self, $parent ) = @_;

    my $restore_mysql_version;

    my $backup_path = $parent->{'backup_path'};
    return ( 0, "Backup Path must be an absolute path" ) if ( $backup_path !~ /^\// );

    return ( 0, "version file missing from backup" ) if !-e "$backup_path/cpanel/system/mysql/version";

    # read configuration files
    foreach my $cfg_file ( keys %Whostmgr::Config::Mysql::files ) {
        my $special  = $Whostmgr::Config::Mysql::files{$cfg_file}{'special'};
        my @fullpath = split( /\//, $cfg_file );
        my $basefile = $fullpath[-1];
        pop @fullpath;
        my $dir = join( '/', @fullpath );

        if ( $Whostmgr::Config::Mysql::files{$cfg_file}->{'special'} eq "present" ) {
            $parent->{'files_to_copy'}->{"$backup_path/cpanel/system/mysql/$basefile"} = { 'dir' => $dir, "file" => "$basefile" };
        }
        elsif ( $special eq 'cpanel_config' ) {
            my $temp_config = {};
            Cpanel::Config::LoadConfig::loadConfig( "$backup_path/cpanel/system/mysql/$basefile", $temp_config, '=' );
            $restore_mysql_version = $temp_config->{'mysql-version'} || 1;
        }

    }

    # do the actual upgrade
    # TODO: split this into it's own method for the sake of cleanliness
    my $cpconf = Cpanel::Config::LoadCpConf::loadcpconf();

    if ( $restore_mysql_version != $cpconf->{'mysql-version'} ) {
        if ( $restore_mysql_version < $cpconf->{'mysql-version'} ) {
            return ( 0, 'This server has a newer version of mysql than the one being migrated from, aborting.' );
        }

        my $mysql_upgrade_params = {
            'selected_version' => $restore_mysql_version,
            'upgrade_type'     => 'unattended_automatic',
            'ea_version'       => Cpanel::Config::Httpd::EA4::is_ea4() ? 4 : 3,
        };

        my $logdir                = Whostmgr::Mysql::Upgrade::_get_logdir();
        my $mysql_upgrade_failure = Whostmgr::Mysql::Upgrade::unattended_upgrade($mysql_upgrade_params);
        if ($mysql_upgrade_failure) {
            return ( 0, 'MySQL version upgrade failed. Check the logs in ' . $logdir . ' for more information.' );
        }
    }

    return ( 1, __PACKAGE__ . ": ok", { 'version' => $self->_version() } );
}

sub post_restore {
    Cpanel::MysqlUtils::Restart::restart();
    return ( 0, "Mysql failed to restart." ) if ( !Cpanel::MysqlUtils::Running::is_mysql_running() );

    return __PACKAGE__->SUPER::post_restore();
}

1;
