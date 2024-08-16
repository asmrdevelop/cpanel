
# cpanel - Whostmgr/API/1/Lang/PHP.pm              Copyright 2022 cPanel, L.L.C.
#                                                           All rights reserved.
# copyright@cpanel.net                                         http://cpanel.net
# This code is subject to the cPanel license. Unauthorized copying is prohibited

package Whostmgr::API::1::Lang::PHP;

use strict;
use warnings;

use Cpanel::JSON        ();
use JSON::XS            ();
use Cpanel::PHP::Config ();

use HTML::Entities                        ();
use Cpanel::Config::userdata::Cache       ();
use Cpanel::Exception                     ();
use Cpanel::Form::Param                   ();
use Cpanel::Hooks                         ();
use Cpanel::ProgLang                      ();
use Cpanel::ProgLang::Conf                ();
use Cpanel::ProgLang::Supported::php::Ini ();
use Cpanel::SafeRun::Simple               ();
use Cpanel::WebServer                     ();
use Whostmgr::API::1::Utils               ();
use Cpanel::AcctUtils::Suspended          ();
use Cpanel::PHP::Vhosts                   ();
use Cpanel::LoadModule                    ();
use Cpanel::PHPFPM::Config                ();
use Cpanel::PHPFPM::Constants             ();
use Cpanel::PHPFPM::Utils                 ();
use Cpanel::Logger                        ();
use Cpanel::Unix::PID::Tiny               ();
use Try::Tiny;

use constant NEEDS_ROLE => 'WebServer';

sub php_get_installed_versions {
    my ( $args, $metadata ) = @_;

    my $php = Cpanel::ProgLang->new( type => 'php' );
    my $ref = { 'versions' => $php->get_installed_packages() };

    Whostmgr::API::1::Utils::set_metadata_ok($metadata);

    return $ref;
}

sub php_get_system_default_version {
    my ( $args, $metadata ) = @_;

    my $php = Cpanel::ProgLang->new( type => 'php' );
    my $ref = { 'version' => $php->get_system_default_package() };

    Whostmgr::API::1::Utils::set_metadata_ok($metadata);

    return $ref;
}

sub php_set_system_default_version {
    my ( $args, $metadata ) = @_;

    _do_hook( $args, 'Lang::PHP::set_system_default_version', 'pre' );

    my $package = Whostmgr::API::1::Utils::get_length_required_argument( $args, 'version' );

    my $php    = Cpanel::ProgLang->new( type => 'php' );
    my $apache = Cpanel::WebServer->new()->get_server( 'type' => 'apache' );
    $apache->set_default_package( 'lang' => $php, 'package' => $package, 'restart' => 1 );

    _do_hook( $args, 'Lang::PHP::set_system_default_version', 'post' );

    Whostmgr::API::1::Utils::set_metadata_ok($metadata);

    return {};
}

our $old_fpm_touch_file = '/etc/cpanel/ea4/old_fpm_flag';

sub php_get_old_fpm_flag {
    my ( $args, $metadata ) = @_;

    # we support a one time dismissable dialog saying this has or has not been
    # configured the old way

    my $old_fpm;

    $old_fpm = 2 if ( -e $old_fpm_touch_file );

    if ( !defined $old_fpm ) {
        require Cpanel::PHPFPM::Inventory;
        my $inventory = Cpanel::PHPFPM::Inventory->get_inventory();
        $old_fpm = 0;
        $old_fpm = 1 if ( @{ $inventory->{'orphaned_files'} } );
    }

    Whostmgr::API::1::Utils::set_metadata_ok($metadata);

    return { 'old_fpm_flag' => $old_fpm };
}

sub php_set_old_fpm_flag {
    my ( $args, $metadata ) = @_;

    my $ret = 1;

    if ( !-e $old_fpm_touch_file ) {
        require Cpanel::FileUtils::TouchFile;

        $ret = Cpanel::FileUtils::TouchFile::touchfile( $old_fpm_touch_file, 0, 1 );
    }

    Whostmgr::API::1::Utils::set_metadata_ok($metadata);

    $ret = 0 if !defined $ret;

    return { 'success' => $ret };
}

sub php_get_vhost_versions {
    my ( $args, $metadata ) = @_;

    my $versions_ref = Cpanel::PHP::Vhosts::get_php_vhost_versions_from_php_config( Cpanel::PHP::Config::get_php_config_for_all_domains() );
    foreach my $entry (@$versions_ref) {
        $entry->{'is_suspended'} = Cpanel::AcctUtils::Suspended::is_suspended( $entry->{'account'} ) ? 1 : 0;
    }

    Whostmgr::API::1::Utils::set_metadata_ok($metadata);
    return { 'versions' => $versions_ref };
}

sub php_get_vhosts_by_version {
    my ( $args, $metadata ) = @_;
    my $package    = Whostmgr::API::1::Utils::get_length_required_argument( $args, 'version' );
    my $vhosts_ref = Cpanel::PHP::Vhosts::get_vhosts_by_php_version( $package, Cpanel::PHP::Config::get_php_config_for_all_domains() );

    Whostmgr::API::1::Utils::set_metadata_ok($metadata);
    return { 'vhosts' => $vhosts_ref };
}

sub _get_multivalued_args {
    my ( $args, $argname ) = @_;

    # The usual argument-marshalling doesn't take multi-valued
    # keys into account, so we'll do it ourselves.  We'll also
    # grab args in the CJT style (e.g. 'argname-1', 'argname-2',
    # etc.), and stuff 'em in there.  Using a hash for
    # duplicate-squashing.
    my %found;

    my $params = Cpanel::Form::Param->new();
    for my $value ( $params->param($argname) ) {
        $found{$value} = 1;
    }
    $params = Cpanel::Form::Param->new( { 'parseform_hr' => $args } );
    for my $value ( $params->param($argname) ) {
        $found{$value} = 1;
    }

    die Cpanel::Exception::create( 'MissingParameter', 'Provide the “[_1]” argument.', [$argname] )
      unless scalar %found;

    return [ sort keys %found ];
}

# no critic, I changed 1 line and refactoring will cause breakage
sub php_set_vhost_versions {    ## no critic qw(ProhibitExcessComplexity)
    my ( $args, $metadata ) = @_;

    _do_hook( $args, 'Lang::PHP::set_vhost_versions', 'pre' );

    my $package;
    my $vhosts = _get_multivalued_args( $args, 'vhost' );

    # vhost_version will contain all the vhosts and their php_versions and php_fpm stati
    # Then based on inputs, they will be modified for any values that were
    # passed in.
    die Cpanel::Exception::create( 'MissingParameter', [ 'name' => 'vhost' ] ) if !$vhosts;

    # Check if FPM is installed for the version in question
    if ( $args->{'version'} && $args->{'php_fpm'} ) {
        require Cpanel::PHPFPM::Installed;
        die Cpanel::Exception::create( 'Services::NotInstalled', [ 'service' => "$args->{'version'}-php-fpm" ] ) if !Cpanel::PHPFPM::Installed::is_fpm_installed_for_php_version_cached( $args->{'version'} );
    }

    if ( exists $args->{'php_fpm_pool_parms'} ) {
        $args->{'php_fpm_pool_parms'} = Cpanel::JSON::Load( $args->{'php_fpm_pool_parms'} );

        # Verify pool params input is fairly sane
        foreach my $integer ( 'pm_max_children', 'pm_process_idle_timeout', 'pm_max_requests' ) {
            if ( $args->{'php_fpm_pool_parms'}{$integer} !~ m/^\d+$/ || $args->{'php_fpm_pool_parms'}{$integer} < 1 ) {
                die Cpanel::Exception::create( 'InvalidParameter', "Value for “[_1]” must be a non-zero positive integer.", [$integer] );
            }
        }

        # 65326 was the max I could set fpr pm.max_children before the php-fpm would crash on startup, this default is 10x what even the largest provider should use
        if ( $args->{'php_fpm_pool_parms'}{'pm_max_children'} > 10000 or $args->{'php_fpm_pool_parms'}{'pm_max_children'} < 1 ) {
            die Cpanel::Exception::create( 'InvalidParameter', "Value for “pm_max_children” must be a non-zero positive integer equal to or less than 10000." );
        }
        if ( $args->{'php_fpm_pool_parms'}{'pm_process_idle_timeout'} > 10000000 or $args->{'php_fpm_pool_parms'}{'pm_process_idle_timeout'} < 1 ) {
            die Cpanel::Exception::create( 'InvalidParameter', "Value for “pm_process_idle_timeout” must be a non-zero positive integer equal to or less than 10000000." );
        }
        if ( $args->{'php_fpm_pool_parms'}{'pm_max_requests'} > 10000000 or $args->{'php_fpm_pool_parms'}{'pm_max_requests'} < 1 ) {
            die Cpanel::Exception::create( 'InvalidParameter', "Value for “pm_max_requests” must be a non-zero positive integer equal to or less than 10000000." );
        }
    }

    # Check for any vhosts that have the same docroot as the ones we intend to set
    # Since having the same docroot means having the same .htaccess file, they would
    # both need to be set to the same version
    my $impacted_domains = Cpanel::PHP::Config::get_impacted_domains( domains => $vhosts, exclude_children => 1 );
    if ( scalar @$impacted_domains ) {
        push @$vhosts, @$impacted_domains;
    }

    my $php_config_ref = Cpanel::PHP::Config::get_php_config_for_domains($vhosts);
    my $vhost_versions = Cpanel::PHP::Vhosts::get_php_vhost_versions_from_php_config($php_config_ref);
    $package = $args->{'version'} if exists $args->{'version'};
    foreach my $domain (@$vhost_versions) {
        my $self_config_location = $domain->{'vhost'};
        $domain->{'phpversion_source'}{'domain'} ||= '';    # prevent undef warnings
        if ( $domain->{'phpversion_source'}{'domain'} ne $self_config_location ) {
            $domain->{'version'} = 'inherit';
        }
    }

    if ( defined $package ) {
        if ( $package ne "inherit" ) {
            my $php       = Cpanel::ProgLang->new( type => 'php' );
            my $installed = $php->get_installed_packages();
            if ( !grep { $package eq $_ } @{$installed} ) {
                die Cpanel::Exception::create( 'FeatureNotEnabled', '“[_1]” is not installed on the system.', [$package] )->to_locale_string_no_id() . "\n";
            }
        }

        my $any_have_fpm_active = 0;
        for (@$vhost_versions) {
            $_->{'version'} = $package;
            $any_have_fpm_active ||= $_->{'php_fpm'};
        }
        foreach my $domain ( keys %{$php_config_ref} ) {
            $php_config_ref->{$domain}{'phpversion'} = $package;
        }

        # If they are setting the package and fpm is active, make sure fpm is installed for that package
        if ( $any_have_fpm_active and !_is_fpm_installed_for_php_version($package) ) {
            $args->{'php_fpm'} = 0;
        }
    }

    # The UI needs to pack the parameters in JSON in order to allow
    # maximum flexibility.  We need to decode it.

    if ( exists $args->{'php_fpm'} ) {
        foreach (@$vhost_versions) {
            my $self_config_location = $_->{'vhost'};
            $_->{'php_fpm_pool_parms'} = $args->{'php_fpm_pool_parms'} if exists $args->{'php_fpm_pool_parms'};
            $_->{'phpversion_source'}{'domain'} ||= '';    # prevent undef warnings

            # If we are setting php version AND enabling fpm in the same call, we can bypass the check for inherited
            if ( exists $args->{'version'} ) {
                $_->{'php_fpm'} = $args->{'php_fpm'};
            }
            else {
                # currently, we do not support php_fpm when the php version is not in the domain.
                $_->{'php_fpm'} = ( $_->{'phpversion_source'}{'domain'} eq $self_config_location ) ? $args->{'php_fpm'} : 0;
            }
        }
    }

    # vhost_version is now up to date with all we want to change in the
    # various vhosts

    my $ref = { 'vhosts' => [], 'errors' => [] };

    foreach my $supplied_vhost (@$vhosts) {
        if ( !$php_config_ref->{$supplied_vhost} ) {
            push @{ $ref->{'errors'} }, Cpanel::Exception::create( 'InvalidParameter', 'No users correspond to the domain “[_1]”.', [$supplied_vhost] );
        }
    }

    my $setup_vhosts_results = Cpanel::PHP::Vhosts::setup_vhosts_for_php($vhost_versions);

    push @{ $ref->{'errors'} }, @{ $setup_vhosts_results->{'failure'} };

    if ( @{ $ref->{'errors'} } ) {
        $metadata->{'result'} = 0;
        $metadata->{'reason'} = Cpanel::Exception::create( 'Collection', [ 'exceptions' => $ref->{'errors'} ] )->get_string();
    }
    else {
        Whostmgr::API::1::Utils::set_metadata_ok($metadata);
    }

    Cpanel::PHP::Vhosts::rebuild_configs_and_restart($php_config_ref);

    _do_hook( $args, 'Lang::PHP::set_vhost_versions', 'post' );

    return scalar @{ $ref->{'errors'} } ? $ref : {};
}

sub php_get_impacted_domains {
    my ( $args, $metadata ) = @_;

    my $prm     = Cpanel::Form::Param->new( { 'parseform_hr' => $args } );
    my @domains = $prm->param('domain');
    my $system  = $prm->param('system_default');

    if ( !$system && !@domains ) {
        Whostmgr::API::1::Utils::set_metadata_not_ok( $metadata, Cpanel::Exception::create( "AtLeastOneOf", [ params => [ "domain", "system_default" ] ] ) );
        return;
    }

    my $domains = eval { Cpanel::PHP::Config::get_impacted_domains( domains => \@domains, system_default => $system ) };
    if ($@) {
        Whostmgr::API::1::Utils::set_metadata_not_ok( $metadata, $@ );
        return;
    }

    Whostmgr::API::1::Utils::set_metadata_ok($metadata);
    return { 'domains' => $domains };
}

sub php_ini_get_directives {
    my ( $args, $metadata ) = @_;

    my $package = Whostmgr::API::1::Utils::get_length_required_argument( $args, 'version' );

    my $php        = Cpanel::ProgLang->new( type => 'php' );
    my $ini        = $php->get_ini( 'package' => $package );
    my $directives = $ini->get_basic_directives();

    Whostmgr::API::1::Utils::set_metadata_ok($metadata);

    return { 'directives' => $directives };
}

sub php_ini_set_directives {
    my ( $args, $metadata ) = @_;

    _do_hook( $args, 'Lang::PHP::ini_set_directives', 'pre' );

    my $package = Whostmgr::API::1::Utils::get_length_required_argument( $args, 'version' );

    # Directive values are in <key>:<value> format
    my %directives = map { split /:/, $_, 2 } @{ _get_multivalued_args( $args, 'directive' ) };

    my $php = Cpanel::ProgLang->new( type => 'php' );
    my $ini = $php->get_ini( 'package' => $package );
    $ini->set_directives( 'directives' => \%directives );

    Whostmgr::API::1::Utils::set_metadata_ok($metadata);

    _do_hook( $args, 'Lang::PHP::ini_set_directives', 'post' );

    # Restart PHP-FPM (restart() handles checks to see if it is needed)
    require Cpanel::ServerTasks;
    Cpanel::ServerTasks::schedule_task( ['CpServicesTasks'], 5, "restartsrv apache_php_fpm" );

    return {};
}

sub php_ini_get_content {
    my ( $args, $metadata ) = @_;

    my $package = Whostmgr::API::1::Utils::get_length_required_argument( $args, 'version' );

    my $php     = Cpanel::ProgLang->new( type => 'php' );
    my $ini     = $php->get_ini( 'package' => $package );
    my $content = $ini->get_content();
    $content = HTML::Entities::encode($$content);

    Whostmgr::API::1::Utils::set_metadata_ok($metadata);

    return { 'content' => $content };
}

sub php_ini_set_content {
    my ( $args, $metadata ) = @_;

    _do_hook( $args, 'Lang::PHP::ini_set_content', 'pre' );

    my $package = Whostmgr::API::1::Utils::get_length_required_argument( $args, 'version' );
    my $content = Whostmgr::API::1::Utils::get_length_required_argument( $args, 'content' );
    $content = HTML::Entities::decode($content);

    my $php = Cpanel::ProgLang->new( type => 'php' );
    my $ini = $php->get_ini( 'package' => $package );
    $ini->set_content( 'content' => \$content );

    Whostmgr::API::1::Utils::set_metadata_ok($metadata);

    _do_hook( $args, 'Lang::PHP::ini_set_content', 'post' );

    return {};
}

sub php_get_handlers {
    my ( $args, $metadata ) = @_;

    my $apache = Cpanel::WebServer->new()->get_server( type => 'apache' );
    my $php    = Cpanel::ProgLang->new( type => 'php' );
    my $installed;
    my @data;
    my @errs;

    if ( ( my $package = Whostmgr::API::1::Utils::get_length_argument( $args, 'version' ) ) ) {
        $installed = [$package];
    }
    else {
        $installed = $php->get_installed_packages();
    }

    # gather list of handlers available to each package
    # It is possible that only a subset of packages would throw exceptions.
    # Rather than die upon first exception, return any available payload and provide an exception collection in metadata.
    for my $package (@$installed) {
        try {
            my $conf     = Cpanel::ProgLang::Conf->new( type => $php->type() );
            my $current  = $conf->get_package_info( package => $package );
            my $avail    = $apache->get_available_handlers( lang => $php, package => $package );
            my @handlers = sort keys %$avail;
            push @data, { version => $package, current_handler => $current, available_handlers => \@handlers };
        }
        catch {
            push @errs, $_;
        }
    }

    if (@errs) {
        my $err_collection = Cpanel::Exception::create( 'Collection', [ 'exceptions' => \@errs ] );
        if (@data) {
            Whostmgr::API::1::Utils::set_metadata_not_ok( $metadata, $err_collection->get_string() );
        }
        else {
            die $err_collection;
        }
    }
    else {
        Whostmgr::API::1::Utils::set_metadata_ok($metadata);
    }

    return { version_handlers => \@data };
}

sub php_set_handler {
    my ( $args, $metadata ) = @_;

    _do_hook( $args, 'Lang::PHP::set_handler', 'pre' );

    my $package = Whostmgr::API::1::Utils::get_length_required_argument( $args, 'version' );
    my $handler = Whostmgr::API::1::Utils::get_length_required_argument( $args, 'handler' );

    my $apache = Cpanel::WebServer->new()->get_server( type => 'apache' );
    my $php    = Cpanel::ProgLang->new( type => 'php' );

    $apache->set_package_handler( type => $handler, lang => $php, package => $package, restart => 1 );
    if ( !defined $args->{users} || $args->{users} ) {
        $apache->update_user_package_handlers( type => $handler, lang => $php, package => $package );
    }

    Whostmgr::API::1::Utils::set_metadata_ok($metadata);

    _do_hook( $args, 'Lang::PHP::set_handler', 'post' );

    return {};
}

sub _is_fpm_installed_for_php_version {
    my ($version) = @_;

    Cpanel::LoadModule::load_perl_module('Cpanel::PHPFPM::Installed');    # module calls packman

    return 1 if ( Cpanel::PHPFPM::Installed::is_fpm_installed_for_php_version($version) );
    return;
}

sub php_set_session_save_path {
    my ( $args, $metadata ) = @_;

    Cpanel::ProgLang::Supported::php::Ini::setup_session_save_path();
    Whostmgr::API::1::Utils::set_metadata_ok($metadata);
    return {};
}

sub php_get_default_accounts_to_fpm {
    my ( $args, $metadata ) = @_;

    my $ref = {
        'default_accounts_to_fpm' => Cpanel::PHPFPM::Config::get_default_accounts_to_fpm(),
    };

    Whostmgr::API::1::Utils::set_metadata_ok($metadata);

    return $ref;
}

sub php_set_default_accounts_to_fpm {
    my ( $args, $metadata ) = @_;

    if ( !exists $args->{'default_accounts_to_fpm'} ) {
        die Cpanel::Exception::create( 'MissingParameter', [ 'name' => 'default_accounts_to_fpm' ] );
    }

    if (   $args->{'default_accounts_to_fpm'} != 0
        && $args->{'default_accounts_to_fpm'} != 1 ) {
        die Cpanel::Exception::create( 'InvalidParameter', "Value for “default_accounts_to_fpm” must be a 1 or 0." );
    }

    Cpanel::PHPFPM::Config::set_default_accounts_to_fpm( $args->{'default_accounts_to_fpm'} );

    Whostmgr::API::1::Utils::set_metadata_ok($metadata);

    return {};
}

sub convert_all_domains_to_fpm {
    my ( $args, $metadata ) = @_;

    my $build_id = time();

    my $logfile_path = "/var/cpanel/logs/convert_all_domains_to_fpm.$build_id.log";
    my $convert_log_fh;
    if ( !open( $convert_log_fh, '>>', $logfile_path ) ) {
        die "Could not open error log $logfile_path : $!\n";
    }

    my $cmd  = '/usr/local/cpanel/scripts/php_fpm_config';
    my @opts = ( '--convert_all', '--logfile_path=' . $logfile_path, '--noprompt' );

    Cpanel::LoadModule::load_perl_module('Cpanel::Daemonizer::Tiny');

    # Fork the process to the background, let the API call return that it has started it
    my $mainpid = Cpanel::Daemonizer::Tiny::run_as_daemon(
        sub {
            local $0 = "Converting all domains to PHP-FPM";
            my $_logger = Cpanel::Logger->new();
            open( $convert_log_fh, '>>', $logfile_path ) or $_logger->die("convert_to_fpm: Failed to open $logfile_path: $!");
            print {$convert_log_fh} 'CHILD_PID: ' . $$ . "\n";
            open( STDIN, '<', '/dev/null' ) || $_logger->die("convert_to_fpm: Failed to redirect STDIN to /dev/null : $!");
            open( STDOUT, '>&=' . fileno($convert_log_fh) ) || $_logger->die("convert_to_fpm: Could not redirect STDOUT: $!");    ## no critic qw(ProhibitTwoArgOpen)
            open( STDERR, '>&=' . fileno($convert_log_fh) ) || $_logger->die("convert_to_fpm: Could not redirect STDERR: $!");    ## no critic qw(ProhibitTwoArgOpen)
            exec( $cmd, @opts ) or $_logger->die("Failed to exec $cmd @opts: $!");
        }
    );

    $metadata->{'result'} = 1;
    $metadata->{'reason'} = 'OK';

    return { build => $build_id };
}

sub is_conversion_in_progress {
    my ( $args, $metadata ) = @_;

    my $pid_obj    = Cpanel::Unix::PID::Tiny->new();
    my $pid        = $pid_obj->get_pid_from_pidfile($Cpanel::PHPFPM::Constants::convert_all_pid_file);
    my $inProgress = 0;

    # Make sure we are looking at something higher than init
    if ( $pid > 1 ) {
        $inProgress = Cpanel::PHPFPM::Utils::is_task_still_running($pid);
    }

    $metadata->{'result'} = 1;
    $metadata->{'reason'} = 'OK';

    return { inProgress => $inProgress };
}

sub _do_hook {
    my ( $args, $event, $stage ) = @_;

    Cpanel::Hooks::hook(
        {
            'category' => 'Whostmgr',
            'event'    => $event,
            'stage'    => $stage,
        },
        $args,
    );

    return 1;
}

sub get_fpm_count_and_utilization {
    my ( $args, $metadata ) = @_;

    my $data_hr = Cpanel::PHPFPM::Utils::get_fpm_count_and_utilization();

    Whostmgr::API::1::Utils::set_metadata_ok($metadata);

    return $data_hr;
}

sub php_fpm_config_set {
    my ( $args, $metadata ) = @_;

    require Cpanel::PHPFPM::EvaluateConfig;

    Cpanel::PHPFPM::EvaluateConfig::config_set( $args, $metadata );

    return;
}

sub php_fpm_config_get {
    my ( $args, $metadata ) = @_;

    require Cpanel::PHPFPM::EvaluateConfig;

    my $output_hr = Cpanel::PHPFPM::EvaluateConfig::config_get( $args, $metadata );

    return $output_hr;
}

1;

__END__

=head1 NAME

Whostmgr::API::1::Lang::PHP

=head1 DESCRIPTION

This module is a thin wrapper around Cpanel::ProgLang::PHP for use via API 1.

=head1 SUBROUTINES

=head2 php_get_installed_versions

Returns a list of the versions of PHP recognized as installed on the system

=head2 php_get_system_default_version

Processes the request and returns the results of Cpanel::ProgLang::PHP::php_get_system_default_version()

=head2 php_set_system_default_version

Processes the request and sets the default system PHP version by calling Cpanel::ProgLang::PHP::php_set_system_default_version( $args->{'version'} )

=head2 php_get_vhost_versions

Processes the request and returns the results of Cpanel::ProgLang::PHP::Settings::php_get_vhost_versions()

=head2 php_set_vhost_versions

Processes the request and sets a group of vhost versions by calling Cpanel::ProgLang::PHP::Settings::php_set_vhost_versions( $args )

When there is a failure to update one or more of the vhosts, the data payload will contain the list of vhosts that failed to be updated.

=head2 php_ini_get_directives

Returns directives and values that may be edited and set via L<php_ini_set_directives>.

Takes a 'version' argument, of the version of PHP to use.

=head2 php_ini_set_directives

Processes the request to update the given directives and values.

Takes key-value pairs of directives, and the PHP version to set.

=head2 php_ini_get_content

Returns the entire contents of the ini file for the specified PHP
version, encoded with HTML-encoding.

Expects the query parameter "version", value should be a valid PHP package name (e.g., "ea-php54")

=head2 php_ini_set_content

Processes the request to update the entire ini file for the specified PHP version.

Takes the version as the 'version' parameter, and the content as
HTML-encoded text within the 'content' parameter.

=head2 php_get_impacted_domains

Reports the domains and subdomains that might change if the PHP configuration
for the given params chages.

=head2 php_fpm_config_get

Returns a hashref of the FPM config for the domain requested or the system defaults.

=head2 php_fpm_config_set

Sets or validates an fpm config for a domain or the system defaults.

=head1 INTERNAL SUBROUTINES

=head2 _init_by_ref

Handles initializing $metadata, assumes error (or rather doesn't assume success)

=head2 _set_ok_by_ref

Sets $metadata for with parameters indicating a successful call

=head2 _do_hook

Runs standard hooks registered for subroutines that call it

=head1 LICENSE AND COPYRIGHT

Copyright (c) 2015, cPanel, Inc. All rights reserved.
