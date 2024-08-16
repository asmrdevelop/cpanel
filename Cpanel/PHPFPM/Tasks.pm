package Cpanel::PHPFPM::Tasks;

# cpanel - Cpanel/PHPFPM/Tasks.pm                  Copyright 2022 cPanel, L.L.C.
#                                                           All rights reserved.
# copyright@cpanel.net                                         http://cpanel.net
# This code is subject to the cPanel license. Unauthorized copying is prohibited

use cPstrict;

use Cpanel::Config::Httpd::EA4 ();
use Cpanel::ServerTasks        ();

use Try::Tiny;

sub _make_service_start ( $php_version, $should_restart, $logger ) {

    return if !Cpanel::Config::Httpd::EA4::is_ea4();
    if ( $php_version !~ m/^ea-php\d{2}/ ) {
        $logger->warn("\$php_version “$php_version” does not match expected format “ea-phpNN”.");
    }
    my $service = $php_version . "-php-fpm";

    require Cpanel::Init;
    my $_init_obj = Cpanel::Init->new();
    my $retval    = $_init_obj->run_command_for_one( ( $should_restart ? 'enable' : 'disable' ), $service );
    if ( !$retval ) {
        warn "Cpanel::PHPFPM - Unable to set “$service” to start or stop on reboots: $retval\n";
    }

    return;
}

sub ensure_all_fpm_versions_start_on_reboot {
    return if !Cpanel::Config::Httpd::EA4::is_ea4();

    require Cpanel::PHP::Config;
    my $php_version_info = Cpanel::PHP::Config::get_php_version_info();
    my @php_versions     = @{ $php_version_info->{'versions'} };

    require Cpanel::Logger;
    my $logger = Cpanel::Logger->new();
    $logger->info("ensure_all_fpm_versions_start_on_reboot: started");

    require Cpanel::PHPFPM::Controller;

    # make sure fpm services start on reboot
    foreach my $php_version (@php_versions) {

        # Check for config files
        my $should_start = Cpanel::PHPFPM::Controller::phpfpm_version_users_configured($php_version);
        if ($should_start) {
            $logger->info("php-fpm: rebuild_files: attempting to have $php_version-php-fpm start on reboot");
        }
        else {
            $logger->info("php-fpm: rebuild_files: attempting to have $php_version-php-fpm NOT start on reboot");
        }

        _make_service_start( $php_version, $should_start, $logger );
    }

    $logger->info("ensure_all_fpm_versions_start_on_reboot: completed");

    return 1;
}

sub bg_ensure_fpm_on_boot {
    my $ret = eval { Cpanel::ServerTasks::schedule_task( ['PHPFPMTasks'], 240, 'ensure_fpm_on_boot' ); };

    if ($@) {
        my $err = $@;
        require Cpanel::Logger;
        my $logger = Cpanel::Logger->new();
        $logger->warn("Could not ensure fpm will start on boot: $err");
        return 0;
    }

    return 1;
}

sub queue_enable_fpm_domain_in_dir {
    my ($domain) = @_;

    require Cpanel::PHPFPM::EnableQueue::Adder;
    Cpanel::PHPFPM::EnableQueue::Adder->add($domain);

    return;
}

sub queue_rebuild_fpm_domain_in_dir {
    my ($domain) = @_;

    require Cpanel::PHPFPM::RebuildQueue::Adder;
    Cpanel::PHPFPM::RebuildQueue::Adder->add($domain);

    return;
}

sub perform_rebuilds {
    my ($logger) = @_;

    require Cpanel::PHPFPM::RebuildQueue::Harvester;
    require Cpanel::PHP::Config;
    require Cpanel::PHPFPM;

    require Cpanel::Logger;
    $logger //= Cpanel::Logger->new();

    $logger->info("Rebuilding ...");

    my @domains_to_process;
    Cpanel::PHPFPM::RebuildQueue::Harvester->harvest( sub { push @domains_to_process, shift } );

    my $php_config_ref;
    if (@domains_to_process) {
        $php_config_ref = Cpanel::PHP::Config::get_php_config_for_domains_consider_addons( \@domains_to_process );
        $logger->info("Dequeued the following domains");
        foreach my $domain (@domains_to_process) {
            $logger->info("Dequeued $domain");
        }
    }
    else {
        $logger->info("Rebuilding All domains");
        $php_config_ref = Cpanel::PHP::Config::get_php_config_for_all_domains();
    }

    Cpanel::PHPFPM::rebuild_files(
        $php_config_ref,
        $Cpanel::PHPFPM::SKIP_HTACCESS,
        !$Cpanel::PHPFPM::SKIP_RESTART,    # Third arg is "do restart", so do the opposite of skip value
        $Cpanel::PHPFPM::REBUILD_VHOSTS,
    );

    $logger->info("Rebuild Complete");

    return;
}

1;
