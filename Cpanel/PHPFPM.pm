package Cpanel::PHPFPM;

# cpanel - Cpanel/PHPFPM.pm                        Copyright 2022 cPanel, L.L.C.
#                                                           All rights reserved.
# copyright@cpanel.net                                         http://cpanel.net
# This code is subject to the cPanel license. Unauthorized copying is prohibited

use strict;
use warnings;

use Umask::Local                        ();
use Cpanel::FileUtils::Dir              ();
use Cpanel::FileUtils::Copy             ();
use Cpanel::ServerTasks                 ();
use Cpanel::ConfigFiles::Apache::vhost  ();
use Cpanel::Config::userdata::Constants ();
use Cpanel::Mkdir                       ();
use Cpanel::FileUtils::Write            ();
use Cpanel::PHPFPM::Get                 ();
use Cpanel::PHPFPM::Constants           ();
use Cpanel::Config::Httpd::EA4          ();
use Cpanel::PHP::Config                 ();
use Cpanel::Debug                       ();
use Cpanel::FileUtils::Write            ();
use Cpanel::CachedDataStore             ();
use Cpanel::LoadModule                  ();
use Cpanel::Config::userdata::Load      ();
use Cpanel::Locale                      ();

use Try::Tiny;

=pod

=head1 NAME

Cpanel::PHPFPM

=head1 DESCRIPTION

This module generates php_fpm configuration files from yaml files and built-in defaults.

=head2 Files related to this module.

The system configuration values are stored in:

/var/cpanel/ApachePHPFPM/system.yaml

Each domain is configured with it's own pool.   The domain's pool configuration parameters
is stored in:

/var/cpanel/userdata/[username]/[domain].php_fpm.yaml

There is a set of default parameters for each user pool as well:

/var/cpanel/ApachePHPFPM/system_pool_defaults.yaml

The templates for this module are in:

/usr/local/cpanel/shared/templates

system-php-fpm-conf.tmpl        # the system conf template
system-php-fpm-pool-conf.tmpl   # the user conf template

The domain pool conf is done on an exception basis, that is the
actual domain's php_fpm.yaml only needs to contain the values it wants that is different
from the system pool defaults and the base defaults.  If it wants all the defaults, the
file needs to be present with the following entry:

---
_is_present: 1

=head1 FUNCTIONS

=cut

our $PHP_FPM_DIR_PERMS         = 0710;
our $PHP_FPM_CONFIG_PERMS      = 0600;
our $USER_PHP_FPM_CONFIG_PERMS = 0644;

# Constants for rebuild_files
our $UPDATE_HTACCESS = 0;
our $SKIP_HTACCESS   = 1;

our $DO_RESTART   = 1;
our $SKIP_RESTART = 0;

our $REBUILD_VHOSTS = 1;
our $SKIP_VHOSTS    = 0;

#
# The list of values accepted

our %php_fpm_global_directives = (
    'pid' => {
        'name'              => 'pid',
        'default'           => '/opt/cpanel/[% ea_php_version %]/root/usr/var/run/php-fpm/php-fpm.pid',
        'present_ifdefault' => 1,
    },
    'error_log' => {
        'name'              => 'error_log',
        'default'           => '/opt/cpanel/[% ea_php_version %]/root/usr/var/log/php-fpm/error.log',
        'present_ifdefault' => 1,
    },
    'log_level' => {
        'name'              => 'log_level',
        'default'           => 'notice',
        'present_ifdefault' => 1,
    },
    'syslog_facility' => {
        'name'              => 'syslog.facility',
        'default'           => 'daemon',
        'present_ifdefault' => 0,
    },
    'syslog_ident' => {
        'name'              => 'syslog.ident',
        'default'           => 'php-fpm',
        'present_ifdefault' => 0,
    },
    'emergency_restart_threshold' => {
        'name'              => 'emergency_restart_threshold',
        'default'           => '0',
        'present_ifdefault' => 1,
    },
    'emergency_restart_interval' => {
        'name'              => 'emergency_restart_interval',
        'default'           => '0',
        'present_ifdefault' => 1,
    },
    'process_control_timeout' => {
        'name'              => 'process_control_timeout',
        'default'           => '10',
        'present_ifdefault' => 1,
    },
    'process_max' => {
        'name'              => 'process.max',
        'default'           => '0',
        'present_ifdefault' => 0,
    },
    'process_priority' => {
        'name'              => 'process.priority',
        'default'           => '_notset_',
        'present_ifdefault' => 0,
    },
    'daemonize' => {
        'name'              => 'daemonize',
        'default'           => 'no',
        'present_ifdefault' => 1,
    },
    'rlimit_files' => {
        'name'              => 'rlimit_files',
        'default'           => '_notset_',
        'present_ifdefault' => 0,
    },
    'rlimit_core' => {
        'name'              => 'rlimit_core',
        'default'           => '0',
        'present_ifdefault' => 0,
    },
    'events_mechanism' => {
        'name'              => 'events.mechanism',
        'default'           => '_notset_',
        'present_ifdefault' => 0,
    },
    'systemd_interval' => {
        'name'              => 'systemd_interval',
        'default'           => '10',
        'present_ifdefault' => 0,
    },
);

our %php_fpm_pool_directives = (
    'user' => {
        'name'              => 'user',
        'default'           => '[% username %]',
        'present_ifdefault' => 1,
    },
    'group' => {
        'name'              => 'group',
        'default'           => '[% username %]',
        'present_ifdefault' => 1,
    },
    'listen' => {
        'name'              => 'listen',
        'default'           => '[% socket_path %]',
        'present_ifdefault' => 1,
    },
    'listen_owner' => {
        'name'              => 'listen.owner',
        'default'           => '[% username %]',
        'present_ifdefault' => 1,
    },
    'listen_group' => {
        'name'              => 'listen.group',
        'default'           => 'nobody',
        'present_ifdefault' => 1,
    },
    'listen_mode' => {
        'name'              => 'listen.mode',
        'default'           => '0660',
        'present_ifdefault' => 1,
    },
    'php_admin_value_disable_functions' => {
        'name'              => 'php_admin_value[disable_functions]',
        'default'           => 'exec,passthru,shell_exec,system',
        'present_ifdefault' => 1,
    },
    'php_admin_flag_allow_url_fopen' => {
        'name'              => 'php_admin_flag[allow_url_fopen]',
        'default'           => 'on',
        'present_ifdefault' => 1,
    },
    'php_admin_value_short_open_tag' => {
        'name'              => 'php_admin_value[short_open_tag]',
        'default'           => 'on',
        'present_ifdefault' => 1,
    },
    'php_admin_value_doc_root' => {
        'name'              => 'php_admin_value[doc_root]',
        'default'           => '"[% documentroot %]"',
        'present_ifdefault' => 1,
    },
    'php_admin_value_error_log' => {
        'name'              => 'php_admin_value[error_log]',
        'default'           => '[% homedir %]/logs/[% scrubbed_domain %].php.error.log',
        'present_ifdefault' => 1,
    },
    'php_admin_flag_log_errors' => {
        'name'              => 'php_admin_flag[log_errors]',
        'default'           => 'on',
        'present_ifdefault' => 1,
    },
    'php_value_error_reporting' => {
        'name'              => 'php_value[error_reporting]',
        'default'           => 'E_ALL & ~E_NOTICE',
        'present_ifdefault' => 1,
    },
    'pm' => {
        'name'              => 'pm',
        'default'           => 'ondemand',
        'present_ifdefault' => 1,
    },
    'pm_max_children' => {
        'name'              => 'pm.max_children',
        'default'           => 5,
        'present_ifdefault' => 1,
    },
    'pm_start_servers' => {
        'name'              => 'pm.start_servers',
        'default'           => 0,
        'present_ifdefault' => 1,
    },
    'pm_min_spare_servers' => {
        'name'              => 'pm.min_spare_servers',
        'default'           => 1,
        'present_ifdefault' => 1,
    },
    'pm_max_spare_servers' => {
        'name'              => 'pm.max_spare_servers',
        'default'           => 5,
        'present_ifdefault' => 1,
    },
    'pm_process_idle_timeout' => {
        'name'              => 'pm.process_idle_timeout',
        'default'           => 10,
        'present_ifdefault' => 1,
    },
    'chdir' => {
        'name'              => 'chdir',
        'default'           => '[% homedir %]',    # use / if using chroot
        'present_ifdefault' => 1,
    },
    'catch_workers_output' => {
        'name'              => 'catch_workers_output',
        'default'           => 'yes',
        'present_ifdefault' => 1,
    },
    'pm_max_requests' => {
        'name'              => 'pm.max_requests',
        'default'           => 20,
        'present_ifdefault' => 1,
    },
    'pm_status_path' => {
        'name'              => 'pm.status_path',
        'default'           => '/status',
        'present_ifdefault' => 1,
    },
    'ping_path' => {
        'name'              => 'ping.path',
        'default'           => '/ping',
        'present_ifdefault' => 1,
    },

    # these are here if needed
    'listen_backlog' => {
        'name'              => 'listen.backlog',
        'default'           => -1,
        'present_ifdefault' => 0,
    },
    'listen_allowed_clients' => {
        'name'              => 'listen.allowed_clients',
        'default'           => 'any',
        'present_ifdefault' => 0,
    },
    'listen_acl_users' => {
        'name'              => 'listen.acl_users',
        'default'           => '_notset_',
        'present_ifdefault' => 0,
    },
    'listen_acl_groups' => {
        'name'              => 'listen.acl_groups',
        'default'           => '_notset_',
        'present_ifdefault' => 0,
    },
    'request_terminate_timeout' => {
        'name'              => 'request_terminate_timeout',
        'default'           => 0,
        'present_ifdefault' => 0,
    },
    'request_slowlog_timeout' => {
        'name'              => 'request_slowlog_timeout',
        'default'           => 0,
        'present_ifdefault' => 0,
    },
    'rlimit_files' => {
        'name'              => 'rlimit_files',
        'default'           => 1024,
        'present_ifdefault' => 0,
    },
    'rlimit_core' => {
        'name'              => 'rlimit_core',
        'default'           => 0,
        'present_ifdefault' => 0,
    },
    'chroot' => {    # note, this is tricky to get working, but is present if needed
        'name'              => 'chroot',
        'default'           => '[% homedir %]/',
        'present_ifdefault' => 0,
    },
    'clean_env' => {
        'name'              => 'clean_env',
        'default'           => 'yes',
        'present_ifdefault' => 0,
    },
    'security_limit_extensions' => {
        'name'              => 'security.limit_extensions',
        'default'           => '.phtml .php .php3 .php4 .php5 .php6 .php7 .php8',    # This static value is replaced by ea-cpanel-tool’s ea4-metainfo.json’s `default_phpfpm_security_limit_extensions`
        'present_ifdefault' => 1,
    },
    'slowlog' => {
        'name'              => 'slowlog',
        'default'           => '[% homedir %]/logs/[% scrubbed_domain %].php-fpm.slow.log',
        'present_ifdefault' => 0,
    },
    'php_value_session_save_handler' => {
        'name'              => 'php_value[session.save_handler]',
        'default'           => 'files',
        'present_ifdefault' => 0,
    },
    'php_value_session_save_path' => {
        'name'              => 'php_value[session.save_path]',
        'default'           => '/opt/cpanel/[% ea_php_version %]/root/usr/var/lib/php/session',
        'present_ifdefault' => 0,
    },
    'php_value_soap_wsdl_cache_dir' => {
        'name'              => 'php_value[soap.wsdl_cache_dir]',
        'default'           => '/opt/cpanel/[% ea_php_version %]/root/usr/var/lib/php/wsdlcache',
        'present_ifdefault' => 0,
    },

    # used to flag if the user's pool file should be present
    # it should not end up in the final config file
    # even if no values are set in the file (i.e. it is all the defaults)
    # this will make sure the file is present.

    '_is_present' => {
        'name'              => '_is_present',
        'default'           => '_notset_',
        'present_ifdefault' => 0,
        'ignore'            => 1,
    }
);

use Cpanel::Transaction::File::JSONReader ();
use Perl::Phase::AtRunTime sub {    # init *once* for *all* consumers at *run time*
    my $trx = eval { Cpanel::Transaction::File::JSONReader->new( path => "/etc/cpanel/ea4/ea4-metainfo.json" ) };
    if ( !$@ ) {
        my $data = $trx->get_data;

        if ( ref $data eq 'HASH' && exists $data->{default_phpfpm_security_limit_extensions} ) {
            $php_fpm_pool_directives{security_limit_extensions}{default} = $data->{default_phpfpm_security_limit_extensions};
        }
    }

    return 1;
};

# TODO: test coverage is weak here
# to improve coverage, need a clever way to test the $system->{$key}{'name'} = $system || $php || $key lines

=head2 _output_system_conf

Parameters are:

$ea_php_version which should be the text ea-php99 which is the directory portion where that php version resides.

Example: /opt/cpanel/ea-php99 use ea-php99

The system php fpm config is stored in:

/opt/cpanel/$ea_php_version/root/etc/php-fpm.conf

=cut

#
# _determine_value implements a complicated initialization scheme when
# merging hashes
#
# The value can come from up to 3 hashe refs, the order of operations is to
# go from ref1 to ref2 to ref3, once the value is determined do not look to
# the later refs.
#
# The ref->{key} can be a hash ref or a value
# if it is a value and we are looking for a value take it
#

sub _determine_value {
    my ( $target_ref, $key, $subkey, $default, @source_refs ) = @_;

    # This function is called roughly 1983819 times when converting
    # a larger number of domains to PHPFPM.
    foreach my $ref ( grep { exists $_->{$key} } @source_refs ) {
        if ( ref $ref->{$key} eq "HASH" ) {
            if ( exists $ref->{$key}{$subkey} ) {

                # ref is a hash ref and the subkey exists grab it
                $target_ref->{$key}{$subkey} = $ref->{$key}{$subkey};
                return;
            }
        }
        elsif ( $subkey eq "value" ) {

            # ref1 is a value not a hash take the value if we are looking for a # value
            $target_ref->{$key}{$subkey} = $ref->{$key};
            return;
        }

    }

    $target_ref->{$key}{$subkey} = $default if defined $default;
    return;
}

sub _output_system_conf {
    my ($ea_php_version) = @_;

    return 0 if !Cpanel::Config::Httpd::EA4::is_ea4();

    my $stash = {
        'ea_php_version' => $ea_php_version,
    };

    # load config parms
    my $system_conf_defaults_hr = _get_system_conf_defaults_hr();

    my %known_keys = map { $_ => 1 } ( keys %$system_conf_defaults_hr, keys %php_fpm_global_directives );
    my $system     = $stash->{'system'} = {};

    # deal with present ifdefault and remove any w/o a value
    foreach my $key ( keys %known_keys ) {
        _determine_value( $system, $key, 'name',  $key,  $system_conf_defaults_hr, \%php_fpm_global_directives );
        _determine_value( $system, $key, 'value', undef, $system_conf_defaults_hr, \%php_fpm_global_directives );

        if ( !length $system->{$key}{'value'} ) {
            _determine_value( $system, $key, 'present_ifdefault', undef, $system_conf_defaults_hr, \%php_fpm_global_directives );
            if ( $system->{$key}{'present_ifdefault'} ) {
                $system->{$key}{'value'} = $system_conf_defaults_hr->{$key}{'default'} // $php_fpm_global_directives{$key}{'default'};
            }
            else {
                delete $system->{$key};
                next;
            }
        }

        if ( $system->{$key}{'value'} =~ tr{%}{} ) {
            $system->{$key}{'value'} =~ s/\[\%[ \t]*(\S+)[ \t]*\%\]/$stash->{$1}/g;
        }
    }

    my $template = _get_template_singleton();
    my $output   = '';
    my $ret      = $template->process( $Cpanel::PHPFPM::Constants::system_conf_tmpl, $stash, \$output );

    local $PHP_FPM_DIR_PERMS = 0755;    # relax permissions on etc dir to match system /etc

    _write_php_fpm_conf( $Cpanel::PHPFPM::Constants::opt_cpanel . "/$ea_php_version/root/etc", 'php-fpm.conf', $output );
    return 1;
}

sub _write_php_fpm_conf {
    my ( $output_dir, $output_file, $output ) = @_;
    my $output_path = "$output_dir/$output_file";
    Cpanel::Mkdir::ensure_directory_existence_and_mode( $output_dir, $PHP_FPM_DIR_PERMS );

    # For 0700 perm on config files
    {
        my $umask_local = Umask::Local->new(0077);
        if ( -e $output_path ) {
            Cpanel::FileUtils::Copy::safecopy( $output_path, $output_path . ".save" );
        }
    }
    Cpanel::FileUtils::Write::overwrite( $output_path, $output, $PHP_FPM_CONFIG_PERMS );
    return 1;
}

our $system_conf_defaults_cache;

sub _get_system_conf_defaults_hr {
    return ( $system_conf_defaults_cache ||= _parse_fpm_yaml( $Cpanel::PHPFPM::Constants::system_yaml_dir . "/" . $Cpanel::PHPFPM::Constants::system_yaml ) );
}

sub get_php_fpm_pool_parms {
    my ( $user, $domain ) = @_;

    return {} if !Cpanel::Config::Httpd::EA4::is_ea4() || !defined $user || !defined $domain;
    return get_php_fpm_pool_parms_from_php_config( Cpanel::PHP::Config::get_php_config_for_domains( [$domain] )->{$domain} );
}

sub get_php_fpm_pool_parms_from_php_config {
    my ($domain_hr) = @_;

    return {} if !Cpanel::Config::Httpd::EA4::is_ea4();
    my $domain_details = _process_pool_parms($domain_hr);

    my $pool_parms = {};

    if ( defined $domain_details && exists $domain_details->{'pool'} ) {
        my $pool = $domain_details->{'pool'};

        $pool_parms->{'pm_max_children'}         = int( $pool->{'pm_max_children'}->{'value'} )         if exists $pool->{'pm_max_children'};
        $pool_parms->{'pm_process_idle_timeout'} = int( $pool->{'pm_process_idle_timeout'}->{'value'} ) if exists $pool->{'pm_process_idle_timeout'};
        $pool_parms->{'pm_max_requests'}         = int( $pool->{'pm_max_requests'}->{'value'} )         if exists $pool->{'pm_max_requests'};
    }

    return $pool_parms;
}

our $_suppress_calling_set_php_fpm = 0;

sub set_php_fpm {
    my ( $user, $domain, $want_pool, $parms_ref ) = @_;

    return if $_suppress_calling_set_php_fpm;

    return if !Cpanel::Config::Httpd::EA4::is_ea4();

    my $config_fname = "$Cpanel::Config::userdata::Constants::USERDATA_DIR/$user/${domain}.php-fpm.yaml";

    my $cache_file = $config_fname =~ s<yaml\z><cache>r;

    if ($want_pool) {
        $parms_ref = {} if !defined $parms_ref;
        $parms_ref->{'_is_present'} = 1;

        if ( -e $config_fname ) {

            # fold in existing params
            my $domain_pool_hr = _parse_fpm_yaml($config_fname);

            foreach my $key ( keys %{$parms_ref} ) {
                $domain_pool_hr->{$key} = $parms_ref->{$key};
            }

            $parms_ref = $domain_pool_hr;
        }

        # $USER_PHP_FPM_CONFIG_PERMS is 0644 to ensure
        # the user can read the YAML files (user needs to be able to read them from cPanel UI)
        #
        # We rely on $Cpanel::Config::userdata::Constants::USERDATA_DIR/$user being
        # 0750 and root:$USER_UID to ensure that the user can access these
        # files but no other user can.
        Cpanel::CachedDataStore::store_ref( $config_fname, $parms_ref, { mode => $USER_PHP_FPM_CONFIG_PERMS } );
    }
    else {
        for my $path ( $config_fname, $cache_file ) {
            unlink $path or do {
                warn "unlink($path): $!" if !$!{'ENOENT'};
            };
        }
    }

    return 1;
}

sub _process_pool_parms {
    my ($domain_hr) = @_;

    if (   !length $domain_hr->{'phpversion'}
        || !length $domain_hr->{'scrubbed_domain'}
        || !length $domain_hr->{'domain'}
        || !length $domain_hr->{'homedir'}
        || !length $domain_hr->{'username'} ) {
        return undef;
    }

    my ( $proxy, $socket_path ) = Cpanel::PHPFPM::Get::get_proxy_from_php_config_for_domain($domain_hr);
    my $stash = {
        'ea_php_version'  => $domain_hr->{'phpversion'},
        'username'        => $domain_hr->{'username'},
        'scrubbed_domain' => $domain_hr->{'scrubbed_domain'},
        'homedir'         => $domain_hr->{'homedir'},
        'documentroot'    => $domain_hr->{'documentroot'},
        'socket_path'     => $socket_path
    };

    # system wide pool defaults
    my $system_pool_defaults_hr = _get_system_pool_defaults_hr();

    # domains pool values
    my $domain_pool_hr = _parse_fpm_yaml( $domain_hr->{'config_fname'} );

    my $pool       = $stash->{'pool'} = {};
    my %known_keys = map { $_ => 1 } ( keys %$system_pool_defaults_hr, keys %php_fpm_pool_directives, keys %$domain_pool_hr );

    # deal with present ifdefault and remove any w/o a value
    foreach my $key ( keys %known_keys ) {
        _determine_value( $pool, $key, 'name',   $key,  $domain_pool_hr, $system_pool_defaults_hr, \%php_fpm_pool_directives );
        _determine_value( $pool, $key, 'value',  undef, $domain_pool_hr, $system_pool_defaults_hr, \%php_fpm_pool_directives );
        _determine_value( $pool, $key, 'ignore', undef, $domain_pool_hr, $system_pool_defaults_hr, \%php_fpm_pool_directives );

        if ( $pool->{$key}{'ignore'} ) {
            delete $pool->{$key};
            next;
        }

        if ( !length $pool->{$key}{'value'} ) {
            _determine_value( $pool, $key, 'present_ifdefault', undef, $domain_pool_hr, $system_pool_defaults_hr, \%php_fpm_pool_directives );

            if ( $pool->{$key}{'present_ifdefault'} ) {
                $pool->{$key}{'value'} = $domain_pool_hr->{$key}{'default'} // $system_pool_defaults_hr->{$key}{'default'} // $php_fpm_pool_directives{$key}{'default'};
            }
            else {
                delete $pool->{$key};
                next;
            }
        }

        if ( $pool->{$key}{'value'} =~ tr{%}{} ) {
            $pool->{$key}{'value'} =~ s/\[\%[ \t]*(\S+)[ \t]*\%\]/$stash->{$1}/g;
        }

        # Fix HB-4018 - stringify users like 'true', 'false' or 'null'
        $pool->{$key}{'value'} = '"' . $pool->{$key}{'value'} . '"' if grep { index( $pool->{$key}{'name'}, $_ ) == 0 } qw{user group listen.owner listen.group};
    }

    return $stash;
}

our $system_pool_defaults_cache;

sub _get_system_pool_defaults_hr {
    return ( $system_pool_defaults_cache ||= _parse_fpm_yaml( $Cpanel::PHPFPM::Constants::system_yaml_dir . "/" . $Cpanel::PHPFPM::Constants::system_pool_defaults_yaml ) );
}

sub _parse_fpm_yaml {
    my ($yaml_file) = @_;
    return {} if !-e $yaml_file || -z _;
    require Cpanel::SafeStorable;

    # Protect the cached hash from being overwritten
    if ( my $fpm_yaml_data = Cpanel::CachedDataStore::load_ref($yaml_file) ) {
        my $ref = Cpanel::SafeStorable::dclone($fpm_yaml_data);
        return $ref;
    }
    else {
        my $locale = Cpanel::Locale->get_handle();
        print STDERR $locale->maketext( "Warning: During the PHP-FPM rebuild, the system detected formatting issues with the “[_1]” file and did not apply any custom values.",    $yaml_file );
        print STDERR $locale->maketext( "For more information about the correct formatting of custom values, read our Custom Templates (link: [output,url,_1,_1]) documentation.", 'https://go.cpanel.net/EA4CustomTemplates' );
        print STDERR "\n";
        return {};
    }
}

=head2 _post_process_pool

Looks for parameter conflicts and repairs them.

Parameters are:

$domain_hr which is generated by rebuild_files (do not call directly).

$pool_ref this is the prospective pool to write the conf file from.

Returns $pool_ref, modified if necessary when conflicts are found

=cut

our @_prefixes = qw(php_admin_value_ php_admin_flag_ php_value_ php_flag_);

sub _post_process_pool {
    my ( $domain_hr, $pool_ref ) = @_;

    my $domain = $domain_hr->{'domain'};

    # look for conflicts

    my %base_opt_refs;
    my @conflicted_base_opts;

    foreach my $key ( keys %{ $pool_ref->{'pool'} } ) {
        foreach my $prefix (@_prefixes) {
            if ( index( $key, $prefix ) == 0 ) {
                my $base_opt = substr( $key, length($prefix) );
                if ( exists $base_opt_refs{$base_opt} ) {
                    push( @{ $base_opt_refs{$base_opt}->{'found'} }, $key );
                    push( @conflicted_base_opts,                     $base_opt );
                }
                else {
                    $base_opt_refs{$base_opt} = {
                        'base_opt' => $base_opt,
                        'found'    => [$key],
                    };
                }
            }
        }
    }

    if (@conflicted_base_opts) {

        # A conflict can only exist between the system_pool_defaults and the
        # domain's pool, so we will look only into the domain's pool and
        # filter out the system_pools reference.

        my $yaml_ref = _parse_fpm_yaml( $domain_hr->{'config_fname'} );
        foreach my $base_opt (@conflicted_base_opts) {
            foreach my $key ( @{ $base_opt_refs{$base_opt}->{'found'} } ) {
                my $key_ref = $yaml_ref->{$key};
                if ( !defined $key_ref ) {
                    delete $pool_ref->{'pool'}->{$key};
                    next;
                }

                if ( ref $key_ref eq 'HASH' && exists $key_ref->{'present_ifdefault'} && $key_ref->{'present_ifdefault'} == 0 ) {
                    delete $pool_ref->{'pool'}->{$key};
                    next;
                }
            }
        }
    }

    return $pool_ref;
}

=head2 _prepare_pool_conf

Parameters are:

$domain_hr which is generated by rebuild_files (do not call directly).

This will generate the pool config and return it.

If there is an error it will return undef;

Returns a hash ref with the config.

=cut

sub _prepare_pool_conf {
    my ($domain_hr) = @_;

    return if !Cpanel::Config::Httpd::EA4::is_ea4();

    my $my_ref = _process_pool_parms($domain_hr);
    _post_process_pool( $domain_hr, $my_ref );

    my $ea_php_version = $domain_hr->{'phpversion'};
    my $domain         = $domain_hr->{'domain'};

    # pre-process the values
    my $template = _get_template_singleton();
    my $output   = "";
    my $ret      = $template->process( $Cpanel::PHPFPM::Constants::system_pool_conf_tmpl, $my_ref, \$output );

    return $output;
}

=head2 _output_pool_conf

Parameters are:

$domain_hr which is generated by rebuild_files (do not call directly).

This will result in a php fpm pool conf:

/opt/cpanel/$ea_php_version/root/etc/php-fpm.d/$domain.conf

Also it creates a proxypass conf for the apache vhost

/etc/apache2/conf.d/userdata/std/2_4/$username/$domain/php-fpm.conf

=cut

sub _output_pool_conf {
    my ($domain_hr) = @_;

    my $output = _prepare_pool_conf($domain_hr);
    return 0 if !defined $output;

    my $ea_php_version = $domain_hr->{'phpversion'};
    my $domain         = $domain_hr->{'domain'};

    return _write_php_fpm_conf( $Cpanel::PHPFPM::Constants::opt_cpanel . "/$ea_php_version/root/etc/php-fpm.d/", "$domain.conf", $output );
}

my $template_singleton;

sub _get_template_singleton {
    Cpanel::LoadModule::load_perl_module('Template');
    return ( $template_singleton ||= Template->new( _template_config() ) );
}

sub _update_htaccess {
    my ($php_config_ref) = @_;

    return if !Cpanel::Config::Httpd::EA4::is_ea4();

    # circular references
    require Cpanel::PHP::Vhosts;

    my $php_vhost_versions = Cpanel::PHP::Vhosts::get_php_vhost_versions_from_php_config($php_config_ref);

    $_suppress_calling_set_php_fpm = 1;    # if not yaml file gets rewritten which is unnecessary
    my $setup_vhosts_for_php = Cpanel::PHP::Vhosts::setup_vhosts_for_php($php_vhost_versions);
    $_suppress_calling_set_php_fpm = 0;

    foreach my $err ( @{ $setup_vhosts_for_php->{'failure'} } ) {
        Cpanel::Debug::log_warn($err);
    }

    return 1;
}

sub rebuild_system_config {
    my $php_version_info = Cpanel::PHP::Config::get_php_version_info();
    my @php_versions     = @{ $php_version_info->{'versions'} };

    # collect user and domain info into a convenient hash
    foreach my $php_version (@php_versions) {
        _output_system_conf($php_version);
    }

    return 1;
}

=head2 rebuild_files( PHP_CONFIG_REF, SKIP_HTACCESS, DO_RESTART, REBUILD_VHOSTS )

rebuild all the configuration files needed for php-fpm for the
passed in virtualhosts/domains

=head3 Arguments

Required:

  PHP_CONFIG_REF   - An arrayref of Cpanel::PHP::Config::Domain objects obtained
                     by calling Cpanel::PHP::Config::get_php_config_for_*

  SKIP_HTACCESS    - One of the following:
                      $Cpanel::PHPFPM::UPDATE_HTACCESS - Update the htaccess
                        files for the virtual host
                      $Cpanel::PHPFPM::SKIP_HTACCESS   - Skip updating the
                        htaccess files for the virtual host.

  DO_RESTART       - One of the following:
                      $Cpanel::PHPFPM::DO_RESTART      - Restart the fpm
                        daemons.
                      $Cpanel::PHPFPM::SKIP_RESTART    - Skip restarting the
                        fpm daemons
                      ** It is the callers responsibility to call
                         Cpanel::HttpUtils::ApRestart::BgSafe::restart()
                         if it is required **

  REBUILD_VHOSTS   - One of the following:
                      $Cpanel::PHPFPM::REBUILD_VHOSTS  - Rebuild the httpd
                         virtual hosts assocated with the domain
                      $Cpanel::PHPFPM::SKIP_VHOSTS     - Do not rebuild the
                         virtual hosts assocated with the domain.

=head3 Return Value

  0 - PHP-FPM is not available (likely EasyApache 4 is not installed)
  1 - Success

=cut

# $php_config_ref is a return value from
# Cpanel::PHP::Config::get_php_config_for_*
sub rebuild_files {
    my ( $php_config_ref, $skip_htaccess, $do_restart, $rebuild_vhosts ) = @_;

    return 0 if !Cpanel::Config::Httpd::EA4::is_ea4();

    $skip_htaccess  ||= 0;
    $do_restart     ||= 0;
    $rebuild_vhosts ||= 0;

    # Why do we do this every time?
    rebuild_system_config();

    _remove_pool_files_for_domains_without_fpm_or_other_php_versions($php_config_ref);

    # output those desiring
    foreach my $domain ( keys %{$php_config_ref} ) {
        Cpanel::Debug::log_info("rebuild_files: working on domain ($domain)");
        my $domain_hr = $php_config_ref->{$domain};
        _output_pool_conf($domain_hr) if -e $domain_hr->{'config_fname'};
    }
    _update_htaccess($php_config_ref) if !$skip_htaccess;

    if ($do_restart) {
        Cpanel::Debug::log_info("php-fpm: rebuild_files: restart fpm services for Apache");
        Cpanel::ServerTasks::schedule_task( ['CpServicesTasks'], 1, "restartsrv apache_php_fpm" );
        Cpanel::Debug::log_info("php-fpm: fpm services restarted");
    }
    if ($rebuild_vhosts) {
        Cpanel::Debug::log_info("Rebuilding vhosts in apache conf");
        my ( $update_ok, $update_msg ) = Cpanel::ConfigFiles::Apache::vhost::update_domains_vhosts( keys %$php_config_ref );

        # Apache restarts are always handled by the caller
    }

    return 1;

}

# TODO: test coverage is weak here
sub _remove_pool_files_for_domains_without_fpm_or_other_php_versions {
    my ($php_config_ref) = @_;
    my $php_version_info = Cpanel::PHP::Config::get_php_version_info();
    my @php_versions     = @{ $php_version_info->{'versions'} };

    foreach my $php_version (@php_versions) {
        my $pool_path = $Cpanel::PHPFPM::Constants::opt_cpanel . "/$php_version/root/etc/php-fpm.d";
        my $nodes_ar  = eval { Cpanel::FileUtils::Dir::get_directory_nodes($pool_path) };
        next if !$nodes_ar;
        my %config_exists = map { $_ => 1 } @{$nodes_ar};
        foreach my $domain ( grep { $config_exists{"$_.conf"} } keys %$php_config_ref ) {

            # if this domain on not on version of php
            # now does this domain want fpm?
            #
            my $domain_ref = $php_config_ref->{$domain};
            if ( !exists $domain_ref->{'phpversion'} || $php_version ne $domain_ref->{'phpversion'} || !-e $domain_ref->{'config_fname'} ) {
                unlink("$pool_path/$domain.conf");
            }
        }
    }

    return 1;
}

# should only be called from Whostmgr::Accounts::Remove::_killacct
sub _killacct {
    my ($user) = @_;

    return if !Cpanel::Config::Httpd::EA4::is_ea4();

    # Remove all essence of FPM for this account.  Ignore accounts without
    # userdata.

    my $php_config_ref = eval { Cpanel::PHP::Config::get_php_config_for_users( [$user] ) };
    return unless $php_config_ref;

    # for each user/domain combination remove fpm

    foreach my $domain ( keys %$php_config_ref ) {
        set_php_fpm( $php_config_ref->{$domain}->{'username'}, $domain, 0, {} );
    }

    rebuild_files( $php_config_ref, $SKIP_HTACCESS, $DO_RESTART, $SKIP_VHOSTS );

    require Cpanel::PHPFPM::Tasks;
    Cpanel::PHPFPM::Tasks::bg_ensure_fpm_on_boot();

    return 1;
}

# should only be called from Cpanel::Sub::_delsubdomain and
# Cpanel::ParkAdmin::unpark
sub _removedomain {
    my ($domain) = @_;

    return if !Cpanel::Config::Httpd::EA4::is_ea4();

    # remove all essence of fpm for this account

    my $php_config_ref = Cpanel::PHP::Config::get_php_config_for_domains( [$domain] );

    my $user = $php_config_ref->{$domain}->{'username'};

    set_php_fpm( $user, $domain, 0, {} );

    require Cpanel::PHP::Vhosts;

    # Does not restart apache, its up to the callers to do this
    # Cpanel::Sub::_delsubdomain and Cpanel::ParkAdmin::unpark currently
    # do this already
    Cpanel::PHP::Vhosts::rebuild_configs_and_restart_fpm($php_config_ref);

    return 1;
}

# this will be called by Whostmgr/Accounts/Modify.pm
# when they are changing the primary domain name

use constant {
    DOMAIN_TYPE_UNKNOWN => 0,
    DOMAIN_TYPE_MAIN    => 1,
    DOMAIN_TYPE_ADDON   => 2,
    DOMAIN_TYPE_SUB     => 3,
};

sub remove_primary_domain_fpm_conf {
    my ($domain) = @_;

    return if !Cpanel::Config::Httpd::EA4::is_ea4();

    my $php_config_ref = Cpanel::PHP::Config::get_php_config_for_domains( [$domain] );

    my $domain_hr = $php_config_ref->{$domain};
    my $user      = $domain_hr->{'username'};

    require Cpanel::Config::userdata::Load;

    my $main_userdata = Cpanel::Config::userdata::Load::load_userdata_main($user);

    my %sub_domains;
    my %addon_domains;
    foreach my $subdomain ( @{ $main_userdata->{'sub_domains'} } ) {
        $sub_domains{$subdomain} = 1;
    }

    foreach my $addondomain ( keys %{ $main_userdata->{'addon_domains'} } ) {
        $addon_domains{$addondomain} = 1;
        delete $sub_domains{ $main_userdata->{'addon_domains'}->{$addondomain} };
    }

    my @domains = ( $domain, keys %sub_domains, keys %addon_domains );

    $php_config_ref = Cpanel::PHP::Config::get_php_config_for_domains( \@domains );

    my $restore_config_hr = {};

    foreach my $domain_tld ( keys %{$php_config_ref} ) {
        my $config = $php_config_ref->{$domain_tld};

        my $ea_php_version   = $config->{'phpversion'};
        my $tld_config_fname = $config->{'config_fname'};
        my $tld_output_path  = $Cpanel::PHPFPM::Constants::opt_cpanel . "/$ea_php_version/root/etc/php-fpm.d/$domain_tld.conf";

        my $domain_type = DOMAIN_TYPE_UNKNOWN;
        $domain_type = DOMAIN_TYPE_MAIN  if ( $domain_tld eq $domain );                # main domain
        $domain_type = DOMAIN_TYPE_ADDON if ( exists $addon_domains{$domain_tld} );    # addon domain
        $domain_type = DOMAIN_TYPE_SUB   if ( exists $sub_domains{$domain_tld} );      # sub domain

        my $base_domain = $domain_tld;
        if ( $domain_type == DOMAIN_TYPE_SUB ) {
            my $idx = rindex $domain_tld, $domain;
            $base_domain = substr( $domain_tld, 0, $idx - 1 );
        }

        my $fpm_config;
        my $fpm = ( -f $tld_config_fname ) ? 1 : 0;
        if ($fpm) {
            $fpm_config = Cpanel::PHPFPM::get_php_fpm_pool_parms( $user, $domain_tld );
        }

        $restore_config_hr->{$base_domain} = {
            'type'       => $domain_type,
            'domain_tld' => $domain_tld,
            'fpm'        => ( -f $tld_config_fname ) ? 1 : 0,
            'fpm_config' => $fpm_config,
        };

        unlink $tld_config_fname if -f $tld_config_fname;
        unlink $tld_output_path  if -f $tld_output_path;
    }

    return $restore_config_hr;
}

sub restore_fpm_configs {
    my ( $domain, $restore_config_hr ) = @_;

    my $php_config_ref = Cpanel::PHP::Config::get_php_config_for_domains( [$domain] );
    my $domain_hr      = $php_config_ref->{$domain};
    my $user           = $domain_hr->{'username'};

    my $rebuild_flag = 0;

    require Cpanel::PHPFPM::Tasks;

    foreach my $old_domain ( keys %{$restore_config_hr} ) {
        my $old_domain_hr = $restore_config_hr->{$old_domain};
        if ( $old_domain_hr->{'fpm'} == 1 ) {
            my $new_domain = $domain;
            $new_domain = $old_domain . '.' . $domain    if ( $old_domain_hr->{'type'} == DOMAIN_TYPE_SUB );      # sub domain
            $new_domain = $old_domain_hr->{'domain_tld'} if ( $old_domain_hr->{'type'} == DOMAIN_TYPE_ADDON );    # addon domain
            set_php_fpm( $user, $new_domain, 1, $old_domain_hr->{'fpm_config'} );
            Cpanel::PHPFPM::Tasks::queue_rebuild_fpm_domain_in_dir($new_domain);
            $rebuild_flag = 1;
        }
    }

    if ($rebuild_flag) {
        try {
            require Cpanel::ServerTasks;
            Cpanel::ServerTasks::schedule_task( ['PHPFPMTasks'], 30, 'rebuild_fpm' );
        };
    }

    return;
}

sub _template_config {
    return { 'INCLUDE_PATH' => $Cpanel::PHPFPM::Constants::template_dir, 'COMPILE_DIR' => $Cpanel::ConfigFiles::TEMPLATE_COMPILE_DIR };
}

1;
