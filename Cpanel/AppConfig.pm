package Cpanel::AppConfig;

# cpanel - Cpanel/AppConfig.pm                     Copyright 2022 cPanel, L.L.C.
#                                                           All rights reserved.
# copyright@cpanel.net                                         http://cpanel.net
# This code is subject to the cPanel license. Unauthorized copying is prohibited

use strict;
use Cpanel::JSON               ();    # PPI USE OK -- Enables caching in LoadConfig
use Cpanel::Config::LoadConfig ();
use Cpanel::PwCache            ();

my $logger;

our $VERSION     = '2.1';
our $APPCONF_DIR = '/var/cpanel/apps';

my $loaded_apps    = 0;
my @known_services = ( 'whostmgr', 'cpanel', 'webmail' );

my $applications;

sub _init_applications {
    $applications ||= {
        'whostmgr' => [
            {
                'url'  => '/cgi/api_shell/index.cgi',
                'user' => 'root',
                'name' => 'internal_apishell',
                'acls' => ['all'],
            },

            {
                'url'  => '/cgi/securityadvisor/index.cgi',
                'user' => 'root',
                'name' => 'internal_securityadvisor',
                'acls' => ['all'],
            },

            {
                'url'       => '/3rdparty/phpMyAdmin',
                'user'      => 'cpanelphpmyadmin',
                'phpConfig' => 'phpmyadmin',
                'name'      => 'internal_phpmyadmin',
                'acls'      => ['all'],
            },

            # cpaddons root only
            {
                'url'  => [ '/cgi/cpaddons.pl', '/cgi/cpaddons_report.pl' ],
                'user' => 'root',
                'name' => 'internal_cpaddons_root',
                'acls' => ['all'],
            },

            # dns clustering root only
            {
                'url'  => [ '/cgi/adjustclusterdns.cgi', '/cgi/adjustclusteroptions.cgi' ],
                'user' => 'root',
                'name' => 'internal_dnsclustering_root',
                'acls' => ['all'],
            },

            # CloudLinux system
            {
                'url'  => '/cgi/CloudLinux.cgi',
                'user' => 'root',
                'name' => 'internal_cloudlinux',
                'acls' => ['all'],
            },

            # Disk usage system
            {
                'url'  => '/cgi/diskusage.cgi',
                'user' => 'root',
                'name' => 'internal_diskusage',
                'acls' => ['all'],
            },

            # Exim config system
            {
                'url'  => [ '/cgi/mailflow.cgi', '/cgi/addrbl.cgi' ],
                'user' => 'root',
                'name' => 'internal_eximconfig',
                'acls' => ['all'],
            },

            # stats system
            {
                'url'  => '/cgi/statmanager.cgi',
                'user' => 'root',
                'name' => 'internal_stats',
                'acls' => ['all'],
            },

            # hostaccess (hosts.allow) system
            {
                'url'  => '/cgi/hostaccess.cgi',
                'user' => 'root',
                'name' => 'internal_hostaccess',
                'acls' => ['all'],
            },

            # log rotation system
            {
                'url'  => [ '/cgi/cpanel_log_rotation.pl', '/cgi/apache_log_rotation.pl' ],
                'user' => 'root',
                'name' => 'internal_logrotation',
                'acls' => ['all'],
            },

            # cphulkd system
            {
                'url'  => [ '/cgi/tweakcphulk.cgi', '/cgi/cphulkdblk.cgi', '/cgi/cphulkdwhitelist.cgi', '/cgi/bl.cgi', '/cgi/wl.cgi' ],
                'user' => 'root',
                'name' => 'internal_cphulkd',
                'acls' => ['all'],
            },

            # Transfer system
            {
                'url'  => [ '/cgi/live_tail_log', '/cgi/live_tail_transfer_log.cgi' ],
                'user' => 'root',
                'name' => 'queued_session_system',
                'acls' => ['rearrange-accts'],
            },

            # Transfer system (accounts)
            {
                'url'  => ['/cgi/sshcheck.cgi'],
                'user' => 'root',
                'name' => 'internal_transfers',
                'acls' => ['all'],
            },

            # Live Log Tail common script
            {
                'url'  => ['/cgi/process_tail.cgi'],
                'user' => 'root',
                'name' => 'process_tail',
                'acls' => ['all'],
            },

            # legacy compat
            {
                'url'  => '/cgi/parseform.pl',
                'user' => 'root',
                'name' => 'internal_compat',
                'acls' => ['all'],
            },

            # ssh key manager
            {
                'url'  => '/backend/puttykey.cgi',
                'user' => 'root',
                'name' => 'internal_ssh_key_manage',
                'acls' => ['all'],
            },

            # NOTE: ---- RESELLER ACCESS BEYOND THIS LINE ------
            # Dns clustering
            {
                'url'  => [ '/cgi/activate_remote_nameservers.cgi', '/cgi/adjustuniquedns.cgi', '/cgi/configure_remote_nameserver.cgi', '/cgi/enableclusterserver.cgi', '/cgi/clusterstatus.cgi', '/cgi/remclusterserver.cgi', '/cgi/changeclusterdns.cgi', '/cgi/trustclustermaster.cgi' ],
                'user' => 'root',
                'name' => 'internal_dns_clustering',
                'acls' => ['clustering'],
            },

            # locale system
            {
                'url'  => [ '/cgi/ajax_maketext_syntax_util.pl', '/cgi/ajax_locale_delete_local_key.pl', '/cgi/build_locale_databases.pl', '/cgi/locale_duplicate.cgi' ],    ## no extract maketext
                'user' => 'root',
                'name' => 'internal_locale',
                'acls' => ['locale-edit'],
            },

            # mail trouble shoot system
            {
                'url'  => '/cgi/traceaddy.cgi',
                'user' => 'root',
                'name' => 'internal_mail_troubleshooter',
                'acls' => ['mailcheck'],
            },

            # changelog system
            {
                'url'  => '/cgi/changelog.cgi',
                'user' => 'root',
                'name' => 'internal_changelog',
                'acls' => ['any'],
            },

            # branding system
            {
                'url'  => '/cgi/brandingimage.cgi',
                'user' => 'root',
                'name' => 'internal_branding',
                'acls' => ['any'],
            },

            # password strength reporting
            {
                'url'  => [ '/backend/passwordstrength.cgi', '/cgi/passwordstrength.cgi' ],
                'user' => 'root',
                'name' => 'internal_passwordstrength',
                'acls' => ['any'],
            },

            # news feed
            {
                'url'  => '/cgi/news.cgi',
                'user' => 'root',
                'name' => 'internal_newsfeed',
                'acls' => ['any'],
            },

        ],
        'cpanel' => [
            {
                'url'      => '/3rdparty/mailman/',
                'user'     => 'mailman',
                'group'    => 'mailman',
                'name'     => 'mailman',
                'features' => ['lists'],
            },
            {
                'url'       => '/3rdparty/roundcube/',
                'user'      => 'cpanelroundcube',
                'phpConfig' => 'roundcube',
                'name'      => 'roundcube',
                'features'  => ['webmail'],
            },
            {
                'url'       => '/3rdparty/phpPgAdmin',
                'user'      => 'cpanelphppgadmin',
                'phpConfig' => 'phppgadmin',
                'name'      => 'phppgadmin',
                'features'  => ['phppgadmin'],
            },

            # elfinder request processing
            {
                'url'      => [ '/backend/elfinder_connector.cgi', '/cgi/elfinder_connector.cgi' ],
                'name'     => 'internal_elfinder_connector',
                'features' => ['filemanager'],
            },
            {
                'url'      => '/3rdparty/phpMyAdmin',
                'features' => ['phpmyadmin'],
                'name'     => 'phpmyadmin'
            },
            {
                'url'      => '/3rdparty/gitweb/',
                'features' => ['version_control'],
                'name'     => 'gitweb'
            },
            {
                'url'      => '/awstats.pl',
                'features' => ['awstats'],
                'name'     => 'awstats',
                'demo'     => 0,
            },
        ],
        'webmail' => [
            {
                'url'       => '/3rdparty/roundcube/',
                'user'      => 'cpanelroundcube',
                'phpConfig' => 'roundcube',
                'name'      => 'roundcube',
                'features'  => ['webmail'],
            },
            {
                'url'      => '/3rdparty/mailman/',
                'user'     => 'mailman',
                'group'    => 'mailman',
                'name'     => 'mailman',
                'features' => ['lists'],
            },
        ],
    };

    return;
}

sub remove_loaded_apps_from_list {
    $loaded_apps = 0;

    _init_applications();

    foreach my $service (@known_services) {

        #ones we load for origin in the key
        @{ $applications->{$service} } = grep { !length $_->{'origin'} } @{ $applications->{$service} };
    }

    return 1;
}

sub get_application_list {
    return $applications if $loaded_apps;

    _init_applications();

    if ( -d $APPCONF_DIR && opendir( my $apps_dh, $APPCONF_DIR ) ) {
        foreach my $file ( readdir($apps_dh) ) {
            if ( $file =~ m/^[a-zA-Z0-9_-]+\.conf$/ ) {
                process_appconfig_file( "$APPCONF_DIR/$file", $applications );
            }
        }
        closedir($apps_dh);
    }

    $loaded_apps = 1;

    return $applications;
}

sub process_appconfig_file {    ## no critic qw(Subroutines::ProhibitExcessComplexity) - requires a larger refactor
    my ( $fullpath, $app_ref, $original_path ) = @_;

    # Original path is used for reporting only
    # since fullpath is likely a temp file that
    # was created with the data from $original_path
    $original_path ||= $fullpath;

    my $file = ( split( m{/+}, $fullpath ) )[-1];

    my $app_count = 0;
    my $status    = 0;

    my $app = Cpanel::Config::LoadConfig::loadConfig( $fullpath, undef, '=' );

    $app->{'url'} = [ $app->{'url'} ] if ( !ref $app->{'url'} );

    # All url1, url2, url3 to the url list
    foreach my $key ( grep( m/^url/, keys %{$app} ) ) {
        next if ( $key eq 'url' );
        push @{ $app->{'url'} }, $app->{$key};
        delete $app->{$key};
    }

    $app->{'origin'} = $file;
    if ( !$app->{'name'} ) {
        $app->{'name'} = determine_name_from_filename($original_path);
    }

    if ( length $app->{'name'} && $app->{'name'} =~ m/^internal/ ) {
        require Cpanel::Logger;
        $logger ||= Cpanel::Logger->new();
        $logger->invalid("Application described at $original_path may not use name internal..., skipping.");
        return ( 0, "Application described at $original_path may not use name internal..., skipping." );
    }

    if ( defined $app->{'url'} && defined $app->{'service'} ) {

        my @services             = split( /\|/, $app->{'service'} );
        my $is_webmail_or_cpanel = ( grep { $_ eq 'webmail' || $_ eq 'cpanel' } @services ) ? 1 : 0;
        my $is_whostmgr          = ( grep { $_ eq 'whostmgr' } @services )                  ? 1 : 0;

        $app->{'user'} ||= 'root' if $is_whostmgr;    # whostmgr defaults to root for back-compat
                                                      # this is required because 'user' is documented
                                                      # as an optional key
        if ( defined $app->{'user'} ) {
            my $app_user = $app->{'user'};
            if ( $app_user eq '$authuser' ) {
                $app_user = $is_webmail_or_cpanel ? 'cpanel' : 'root';    # highest level that $authuser could be
            }

            my @pwnam = Cpanel::PwCache::getpwnam($app_user);

            foreach my $key ( keys %{$app} ) {
                my $text = $app->{$key};
                if ( ref $app->{$key} ) {
                    $text = join( ',', @{ $app->{$key} } );
                }
            }

            if ($is_webmail_or_cpanel) {

                # All applications that use cpanel or webmail, MUST exist within /3rdparty
                foreach my $url ( @{ $app->{'url'} } ) {
                    if ( $url !~ m{^/3rdparty/} ) {    #perlcc workaround, must be regex
                        require Cpanel::Logger;
                        $logger ||= Cpanel::Logger->new();
                        $logger->invalid("Application described at $original_path does not use a URL within /3rdparty/, skipping.");
                        return ( 0, "Application described at $original_path does not use a URL within /3rdparty/, skipping." );
                    }
                }

                # SetUID Applications within cpanel may not run as root
                if ( $pwnam[2] == 0 ) {
                    require Cpanel::Logger;
                    $logger ||= Cpanel::Logger->new();
                    $logger->invalid( "user " . $app_user . " has a UID of 0, skipping application configuration at $original_path\n" );
                    return ( 0, "user " . $app_user . " has a UID of 0, skipping application configuration at $original_path" );

                    # SetUID Applications within cpanel may not run as root
                }
                elsif ( $pwnam[2] < 99 ) {
                    require Cpanel::Logger;
                    $logger ||= Cpanel::Logger->new();
                    $logger->invalid( "user " . $app_user . " has a UID less then 99, skipping application configuration at $original_path\n" );
                    return ( 0, "user " . $app_user . " has a UID less then 99, skipping application configuration at $original_path" );
                }
            }
            else {
                foreach my $url ( @{ $app->{'url'} } ) {
                    if ( $url =~ m{^/?$} || $url =~ m{^/?cgi/?$} ) {
                        require Cpanel::Logger;
                        $logger ||= Cpanel::Logger->new();
                        $logger->invalid( "url " . $url . " may not match the cgi or entire WHM url space." );
                        return ( 0, "url " . $url . " may not match the cgi or entire WHM url space." );
                    }
                }
            }

            # Validate that the user exists on the system, otherwise, error out.

            if ( $pwnam[0] ne $app_user ) {
                require Cpanel::Logger;
                $logger ||= Cpanel::Logger->new();
                $logger->invalid( "user " . $app_user . " does not exist, skipping application configuration at $original_path\n" );
                return ( 0, "user " . $app_user . " does not exist, skipping application configuration at $original_path" );
            }

        }

        if ( $app->{'acls'} ) {
            $app->{'acls'} = [ split( m/\s*\,\s*/, $app->{'acls'} ) ];
        }
        elsif ( $app->{'features'} ) {
            $app->{'features'} = [ split( m/\s*\,\s*/, $app->{'features'} ) ];
        }

        delete $app->{'service'};
        foreach my $service (@services) {
            if ( !exists $app_ref->{$service} ) {
                require Cpanel::Logger;
                $logger ||= Cpanel::Logger->new();
                $logger->invalid("$original_path specifies $service, which is invalid, the only valid services are: 'webmail', 'cpanel', and 'whostmgr'");
                return ( 0, "$original_path specifies $service, which is invalid, the only valid services are: 'webmail', 'cpanel', and 'whostmgr'" );
            }

            $status = 1;
            $app_count++;
            push @{ $app_ref->{$service} }, $app;
        }
    }
    else {
        require Cpanel::Logger;
        $logger ||= Cpanel::Logger->new();

        $logger->invalid("$original_path is an invalid application configuration file. It must specify 'service' and 'url'\n");
        return ( 0, "$original_path is an invalid application configuration file. It must specify 'service' and 'url'" );
    }

    if ($status) {
        return ( $status, "$app_count loaded from: $fullpath", $app_count );
    }

    return ( $status, "failed to load any apps from: $fullpath.  Please check /usr/local/cpanel/logs/error_log.", 0 );
}

sub determine_name_from_filename {
    my ($fullpath) = @_;

    my $file = ( split( m{/+}, $fullpath ) )[-1];

    $file =~ s/\.appconfig$//;
    $file =~ s/\.config$//;
    $file =~ s/\.conf$//;

    return $file;
}

# For testing only since $applications may not be our
sub _fetchapps {
    return $applications;
}

sub _reset_cache {
    undef $applications;
    _init_applications();
    $loaded_apps = 0;
}

1;
