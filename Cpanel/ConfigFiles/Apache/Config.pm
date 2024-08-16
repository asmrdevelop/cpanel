package Cpanel::ConfigFiles::Apache::Config;

# cpanel - Cpanel/ConfigFiles/Apache/Config.pm     Copyright 2022 cPanel, L.L.C.
#                                                           All rights reserved.
# copyright@cpanel.net                                         http://cpanel.net
# This code is subject to the cPanel license. Unauthorized copying is prohibited

######################################################################################################
#### This module is a modified version of EA3’s distiller’s code, it will be cleaned up via ZC-5317 ##
######################################################################################################

use strict;
use warnings;

=encoding utf-8

=head1 NAME

Cpanel::ConfigFiles::Apache::Config - Generate configuration needed to build httpd.conf

=head1 FUNCTIONS

=cut

use Cpanel::AcctUtils::Owner ();
use Cpanel::CachedCommand    ();
use Cpanel::ConfigFiles::Apache 'apache_paths_facade';    # see POD for import specifics
use Cpanel::ConfigFiles::Apache::modules     ();
use Cpanel::Config::HasCpUserFile            ();
use Cpanel::Config::Httpd::IpPort            ();
use Cpanel::Config::Httpd::Paths             ();
use Cpanel::Config::LoadConfig               ();
use Cpanel::Config::LoadCpConf               ();
use Cpanel::Config::LoadCpUserFile           ();
use Cpanel::Config::LoadWwwAcctConf          ();
use Cpanel::Config::userdata::Constants      ();
use Cpanel::Config::userdata::Load           ();
use Cpanel::Config::WebVhosts                ();
use Cpanel::Debug                            ();
use Cpanel::DIp::MainIP                      ();
use Cpanel::DomainForward                    ();
use Cpanel::EA4::Conf::Tiny                  ();
use Cpanel::Hostname                         ();
use Cpanel::HttpUtils::Conf                  ();
use Cpanel::HttpUtils::SSL::Stapling         ();
use Cpanel::HttpUtils::Vhosts::PrimaryReader ();
use Cpanel::IP::Configured                   ();
use Cpanel::IP::Parse                        ();
use Cpanel::Ips::Reserved                    ();
use Cpanel::IPv6::Has                        ();
use Cpanel::IPv6::UserDataUtil::Key          ();
use Cpanel::NAT                              ();
use Cpanel::PHP::Config                      ();
use Cpanel::PHPFPM::Get                      ();
use Cpanel::PwCache                          ();
use Cpanel::PwCache::Build                   ();
use Cpanel::PwCache::GID                     ();
use Cpanel::Reseller                         ();
use Cpanel::Template::Files                  ();
use Cpanel::Validate::IP                     ();
use Cpanel::WildcardDomain::Tiny             ();

use Try::Tiny;

our $PRODUCT_CONF_DIR = '/var/cpanel';
our $SYSTEM_CONF_DIR  = '/etc';

our $MAX_SERVERALIASES_PER_LINE = 29;    # AKA (8192 / 257 [for leading whitespace]  ) - 2

our $conf = { initialized => 0 };

my $ipmigration_map;
my %vhosts_hash;
my $cpconf;
my $reserved_ips;
my $main_ip;
my $wwwacct;
my $dom_owner_lookup_hr;

our $main_port = '80';                   # will be overwitten with the configured port below
our $ssl_port  = '443';                  # will be overwitten with the configured port below

sub _load_ipmigration_map {
    return {} unless ( -e "$PRODUCT_CONF_DIR/ipmigratelock" && -e "$PRODUCT_CONF_DIR/useripmigratemap" );

    my %ip_map = ();
    my $line;
    my $uipmm_fh;
    require Cpanel::SafeFile;
    my $lock = Cpanel::SafeFile::safeopen( $uipmm_fh, '<', "$PRODUCT_CONF_DIR/useripmigratemap" );
    if ( !$lock ) {
        Cpanel::Debug::log_warn("Could not read from $PRODUCT_CONF_DIR/useripmigratemap");
        return;
    }
    while ( $line = readline($uipmm_fh) ) {
        chomp $line;
        my ( $user, $oldip, $newip ) = split( /=/, $line );
        $ip_map{$newip} = $oldip;
    }
    Cpanel::SafeFile::safeclose( $uipmm_fh, $lock );
    return \%ip_map;
}

###########################################################################
#
# Method:
#   add_missing_ssl_file_paths_to_userdata_hash
#
# Description:
#   This function will add missing SSL certificate, key, or CABundle file paths
#   to a user's SSL userdata hash. This function should only be called on SSL
#   userdata hashes, as non-SSL userdata should not have the filepaths.
#
# Parameters:
#   $domain          - The domain the SSL userdata hash describes.
#   $userdata_ssl_hr
#
# Exceptions:
#   None yet.
#
# Returns:
#   The method returns 1 on success or a two-arg return upon failure described below:
#   (
#      0, # Status meaning failure
#      "Failure message",
#   )
sub add_missing_ssl_file_paths_to_userdata_hash {
    my ( $domain, $userdata_ssl_hr ) = @_;

    #We might have an SSL vhost whose certificate is missing. If we put that
    #missing path into Apache’s configuration, Apache will fail to start.
    #So, we ensure that the path is actually there before we put it into
    #the configuration.
    require Cpanel::Apache::TLS;
    my $path = Cpanel::Apache::TLS->get_tls_path($domain);
    my $whynot;
    if ( !-e $path ) {
        $whynot = "$path: $!";
    }
    elsif ( -z _ ) {
        $whynot = "$path exists but is empty.";
    }

    if ($whynot) {
        return ( 0, "No SSL vhost possible for $domain ($whynot)!" );
    }

    $userdata_ssl_hr->{sslcertificatefile} = $path;
    delete $userdata_ssl_hr->{sslcertificatekeyfile};
    delete $userdata_ssl_hr->{sslcacertificatefile};

    return 1;
}

sub _prepare_ips_array {
    my $domain   = shift;
    my $vhost_hr = shift;
    my $nvh_hr   = shift;    # namevirtualhosts
    unless ( defined $domain && defined $vhost_hr && defined $nvh_hr ) {

        # This should never happen
        die "Need domain and vhost hash to prepare the IP array";
    }
    my $ip_arr = [ { ip => $vhost_hr->{ip}, port => $vhost_hr->{port} } ];

    $nvh_hr->{ $vhost_hr->{ip} . ':' . $vhost_hr->{port} } = 1;

    if ( exists $ipmigration_map->{ $vhost_hr->{ip} } ) {
        push @{$ip_arr}, { ip => $ipmigration_map->{ $vhost_hr->{ip} }, port => $vhost_hr->{port} };
        $nvh_hr->{ $ipmigration_map->{ $vhost_hr->{ip} } . ':' . $vhost_hr->{port} } = 1;
    }

    if ( ref $vhost_hr->{$Cpanel::IPv6::UserDataUtil::Key::ipv6_key} eq 'HASH' ) {
        for my $ipv6_ip ( keys %{ $vhost_hr->{$Cpanel::IPv6::UserDataUtil::Key::ipv6_key} } ) {
            ## IPv6 Phase I: note; the square brackets are convenient for writing
            ## out (e.g. bin/build_apache_conf) but inconvenient for reading in
            ## (distiller); would be best if it were technically correct (no
            ## brackets), but this will require a change in the
            ## ::apache::directives (i.e. the Apache templates)
            push @{$ip_arr}, { ip => "[$ipv6_ip]", port => $vhost_hr->{port} };
            $nvh_hr->{ "[$ipv6_ip]:" . $vhost_hr->{port} } = 1;
        }
    }

    $vhost_hr->{ips} = $ip_arr;
    return;
}

#NOTE: This function empties out the passed-in array.
sub split_arrayref_into_chunks {

    # The maximum line length for an apache configuration line is 8192
    # We have to split the serveraliases so they do not get that large

    my ( $array_ref, $chunk_sizes ) = @_;

    my @chunk_container;
    while ( scalar @{$array_ref} ) {
        push @chunk_container, join( ' ', splice( @{$array_ref}, 0, $chunk_sizes ) );
    }

    return \@chunk_container;
}

#This MUTATES the passed-in array!
sub _augment_ssl_vhosts_hash_with_serveralias {
    my ( $vh_hash, $aliases_ar ) = @_;

    $vh_hash->{serveralias}       = join ' ', @$aliases_ar;
    $vh_hash->{serveralias_array} = split_arrayref_into_chunks( $aliases_ar, $MAX_SERVERALIASES_PER_LINE );

    return;
}

sub _augment_ssl_vhosts_hash_with_serveralias__proxy_subdomains {
    my ( $vh_hash, $user_main_obj, $vhname, $username, $aliases_ar ) = @_;

    my @all_aliases = @$aliases_ar;

    my $proxies_hr = $user_main_obj->ssl_proxy_subdomains_label_hash_for_vhost($vhname);

    for my $label ( keys %$proxies_hr ) {
        push @all_aliases, map { "$label.$_" } @{ $proxies_hr->{$label} };
    }

    #Keyed by subdomain leftmost label; values are lists of the DNS zones
    #to which that label should apply.
    $vh_hash->{proxy_subdomains} = $proxies_hr;

    _augment_ssl_vhosts_hash_with_serveralias( $vh_hash, \@all_aliases );

    return;
}

sub get_hash_for_users_specific_vhosts {    ## no critic(Subroutines::ProhibitExcessComplexity)  -- Refactoring this function is a project, not a bug fix
    my ( $users_ar, $vhosts_hr ) = @_;

    my @users = @$users_ar;

    if ( !@users && scalar keys %vhosts_hash ) {
        return wantarray ? %vhosts_hash : \%vhosts_hash;
    }
    elsif (@users) {

        # TODO return cached %vhosts_hash if all @users are in it
    }

    Cpanel::Reseller::getresellersaclhash();    # prime cache
    $cpconf ||= Cpanel::Config::LoadCpConf::loadcpconf_not_copy();

    my %NOCGI;
    my %PWCACHE;
    my $gid_cache_ref;
    my %valid_group_names;

    if ( scalar @users == 1 ) {
        if ( Cpanel::Config::HasCpUserFile::has_cpuser_file( $users[0] ) ) {
            my $cpuser_ref = Cpanel::Config::LoadCpUserFile::loadcpuserfile( $users[0] );
            if ( exists $cpuser_ref->{HASCGI} && $cpuser_ref->{HASCGI} eq '0' ) {
                $NOCGI{ $users[0] } = 1;
            }
        }
        $PWCACHE{ $users[0] } = [ Cpanel::PwCache::getpwnam_noshadow( $users[0] ) ];
        my $gid = $PWCACHE{ $users[0] }->[3];
        my @gr  = getgrgid($gid);
        $gid_cache_ref = { $gid => \@gr };
        $valid_group_names{ $gr[0] } = 1 if defined $gr[0];

    }
    else {
        $gid_cache_ref     = Cpanel::PwCache::GID::get_gid_cacheref();
        %valid_group_names = map { $_->[0] => undef } values %$gid_cache_ref;

        if ( !Cpanel::PwCache::Build::pwcache_is_initted() ) {
            Cpanel::PwCache::Build::init_passwdless_pwcache();
        }
        my $pwcache_ref = Cpanel::PwCache::Build::fetch_pwcache();
        %PWCACHE = map { $_->[0] => $_ } @$pwcache_ref;
        Cpanel::Config::LoadConfig::loadConfig( "$SYSTEM_CONF_DIR/nocgiusers", \%NOCGI, undef, undef, undef, 1 );
        Cpanel::AcctUtils::Owner::build_trueuserowners_cache();
    }

    # This is a sanity check since we can't be certain the setup for these globals was done in get_config()
    $ipmigration_map ||= _load_ipmigration_map();
    $reserved_ips    ||= Cpanel::Ips::Reserved::load_apache_reserved_ips();
    $main_ip         ||= Cpanel::NAT::get_local_ip( Cpanel::DIp::MainIP::getmainip() );
    $main_port = Cpanel::Config::Httpd::IpPort::get_main_httpd_port();
    $ssl_port  = Cpanel::Config::Httpd::IpPort::get_ssl_httpd_port();

    # If we load all vhosts we can determine what the correct set of namevirualhosts is
    my $all_vhosts_loaded   = 0;
    my $namevirtualhost_ips = {};

    #TODO: can be safely deleted one version after the next LTS (currently we can delete in v72+)
    my $user_store_dir = $Cpanel::Config::userdata::Constants::USERDATA_DIR;
    my $php_config_ref;

    if ( !@users ) {

        $all_vhosts_loaded = 1;

        # Get a list of all cpanel accounts
        if ( opendir my $users_dh, $user_store_dir ) {
            @users = readdir $users_dh;
            closedir $users_dh;
        }
        else {
            Cpanel::Debug::log_warn("Failed to open directory $user_store_dir: $!");
            return;
        }

        $php_config_ref = Cpanel::PHP::Config::get_php_config_for_all_domains();    # UpdateCache.pm already excludes nobody
    }
    else {
        $php_config_ref = Cpanel::PHP::Config::get_php_config_for_users( [ grep { $_ ne 'nobody' } @users ] );
    }

    my $main_server_name;                                                           # filled only if needed

    my $primary_vhosts_obj = Cpanel::HttpUtils::Vhosts::PrimaryReader->new();
    my %primary_vhosts_cache;
    my %primary_vhosts_ssl_cache;

  USERLOOP:
    foreach my $user (@users) {                                                     # Read directory because users may include non-cPanel accounts
        next USERLOOP if ( $user =~ m/^\./ || $user =~ m/\.cache$/ );

        my $homedir = $PWCACHE{$user}->[7];
        my $shell   = $PWCACHE{$user}->[8];

        next USERLOOP if ( $user ne '_custom' && !$homedir );                       # Allow custom container

        my $user_main_obj;
        local $@;
        eval { $user_main_obj = Cpanel::Config::WebVhosts->load($user); };
        if ($@) {
            Cpanel::Debug::log_warn("Failed to load user “$user”’s web vhost data: $@");
        }

        next USERLOOP if !defined $user_main_obj;

        my $main_domain                 = $user_main_obj->main_domain();
        my @subdomains                  = $user_main_obj->subdomains();
        my @parked_domains              = $user_main_obj->parked_domains();
        my %addon_domains               = $user_main_obj->addon_domains();
        my $subdomains_to_addons_map_hr = $user_main_obj->subdomains_to_addons_map();

        my $hascgi = ( $user eq 'nobody' ? 1 : ( exists $NOCGI{$user} ? 0 : 1 ) );
        my $jailed = ( $shell =~ m{(?:no|jail)shell} ) ? 1 : 0;

        if ( !$main_domain ) {
            if ( $user eq 'nobody' ) {
                $main_server_name ||= Cpanel::HttpUtils::Conf::get_main_server_name();
                $main_domain = $main_server_name;
            }
            else {
                Cpanel::Debug::log_info("User '$user' data set has no 'main_domain' key.");
                next USERLOOP;
            }
        }

        # update virtfs if jailapache is now done from TweakSettings

        # Main Domain
        if ( exists $vhosts_hash{$main_domain} && $user ne $vhosts_hash{$main_domain}{user} ) {
            Cpanel::Debug::log_warn("Domain ownership conflict detected for $main_domain, users $user, $vhosts_hash{ $main_domain }{user}");
            next USERLOOP;
        }

        my $want_main_domain = ( !$vhosts_hr || $vhosts_hr->{$main_domain} ) ? 1 : 0;

        if ($want_main_domain) {

            # Fetch stored configuration
            #
            # Warning: We are modifing data without making a copy
            # here.  This relys on the legacy behavior of fetch_ref
            # in Cpanel::CachedDataStore which is the underlying
            # code for Cpanel::Config::userdata::Load::load_*
            #
            $vhosts_hash{$main_domain} = Cpanel::Config::userdata::Load::load_userdata_domain( $user, $main_domain, $Cpanel::Config::userdata::Load::ADDON_DOMAIN_CHECK_SKIP );
            delete $vhosts_hash{$main_domain}{optimize_htaccess};

            # Include numeric UID if they want it
            if ( -e "/etc/cpanel/ea4/option-flags/set-USER_ID" ) {
                $vhosts_hash{$main_domain}{uid} = $PWCACHE{$user}->[2];
            }

            # Acquire HTTPS redirect status
            $vhosts_hash{$main_domain}{redirect_to_ssl} = $vhosts_hash{$main_domain}{ssl_redirect};

            # Always force new home directory
            $vhosts_hash{$main_domain}{homedir} = $homedir;

            # DocumentRoot
            if ( !$vhosts_hash{$main_domain}{documentroot} ) {
                if ( $user eq 'nobody' ) {
                    $vhosts_hash{$main_domain}{documentroot} = apache_paths_facade->dir_docroot();
                }
                else {
                    $vhosts_hash{$main_domain}{documentroot} = $homedir . '/public_html';
                }
            }

            if ( !-e $vhosts_hash{$main_domain}{documentroot} && -d $homedir ) {
                Cpanel::Debug::log_info("Creating missing document root $vhosts_hash{ $main_domain }{documentroot} for $user");

                require Cpanel::AccessIds::ReducedPrivileges;
                require Cpanel::FileProtect::Sync;
                Cpanel::AccessIds::ReducedPrivileges::call_as_user(
                    sub {
                        mkdir $vhosts_hash{$main_domain}{documentroot};
                    },
                    $user
                );

                my @warnings = Cpanel::FileProtect::Sync::sync_user_homedir($user);
                foreach my $warning (@warnings) {
                    Cpanel::Debug::log_warn($warning);
                }
            }

            # Reset CGI option
            $vhosts_hash{$main_domain}{hascgi} = $hascgi;

            # Jailed
            $vhosts_hash{$main_domain}{jailed} = $jailed;

            my $is_hostname_vhost = Cpanel::Hostname::gethostname() eq $main_domain ? 1 : 0;

            if ( !$vhosts_hash{$main_domain}{ip} ) {
                Cpanel::Debug::log_info("Missing IP for domain $main_domain, using $main_ip") unless $is_hostname_vhost;
                $vhosts_hash{$main_domain}{ip} = $main_ip;
            }
            if ( !$vhosts_hash{$main_domain}{servername} ) {
                Cpanel::Debug::log_info("Missing ServerName for domain $main_domain, using $main_domain") unless $is_hostname_vhost;

                # wildcard encoding of the servername not necessary here since the template does it
                $vhosts_hash{$main_domain}{servername} = $main_domain;
            }

            # PHP-FPM

            if ( Cpanel::PHPFPM::Get::get_php_fpm( $user, $main_domain ) ) {
                $vhosts_hash{$main_domain}{php_fpm} = 1;

                # php_fpm_proxy is a ProxyPass configuration line that will need to be deprecated in future versions
                my ( $php_fpm_proxy, $php_fpm_socket ) = Cpanel::PHPFPM::Get::get_proxy_from_php_config_for_domain( $php_config_ref->{$main_domain} );
                $vhosts_hash{$main_domain}{php_fpm_proxy}  = $php_fpm_proxy;
                $vhosts_hash{$main_domain}{php_fpm_socket} = $php_fpm_socket;
            }
            else {
                $vhosts_hash{$main_domain}{php_fpm} = 0;
            }

            my $main_domain_ip         = $vhosts_hash{$main_domain}{ip};
            my $main_domain_servername = $vhosts_hash{$main_domain}{servername};

            my $ip_primary_servername = $primary_vhosts_cache{$main_domain_ip} ||= $primary_vhosts_obj->get_primary_non_ssl_servername($main_domain_ip);

            # Mark as high priority for vhost sorting (so that it ends up as default for dedicated IPs)
            $vhosts_hash{$main_domain}{sort_priority} = 3;

            $vhosts_hash{$main_domain}{default_vhost_sort_priority} = ( $ip_primary_servername && $ip_primary_servername eq $main_domain_servername ) ? 1 : 0;
            if ( !$vhosts_hash{$main_domain}{port} ) {
                Cpanel::Debug::log_info("Missing port for domain $main_domain, using $main_port") unless $is_hostname_vhost;
                $vhosts_hash{$main_domain}{port} = $main_port;
            }
            elsif ( $main_port ne $vhosts_hash{$main_domain}{port} ) {
                $vhosts_hash{$main_domain}{port} = $main_port;
            }
            if ( !$vhosts_hash{$main_domain}{user} ) {
                Cpanel::Debug::log_info("Missing user for domain $main_domain, using $user") unless $is_hostname_vhost;
                $vhosts_hash{$main_domain}{user} = $user;
            }
            if ( !$vhosts_hash{$main_domain}{owner} ) {
                my $owner = Cpanel::AcctUtils::Owner::getowner( $vhosts_hash{$main_domain}{user} );
                Cpanel::Debug::log_info("Missing owner for domain $main_domain, force lookup to $owner") unless $is_hostname_vhost;
                $vhosts_hash{$main_domain}{owner} = $owner;
            }
            if ( !$vhosts_hash{$main_domain}{group} || !exists $valid_group_names{ $vhosts_hash{$main_domain}{group} } ) {
                my $group = $gid_cache_ref->{ $PWCACHE{$user}->[3] }->[0];
                if ( !$group ) {
                    Cpanel::Debug::log_info("Unable to determine group for $user, skipping domain $main_domain");
                    delete $vhosts_hash{$main_domain};
                    next USERLOOP;
                }
                Cpanel::Debug::log_info("Missing group for domain $main_domain, using $group") unless $is_hostname_vhost;
                $vhosts_hash{$main_domain}{group} = $group;
            }

            #
            # Skip VHOSTS with invalid system users as they will
            # cause apache to not startup.
            #
            # TODO: Check subdomains as well
            #
            if ( !exists $PWCACHE{ $vhosts_hash{$main_domain}{user} } ) {
                my $invalid_user = $vhosts_hash{$main_domain}{user};
                delete $vhosts_hash{$main_domain};
                Cpanel::Debug::log_warn("Skipping vhost generation for server '$main_domain' because the user '$invalid_user' does not exist.");
                next USERLOOP;
            }
            elsif ( !exists $valid_group_names{ $vhosts_hash{$main_domain}{group} } ) {
                my $invalid_group = $vhosts_hash{$main_domain}{group};
                delete $vhosts_hash{$main_domain};
                Cpanel::Debug::log_warn("Skipping vhost generation for server '$main_domain' because the group '$invalid_group' does not exist.");
                next USERLOOP;
            }

            if ( !$vhosts_hash{$main_domain}{log_servername} ) {

                # wildcard encoding of the servername not necessary here since the template does it
                $vhosts_hash{$main_domain}{log_servername} = $vhosts_hash{$main_domain}{servername};
            }

            ## _prepare_ips_array on main domain
            _prepare_ips_array( $main_domain, $vhosts_hash{$main_domain}, $namevirtualhost_ips ) unless ( $user eq 'nobody' );

            # SSL Main Domain - missing information taken from main domain's non-SSL vhost info
            if ( -e $user_store_dir . '/' . $user . '/' . $main_domain . '_SSL' ) {
                #
                # Warning: We are modifing data without making a copy
                # here.  This relys on the legacy behavior of fetch_ref
                # in Cpanel::CachedDataStore which is the underlying
                # code for Cpanel::Config::userdata::Load::load_*
                #

                $vhosts_hash{ $main_domain . '_SSL' } = Cpanel::Config::userdata::Load::load_userdata_domain( $user, $main_domain . '_SSL', $Cpanel::Config::userdata::Load::ADDON_DOMAIN_CHECK_SKIP );
                delete $vhosts_hash{ $main_domain . '_SSL' }{optimize_htaccess};

                # Include numeric UID if they want it
                if ( -e "/etc/cpanel/ea4/option-flags/set-USER_ID" ) {
                    $vhosts_hash{ $main_domain . '_SSL' }{uid} = $PWCACHE{$user}->[2];
                }

                # IP
                $vhosts_hash{ $main_domain . '_SSL' }{ip} ||= $main_ip;

                my $ssl_ip = $vhosts_hash{ $main_domain . '_SSL' }{ip};

                my $primary_ssl_servername = $primary_vhosts_ssl_cache{$ssl_ip} ||= $primary_vhosts_obj->get_primary_ssl_servername($ssl_ip);

                # Mark as high priority for vhost sorting (so that it ends up as default for dedicated IPs)
                $vhosts_hash{ $main_domain . '_SSL' }{sort_priority}               = 3;
                $vhosts_hash{ $main_domain . '_SSL' }{default_vhost_sort_priority} = ( $primary_ssl_servername && $primary_ssl_servername eq $main_domain ) ? 1 : 0;

                # Servername

                # wildcard encoding of the servername not necessary here since the template does it
                $vhosts_hash{ $main_domain . '_SSL' }{servername} ||= $main_domain;

                # wildcard encoding of the servername not necessary here since the template does it
                $vhosts_hash{ $main_domain . '_SSL' }{log_servername} ||= $vhosts_hash{ $main_domain . '_SSL' }{servername};

                # Port
                $vhosts_hash{ $main_domain . '_SSL' }{port} ||= $ssl_port;

                if ( $ssl_port ne $vhosts_hash{ $main_domain . '_SSL' }{port} ) {
                    $vhosts_hash{ $main_domain . '_SSL' }{port} = $ssl_port;
                }

                # User
                $vhosts_hash{ $main_domain . '_SSL' }{user} ||= $user;

                # Owner
                $vhosts_hash{ $main_domain . '_SSL' }{owner} ||= Cpanel::AcctUtils::Owner::getowner( $vhosts_hash{ $main_domain . '_SSL' }{user} );

                # Group
                if ( !$vhosts_hash{ $main_domain . '_SSL' }{group} ) {
                    my $group = $gid_cache_ref->{ $PWCACHE{$user}->[3] }->[0];

                    # No group is a fatal, skip the entire user
                    if ( !$group ) {
                        Cpanel::Debug::log_info("Unable to determine group for $user, skipping domain $main_domain");
                        delete $vhosts_hash{ $main_domain . '_SSL' };
                        next USERLOOP;
                    }
                    $vhosts_hash{ $main_domain . '_SSL' }{group} = $group;
                }

                # DocumentRoot
                if ( !$vhosts_hash{ $main_domain . '_SSL' }{documentroot} ) {
                    if ( $user eq 'nobody' ) {
                        $vhosts_hash{ $main_domain . '_SSL' }{documentroot} = apache_paths_facade->dir_docroot();
                    }
                    else {
                        $vhosts_hash{ $main_domain . '_SSL' }{documentroot} = $homedir . '/public_html';
                    }
                }

                # Homedir
                $vhosts_hash{ $main_domain . '_SSL' }{homedir} = $homedir;

                # Reset CGI option
                $vhosts_hash{ $main_domain . '_SSL' }{hascgi} = $hascgi;

                # Jailed
                $vhosts_hash{ $main_domain . '_SSL' }{jailed} = $jailed;

                # PHP-FPM

                my $ssl_domain = $main_domain . '_SSL';

                if ( Cpanel::PHPFPM::Get::get_php_fpm( $user, $main_domain ) ) {
                    $vhosts_hash{$ssl_domain}{php_fpm} = 1;

                    # php_fpm_proxy is a ProxyPass configuration line that will need to be deprecated in future versions
                    my ( $php_fpm_proxy, $php_fpm_socket ) = Cpanel::PHPFPM::Get::get_proxy_from_php_config_for_domain( $php_config_ref->{$main_domain} );
                    $vhosts_hash{$ssl_domain}{php_fpm_proxy}  = $php_fpm_proxy;
                    $vhosts_hash{$ssl_domain}{php_fpm_socket} = $php_fpm_socket;
                }
                else {
                    $vhosts_hash{$ssl_domain}{php_fpm} = 0;
                }

                my $main_domain       = $main_domain;
                my $vhosts_domain_ssl = $vhosts_hash{ $main_domain . '_SSL' };

                # This may modify $vhosts_domain_ssl if it is missing SSL file information
                # v72+: just call the non-legacy function
                my ( $ssl_ok, $message ) = add_missing_ssl_file_paths_to_userdata_hash( $main_domain, $vhosts_domain_ssl );

                if ($ssl_ok) {

                    # IP migration information
                    ## _prepare_ips_array on main domain + SSL
                    _prepare_ips_array( $main_domain . '_SSL', $vhosts_hash{ $main_domain . '_SSL' }, $namevirtualhost_ips );
                }
                else {
                    # Skipping SSL
                    delete $vhosts_hash{ $main_domain . '_SSL' };
                    Cpanel::Debug::log_warn($message);
                }
            }

        }

        # Sub Domains
      SUBLOOP:
        foreach my $sub (@subdomains) {
            next SUBLOOP unless $sub;

            if ( exists $vhosts_hash{$sub} && $user ne $vhosts_hash{$sub}{user} ) {
                Cpanel::Debug::log_info("Domain ownership conflict detected for $sub, users $user, $vhosts_hash{$sub}{user}");
                next SUBLOOP;
            }

            if ( $vhosts_hr && !$vhosts_hr->{$sub} ) {
                next;
            }

            my %sub_uniq_aliases;

            # Unhandled subdomains are now "parked" on main domain
            if ( -e $user_store_dir . '/' . $user . '/' . $sub ) {
                #
                # Warning: We are modifing data without making a copy
                # here.  This relys on the legacy behavior of fetch_ref
                # in Cpanel::CachedDataStore which is the underlying
                # code for Cpanel::Config::userdata::Load::load_*
                #

                $vhosts_hash{$sub} = Cpanel::Config::userdata::Load::load_userdata_domain( $user, $sub, $Cpanel::Config::userdata::Load::ADDON_DOMAIN_CHECK_SKIP );
                delete $vhosts_hash{$sub}{optimize_htaccess};

                # Include numeric UID if they want it
                if ( -e "/etc/cpanel/ea4/option-flags/set-USER_ID" ) {
                    $vhosts_hash{$sub}{uid} = $PWCACHE{$user}->[2];
                }

                # Acquire HTTPS redirect status
                $vhosts_hash{$sub}{redirect_to_ssl} = $vhosts_hash{$sub}{ssl_redirect};

                # Homedir
                $vhosts_hash{$sub}{homedir} = $homedir;

                # Reset CGI option
                $vhosts_hash{$sub}{hascgi} = $hascgi;

                # Jailed
                $vhosts_hash{$sub}{jailed} = $jailed;

                # Mark as low priority for vhost sorting
                # wildcard vhosts have lowest priority
                if ( Cpanel::WildcardDomain::Tiny::is_wildcard_domain($sub) ) {
                    $vhosts_hash{$sub}{sort_priority} = 0;
                }
                else {
                    $vhosts_hash{$sub}{sort_priority} = 1;
                }

                # IP
                $vhosts_hash{$sub}{ip} ||= $main_ip;
                my $sub_ip = $vhosts_hash{$sub}{ip};

                my $primary_servername_on_ip = $primary_vhosts_cache{$sub_ip} ||= $primary_vhosts_obj->get_primary_non_ssl_servername($sub_ip);
                $vhosts_hash{$sub}{default_vhost_sort_priority} = ( $primary_servername_on_ip && $primary_servername_on_ip eq $sub ) ? 1 : 0;

                # Port
                $vhosts_hash{$sub}{port} = $main_port;

                # User
                $vhosts_hash{$sub}{user} ||= $user;

                # Owner
                $vhosts_hash{$sub}{owner} ||= Cpanel::AcctUtils::Owner::getowner( $vhosts_hash{$sub}{user} );

                # Group
                if ( !$vhosts_hash{$sub}{group} ) {
                    my $group = $gid_cache_ref->{ $PWCACHE{$user}->[3] }->[0];
                    if ( !$group ) {
                        Cpanel::Debug::log_info("Unable to determine group for $user, skipping domain $sub");
                        delete $vhosts_hash{$sub};
                        next SUBLOOP;
                    }
                    $vhosts_hash{$sub}{group} = $group;
                }

                # Servername
                if ( !$vhosts_hash{$sub}{servername} ) {
                    Cpanel::Debug::log_info("Missing ServerName for domain $sub, using $sub");

                    # wildcard encoding of the servername not necessary here since the template does it
                    $vhosts_hash{$sub}{servername} = $sub;
                }
                if ( !$vhosts_hash{$sub}{log_servername} ) {

                    # wildcard encoding of the servername not necessary here since the template does it
                    $vhosts_hash{$sub}{log_servername} = $vhosts_hash{$sub}{servername};
                }

                # DocumentRoot
                if ( !$vhosts_hash{$sub}{documentroot} ) {
                    my $docroot  = $user eq 'nobody' ? apache_paths_facade->dir_docroot() : $homedir . '/public_html';
                    my $sub_part = $sub;
                    $sub_part =~ s/\..*$//;

                  DOCROOTLOOKUP:
                    foreach my $location ( $homedir, $homedir . '/public_html', apache_paths_facade->dir_docroot() ) {
                        if ( -d $location . '/' . $sub_part ) {
                            $docroot = $location . '/' . $sub_part;
                            last DOCROOTLOOKUP;
                        }
                        elsif ( -d $location . '/' . $sub ) {
                            $docroot = $location . '/' . $sub;
                            last DOCROOTLOOKUP;
                        }
                    }
                    $vhosts_hash{$sub}{documentroot} = $docroot;
                }

                if ( !-e $vhosts_hash{$sub}{documentroot} ) {
                    require Cpanel::AccessIds::ReducedPrivileges;
                    require Cpanel::FileProtect::Sync;
                    Cpanel::AccessIds::ReducedPrivileges::call_as_user(
                        sub {
                            mkdir $vhosts_hash{$sub}{documentroot};
                        },
                        $user
                    );

                    my @warnings = Cpanel::FileProtect::Sync::sync_user_homedir($user);
                    foreach my $warning (@warnings) {
                        Cpanel::Debug::log_warn($warning);
                    }
                }

                # Sub Domain ServerAlias
                if ( !exists $vhosts_hash{$sub}{serveralias_array} ) {
                    if ( exists $vhosts_hash{$sub}{serveralias} ) {
                        @sub_uniq_aliases{ split /\s+/, $vhosts_hash{$sub}{serveralias} } = ();
                    }
                }
                else {
                    foreach my $serveralias ( @{ $vhosts_hash{$sub}{serveralias_array} } ) {
                        @sub_uniq_aliases{ split /\s+/, $serveralias } = ();
                    }
                }

                # Ensure subdomain 'www' alias exists and that wildcards are included in serveraliases
                if ( Cpanel::WildcardDomain::Tiny::is_wildcard_domain($sub) ) {
                    $sub_uniq_aliases{$sub} = undef;
                    delete $sub_uniq_aliases{ 'www.' . $sub };
                }
                else {
                    $sub_uniq_aliases{ 'www.' . $sub } = undef;
                    delete $sub_uniq_aliases{$sub};
                }

                $vhosts_hash{$sub}{serveralias_array} = split_arrayref_into_chunks( [ keys %sub_uniq_aliases ], $MAX_SERVERALIASES_PER_LINE );
                $vhosts_hash{$sub}{serveralias}       = join ' ', keys %sub_uniq_aliases;

                # IP migration information
                ## _prepare_ips_array on subdomains
                _prepare_ips_array( $sub, $vhosts_hash{$sub}, $namevirtualhost_ips ) unless ( $user eq 'nobody' );

                # PHP-FPM

                # PHP-FPM stores it's configuration for addon domains as the name of the addon domain
                # this should look up the addon domain and make $fpm_domain the value of the addon domain
                # rather than the subdomain.
                #
                # Limitation:
                # Its possible via the API (not the UI) to park additional domains on top of the underlying
                # subdomain that an addon domain is using. In this case we are chosing the first parked domain
                # we see in the map.  While this has not been a problem in practice, a better solution will
                # be needed in the future.

                my $fpm_domain = $subdomains_to_addons_map_hr->{$sub} ? $subdomains_to_addons_map_hr->{$sub}->[0] : $sub;

                if ( Cpanel::PHPFPM::Get::get_php_fpm( $user, $fpm_domain ) ) {
                    $vhosts_hash{$sub}{php_fpm} = 1;

                    # php_fpm_proxy is a ProxyPass configuration line that will need to be deprecated in future versions
                    my ( $php_fpm_proxy, $php_fpm_socket ) = Cpanel::PHPFPM::Get::get_proxy_from_php_config_for_domain( $php_config_ref->{$fpm_domain} );
                    $vhosts_hash{$sub}{php_fpm_proxy}  = $php_fpm_proxy;
                    $vhosts_hash{$sub}{php_fpm_socket} = $php_fpm_socket;

                }
                else {
                    $vhosts_hash{$sub}{php_fpm} = 0;
                }
            }

            if ( Cpanel::Config::userdata::Load::user_has_ssl_domain( $user, $sub ) ) {
                #
                # Warning: We are modifing data without making a copy
                # here.  This relys on the legacy behavior of fetch_ref
                # in Cpanel::CachedDataStore which is the underlying
                # code for Cpanel::Config::userdata::Load::load_*
                #

                $vhosts_hash{ $sub . '_SSL' } = Cpanel::Config::userdata::Load::load_ssl_domain_userdata( $user, $sub, $Cpanel::Config::userdata::Load::ADDON_DOMAIN_CHECK_SKIP );
                delete $vhosts_hash{ $sub . '_SSL' }{optimize_htaccess};

                # Include numeric UID if they want it
                if ( -e "/etc/cpanel/ea4/option-flags/set-USER_ID" ) {
                    $vhosts_hash{ $sub . '_SSL' }{uid} = $PWCACHE{$user}->[2];
                }

                $vhosts_hash{ $sub . '_SSL' }{homedir} = $homedir;

                # Reset CGI option
                $vhosts_hash{ $sub . '_SSL' }{hascgi} = $hascgi;

                # Jailed
                $vhosts_hash{ $sub . '_SSL' }{jailed} = $jailed;

                # Mark as low priority for vhost sorting
                # wildcard vhosts have lowest priority
                if ( Cpanel::WildcardDomain::Tiny::is_wildcard_domain($sub) ) {
                    $vhosts_hash{ $sub . '_SSL' }{sort_priority} = 0;
                }
                else {
                    $vhosts_hash{ $sub . '_SSL' }{sort_priority} = 1;
                }

                # IP
                $vhosts_hash{ $sub . '_SSL' }{ip} ||= $main_ip;
                my $ssl_sub_ip = $vhosts_hash{ $sub . '_SSL' }{ip};

                my $primary_ssl_servername_on_ip = $primary_vhosts_ssl_cache{$ssl_sub_ip} ||= $primary_vhosts_obj->get_primary_ssl_servername($ssl_sub_ip);
                $vhosts_hash{ $sub . '_SSL' }{default_vhost_sort_priority} = ( $primary_ssl_servername_on_ip && $primary_ssl_servername_on_ip eq $sub ) ? 1 : 0;    # will be set to 1 if its the default vhost for the ip

                # Port
                $vhosts_hash{ $sub . '_SSL' }{port} = $ssl_port;

                # User
                $vhosts_hash{ $sub . '_SSL' }{user} ||= $user;

                # Owner
                $vhosts_hash{ $sub . '_SSL' }{owner} ||= Cpanel::AcctUtils::Owner::getowner( $vhosts_hash{ $sub . '_SSL' }{user} );

                # Group
                if ( !$vhosts_hash{ $sub . '_SSL' }{group} ) {
                    my $group = $gid_cache_ref->{ $PWCACHE{$user}->[3] }->[0];
                    if ( !$group ) {
                        Cpanel::Debug::log_info("Unable to determine group for $user, skipping domain $sub");
                        delete $vhosts_hash{ $sub . '_SSL' };
                        next SUBLOOP;
                    }
                    $vhosts_hash{ $sub . '_SSL' }{group} = $group;
                }

                # Servername
                if ( !$vhosts_hash{ $sub . '_SSL' }{servername} ) {

                    # wildcard encoding of the servername not necessary here since the template does it
                    $vhosts_hash{ $sub . '_SSL' }{servername}     = $sub;
                    $vhosts_hash{ $sub . '_SSL' }{log_servername} = $sub;
                }
                if ( !$vhosts_hash{ $sub . '_SSL' }{log_servername} ) {

                    # wildcard encoding of the servername not necessary here since the template does it
                    $vhosts_hash{ $sub . '_SSL' }{log_servername} = $vhosts_hash{ $sub . '_SSL' }{servername};
                }

                if ( $user eq 'nobody' ) {
                    if ( Cpanel::WildcardDomain::Tiny::is_wildcard_domain($sub) ) {
                        $vhosts_hash{ $sub . '_SSL' }{serveralias}       = $sub;
                        $vhosts_hash{ $sub . '_SSL' }{serveralias_array} = [$sub];
                    }
                    else {
                        $vhosts_hash{ $sub . '_SSL' }{serveralias_array} = [ 'www.' . $sub ];
                        $vhosts_hash{ $sub . '_SSL' }{serveralias}       = 'www.' . $sub;
                    }
                }
                else {

                    # SSL Sub Domain ServerAlias (taken from non-SSL vhost)
                    $vhosts_hash{ $sub . '_SSL' }{serveralias_array} = [];
                    @{ $vhosts_hash{ $sub . '_SSL' }{serveralias_array} } = @{ $vhosts_hash{$sub}{serveralias_array} };
                    $vhosts_hash{ $sub . '_SSL' }{serveralias} = join ' ', keys %sub_uniq_aliases;
                }

                my $vhosts_sub = $vhosts_hash{ $sub . '_SSL' };

                # PHP-FPM

                my $ssl_domain = $sub . '_SSL';

                # PHP-FPM stores it's configuration for addon domains as the name of the addon domain
                # this should look up the addon domain and make $fpm_domain the value of the addon domain
                # rather than the subdomain
                #
                # Limitation:
                # Its possible via the API (not the UI) to park additional domains on top of the underlying
                # subdomain that an addon domain is using. In this case we are chosing the first parked domain
                # we see in the map.  While this has not been a problem in practice, a better solution will
                # be needed in the future.
                my $fpm_domain = $subdomains_to_addons_map_hr->{$sub} ? $subdomains_to_addons_map_hr->{$sub}->[0] : $sub;

                if ( Cpanel::PHPFPM::Get::get_php_fpm( $user, $fpm_domain ) ) {
                    $vhosts_hash{$ssl_domain}{php_fpm} = 1;

                    # php_fpm_proxy is a ProxyPass configuration line that will need to be deprecated in future versions

                    my ( $php_fpm_proxy, $php_fpm_socket ) = Cpanel::PHPFPM::Get::get_proxy_from_php_config_for_domain( $php_config_ref->{$fpm_domain} );
                    $vhosts_hash{$ssl_domain}{php_fpm_proxy}  = $php_fpm_proxy;
                    $vhosts_hash{$ssl_domain}{php_fpm_socket} = $php_fpm_socket;
                }
                else {
                    $vhosts_hash{$ssl_domain}{php_fpm} = 0;
                }

                # This may modify $vhosts_sub if it is missing SSL file information
                # v72+: just call the non-legacy function
                my ( $ssl_ok, $message ) = add_missing_ssl_file_paths_to_userdata_hash( $sub, $vhosts_sub );

                if ($ssl_ok) {

                    # IP Migration information
                    ## _prepare_ips_array on subdomains + SSL
                    _prepare_ips_array( $sub . '_SSL', $vhosts_hash{ $sub . '_SSL' }, $namevirtualhost_ips );
                }
                else {
                    # Skipping SSL
                    delete $vhosts_hash{ $sub . '_SSL' };
                    Cpanel::Debug::log_warn($message);
                }

            }
            delete $vhosts_hash{$sub} if ( $user eq 'nobody' );
        }

        if ($want_main_domain) {

            # Parked Domains and Main Domain ServerAlias
            my %uniq_aliases;
            if ( !exists $vhosts_hash{$main_domain}{serveralias_array} ) {
                if ( exists $vhosts_hash{$main_domain}{serveralias} ) {
                    @uniq_aliases{ split /\s+/, $vhosts_hash{$main_domain}{serveralias} } = ();
                }
            }
            else {
                foreach my $serveralias ( @{ $vhosts_hash{$main_domain}{serveralias_array} } ) {
                    @uniq_aliases{ split /\s+/, $serveralias } = ();
                }
            }

            # Ensure main domain 'www' alias exists and that wildcards are included in serveraliases
            if ( Cpanel::WildcardDomain::Tiny::is_wildcard_domain($main_domain) ) {
                $uniq_aliases{$main_domain} = undef;
                delete $uniq_aliases{ 'www.' . $main_domain };
            }
            else {
                $uniq_aliases{ 'www.' . $main_domain } = undef;
                delete $uniq_aliases{$main_domain};
            }

            @uniq_aliases{ map { $_, Cpanel::WildcardDomain::Tiny::is_wildcard_domain($_) ? () : "www.$_" } @parked_domains } = ();
            my @aliases = sort keys %uniq_aliases;

            $vhosts_hash{$main_domain}{serveralias_array} = split_arrayref_into_chunks( [@aliases], $MAX_SERVERALIASES_PER_LINE );

            $vhosts_hash{$main_domain}{serveralias} = join ' ', @aliases;

            # Main Domain SSL ServerAlias (taken from non-SSL vhost)
            if ( exists $vhosts_hash{ $main_domain . '_SSL' } ) {
                if ( $cpconf->{proxysubdomains} ) {
                    _augment_ssl_vhosts_hash_with_serveralias__proxy_subdomains(
                        $vhosts_hash{ $main_domain . '_SSL' },
                        $user_main_obj,
                        $main_domain,
                        $user,
                        \@aliases,
                    );
                }
                else {
                    _augment_ssl_vhosts_hash_with_serveralias(
                        $vhosts_hash{ $main_domain . '_SSL' },
                        [@aliases],
                    );
                }
            }

            if ( $user eq 'nobody' ) {
                delete $vhosts_hash{$main_domain};
                if ( exists $vhosts_hash{ $main_domain . '_SSL' } ) {

                    # Ensure main domain 'www' alias exists and that wildcards are included in serveraliases
                    if ( Cpanel::WildcardDomain::Tiny::is_wildcard_domain($main_domain) ) {
                        $vhosts_hash{ $main_domain . '_SSL' }{serveralias_array} = [$main_domain];
                        $vhosts_hash{ $main_domain . '_SSL' }{serveralias}       = $main_domain;
                    }
                    else {
                        $vhosts_hash{ $main_domain . '_SSL' }{serveralias_array} = [ 'www.' . $main_domain ];
                        $vhosts_hash{ $main_domain . '_SSL' }{serveralias}       = 'www.' . $main_domain;
                    }
                }
                next;
            }
        }

        # Addon Domains
      ADDONLOOP:
        foreach my $domain ( keys %addon_domains ) {
            my $addon_sub_domain = $addon_domains{$domain};
            next if !$addon_sub_domain;

            if ( $vhosts_hr && !$vhosts_hr->{$addon_sub_domain} ) {
                next;
            }

            # Don't add if subdomain doesn't exist
            if ( !exists $vhosts_hash{$addon_sub_domain} ) {
                Cpanel::Debug::log_warn("Skipping addon domain $domain for $user, corresponding sub domain $addon_sub_domain does not exist");
                next ADDONLOOP;
            }

            my %uniq_aliases;
            if ( !exists $vhosts_hash{$addon_sub_domain}{serveralias_array} ) {
                if ( $vhosts_hash{$addon_sub_domain}{serveralias} ) {
                    @uniq_aliases{ split /\s+/, $vhosts_hash{$addon_sub_domain}{serveralias} } = ();
                }
            }
            else {
                foreach my $serveralias ( @{ $vhosts_hash{$addon_sub_domain}{serveralias_array} } ) {
                    @uniq_aliases{ split /\s+/, $serveralias } = ();
                }
            }

            # Add addon domain name variable for use in templates
            $vhosts_hash{$addon_sub_domain}{addon_domain} = $domain;

            # Include numeric UID if they want it
            if ( -e "/etc/cpanel/ea4/option-flags/set-USER_ID" ) {
                $vhosts_hash{$main_domain}{uid}      = $PWCACHE{$user}->[2];
                $vhosts_hash{$addon_sub_domain}{uid} = $PWCACHE{$user}->[2];
            }

            # Acquire HTTPS redirect status
            $vhosts_hash{$addon_sub_domain}{redirect_to_ssl} = $vhosts_hash{$addon_sub_domain}{ssl_redirect};

            @uniq_aliases{ $domain, Cpanel::WildcardDomain::Tiny::is_wildcard_domain($domain) ? () : "www.$domain" } = ();

            my @aliases = sort keys %uniq_aliases;

            $vhosts_hash{$addon_sub_domain}{serveralias_array} = split_arrayref_into_chunks( [@aliases], $MAX_SERVERALIASES_PER_LINE );
            $vhosts_hash{$addon_sub_domain}{serveralias}       = join ' ', @aliases;

            if ( exists $vhosts_hash{ $addon_sub_domain . '_SSL' } ) {
                $vhosts_hash{ $addon_sub_domain . '_SSL' }{addon_domain} = $domain;

                if ( $cpconf->{proxysubdomains} ) {
                    _augment_ssl_vhosts_hash_with_serveralias__proxy_subdomains(
                        $vhosts_hash{ $addon_sub_domain . '_SSL' },
                        $user_main_obj,
                        $addon_sub_domain,
                        $user,
                        \@aliases,
                    );
                }
                else {
                    _augment_ssl_vhosts_hash_with_serveralias(
                        $vhosts_hash{ $addon_sub_domain . '_SSL' },
                        [@aliases],
                    );
                }
            }
        }
    }

    # Remove main server name vhost
    my $servername = Cpanel::HttpUtils::Conf::get_main_server_name();
    delete $vhosts_hash{$servername};

    # If we load all vhosts we can determine what the correct set of namevirualhosts is
    if ($all_vhosts_loaded) {
        $conf->{namevirtualhosts} = [ sort keys %{$namevirtualhost_ips} ];
        $conf->{sharedips}        = [];

        my $http_port = $conf->{configured}{main_port} || $main_port;

        # In case the main IP has no virtual hosts, this allows a hostname certificate to be issued.
        #
        # If the vhost for the main IP is missing the first one will be the
        # service (formerly proxy) subdomains vhost which has a rewrite rule that will consume
        # the DCV request and prevent DCV from passing.
        #
        if ( $conf->{main_ip} && !exists $namevirtualhost_ips->{"$conf->{main_ip}:$http_port"} ) {
            push @{ $conf->{sharedips} }, "$conf->{main_ip}:$http_port";
        }
        if ( $conf->{main_ipv6} && !exists $namevirtualhost_ips->{"$conf->{main_ipv6}:$http_port"} ) {
            push @{ $conf->{sharedips} }, "$conf->{main_ipv6}:$http_port";
        }

        # CPANEL-13532:
        #
        # Some setups put nginx on port 80 as a proxy to Apache.
        # It’s not uncommon in this case for nginx to forward certain
        # requests to 127.0.0.1 instead of the intended backend IP address.
        # For example, plugins that “translate” Apache’s configuration into
        # something that nginx will parse might have nginx routing.
        # (A specific case is DCV for the hostname certificate.)
        # This is probably not intended; however, it’s widespread enough
        # that we consider it a given.
        #
        # To accommodate this case, we create a dedicated virtual host
        # for 127.0.0.1. This prevents requests to this IP address from
        # hitting the service (formerly proxy) subdomains virtual host instead of the intended
        # content.
        #
        if ( !exists $namevirtualhost_ips->{"127.0.0.1:$http_port"} ) {
            push @{ $conf->{sharedips} }, "127.0.0.1:$http_port";
        }

        my $domainfwdip = Cpanel::DomainForward::get_domain_fwd_ip();
        $conf->{domainfwdip} = $domainfwdip if $domainfwdip;

        foreach my $ip_port ( @{ $conf->{namevirtualhosts} } ) {
            push @{ $conf->{sharedips} }, $ip_port if _shared_ip( $ip_port, domainfwdip => $conf->{domainfwdip} );
        }
        if ( !scalar keys %{$cpconf} ) {
            $cpconf = Cpanel::Config::LoadCpConf::loadcpconf_not_copy();
        }
        if ( $cpconf->{proxysubdomains} ) {

            # add 127.0.0.1 to NameVirtualHosts for service (formerly proxy) subdomains
            push @{ $conf->{namevirtualhosts} }, "127.0.0.1:$http_port";
        }
    }

    return wantarray ? %vhosts_hash : \%vhosts_hash;
}

sub _shared_ip {    ## no critic qw(Subroutines::RequireArgUnpacking)
    my $ip_port = shift || return;
    my %OPTS    = @_;

    my ( $version, $ip, $port ) = Cpanel::IP::Parse::parse( $ip_port, undef, $Cpanel::IP::Parse::BRACKET_IPV6 );
    $port ||= $main_port;

    return unless $ip;

    if ( $OPTS{'domainfwdip'} && $ip eq $OPTS{'domainfwdip'} ) {
        Cpanel::Debug::log_warn("Shared IP $ip is the domain forward ip. Apache will not have a shared vhost on this IP");
    }
    elsif ( $reserved_ips->{$ip} ) {
        Cpanel::Debug::log_warn("Shared IP $ip is reserved. Apache will not listen on this IP");

        # TODO: Should this return false????
    }
    if ( $port eq $ssl_port || _isdedicatedip($ip) ) {
        return;
    }
    return 1;
}

sub _isdedicatedip {
    my ($ip) = @_;
    require Cpanel::DIp::IsDedicated;
    *_isdedicatedip = *Cpanel::DIp::IsDedicated::isdedicatedip;
    return Cpanel::DIp::IsDedicated::isdedicatedip($ip);
}

sub _sort_vhost_arrayref {
    my ($vhosts_ar) = @_;

    # Sort hash by IP, username, then servername
    my @vhosts =
      sort {
             $a->{ip} cmp $b->{ip}
          || $b->{default_vhost_sort_priority} <=> $a->{default_vhost_sort_priority}
          || $b->{sort_priority}               <=> $a->{sort_priority}                 # wildcards need to come after non-wildcards
          || $a->{user} cmp $b->{user}
          || length $b->{servername} <=> length $a->{servername}                       # case 63089: when we sort wildcards, we need to have the longest ones first
          || $a->{servername} cmp $b->{servername}
      } @$vhosts_ar;

    return wantarray ? @vhosts : \@vhosts;
}

sub get_httpd_vhosts_hash {

    # my (@users) = @_;
    return get_hash_for_users_specific_vhosts( \@_ );
}

sub get_httpd_vhosts_sorted {
    my $vhosts_hr = get_httpd_vhosts_hash();

    return _sort_vhost_arrayref( [ map { substr( $_, -4 ) ne '_SSL' ? $vhosts_hr->{$_} : () } keys %$vhosts_hr ] );
}

sub clearcache {
    my $all_cached = shift;

    # this is here to maintain backwards-compatibility
    $conf        = { initialized => 0 };
    %vhosts_hash = ();
    Cpanel::ConfigFiles::Apache::modules::clean_module_caches();
    $wwwacct = {};

    # considering how we fetch $main_ip, merely undefining $main_ip would be useless in practice, as Cpanel::DIp::MainIP also caches this value, consulting it first if set.
    # Effectively, once you've done a fetch once in the same memory context, getmainip and getmainserverip will always return what it first came up with.
    # You have to run Cpanel::DIp::MainIP::clearcache as well if you wanted to truly force a 'fresh' fetch of this value in the same memory context.
    # As such, I'm making this change in CPANEL-9372 for paranoia's sake.
    undef $main_ip;
    Cpanel::DIp::MainIP::clearcache();
    Cpanel::IP::Configured::clear_configured_ips_cache();

    # this is here to reset more than just the above
    if ($all_cached) {
        $dom_owner_lookup_hr = undef;
        $ipmigration_map     = undef;
        $reserved_ips        = undef;
        $cpconf              = undef;
    }
    return;
}

sub _is_phpsuexec_supported {
    return -r Cpanel::Config::Httpd::Paths::suexec_binary_location()
      && Cpanel::CachedCommand::cachedcommand_multifile(
        [ Cpanel::Config::Httpd::Paths::suexec_binary_location() ], '/bin/grep', 'PHPHANDLER',
        Cpanel::Config::Httpd::Paths::suexec_binary_location()
      ) =~ m/(?:PHPHANDLER|matches)/ ? 1 : 0;
}

sub _valid_splitlogs {
    return if !-x Cpanel::Config::Httpd::Paths::splitlogs_binary_location();
    my $out = Cpanel::CachedCommand::cachedcommand( Cpanel::Config::Httpd::Paths::splitlogs_binary_location(), '--bincheck' );
    return $out =~ m/bincheck ok/i ? 1 : 0;
}

sub _splitlogs_enabled {
    my ($conf) = @_;
    my $is_apache2 = $conf->{options_support}->{version} && substr( $conf->{options_support}->{version}, 0, 1 ) >= 2;

    return ( $is_apache2 && $conf->{enable_piped_logs} && $conf->{supported}->{mod_log_config} );
}

sub _configure_logprocessing {
    my ( $conf, $split_conf ) = @_;

    # If splitlogs does not work, we must not enable that functionality.
    if ( $conf->{enable_piped_logs} && !_valid_splitlogs() ) {
        unless ( $ENV{CPANEL_BASE_INSTALL} ) {

            # on a fresh install splitlogs does not get installed until the end
            # after the first upcp
            Cpanel::Debug::log_warn("The splitlogs program could not be executed, disabling piped logs.");
        }
        $conf->{enable_piped_logs} = 0;
    }

    my $logconf_module = $conf->{main}->{ifmodulelogconfigmodule};
    my $logconf        = $conf->{main}->{ifmodulemodlogconfigc} || $conf->{main}->{ifmodulelogconfigmodule};
    my $has_logio      = $conf->{supported}->{mod_logio};

    if ( _splitlogs_enabled($conf) ) {

        # Add new log formats.
        $logconf->{logformat}->{items} = [
            {
                logformat => q["%v:%p %h %l %u %t \"%r\" %>s %b \"%{Referer}i\" \"%{User-Agent}i\"" combinedvhost],
            },
            (
                $has_logio
                ? ( { logformat => q["%v %{%s}t %I .\n%v %{%s}t %O ." bytesvhost], } )
                : ()
            ),
            grep { $_->{logformat} !~ /combinedvhost|bytesvhost/ } @{ $logconf->{logformat}->{items} },
        ];

        foreach my $lconf ( $logconf, $logconf_module ) {

            # Remove old access_log definition
            $lconf->{customlog}->{items} = [ grep { $_->{format} ne 'common' || $_->{target} !~ m("?logs/access_log"?) } @{ $lconf->{customlog}->{items} } ];
        }

        my $extra = '';
        $extra .= " --maxopen=$split_conf->{maxopen}" if defined $split_conf->{maxopen};
        $extra .= " --buffer=$split_conf->{buffer}"   if defined $split_conf->{buffer};
        my $sslport = $split_conf->{sslport} || Cpanel::Config::Httpd::IpPort::get_ssl_httpd_port();
        $extra .= " --sslport=$sslport" if $sslport && 443 != $sslport;
        my $servername = Cpanel::HttpUtils::Conf::get_main_server_name();

        my $split_logs_bin_location = Cpanel::Config::Httpd::Paths::splitlogs_binary_location();

        $logconf->{customlog}->{directive} = 'customlog';

        # Replace new custom logs.
        $logconf->{customlog}->{items} = [
            (
                $has_logio
                ? (
                    {
                        format => 'bytesvhost',
                        target => qq{|$split_logs_bin_location --main=$servername --suffix=-bytes_log$extra},
                    }
                  )
                : ()
            ),
            {
                format => 'combinedvhost',
                target => qq{"|$split_logs_bin_location --main=$servername --mainout=} . apache_paths_facade->file_access_log() . qq{$extra"},
            },
            grep { $_->{format} !~ /bytesvhost|combinedvhost/ } @{ $logconf->{customlog}->{items} }
        ];
    }
    else {
        $logconf->{customlog}->{directive} = 'customlog';

        # Add new log formats.
        $logconf->{logformat}->{items} = [
            grep { $_->{logformat} !~ /combinedvhost|bytesvhost/ } @{ $logconf->{logformat}->{items} },
        ];

        # Clean old access_log definition
        $logconf->{customlog}->{items} = [ grep { $_->{format} ne 'common' || $_->{target} !~ m("?logs/access_log"?) } @{ $logconf->{customlog}->{items} } ];

        # Replace new custom logs.
        $logconf->{customlog}->{items} = [
            {
                format => 'common',
                target => 'logs/access_log',
            },
            grep { $_->{format} !~ /bytesvhost|combinedvhost/ } @{ $logconf->{customlog}->{items} }
        ];
    }
    return;
}

sub get_allow_server_info_status_from {
    if ( !scalar keys %{$cpconf} ) {
        $cpconf = Cpanel::Config::LoadCpConf::loadcpconf_not_copy();
    }
    my $allow_from = exists $cpconf->{allow_server_info_status_from} && $cpconf->{allow_server_info_status_from} ? $cpconf->{allow_server_info_status_from} : '';
    return $allow_from;
}

sub get_httpd_ssl_vhosts_sorted {
    my $vhosts_hr = get_httpd_vhosts_hash();

    return _sort_vhost_arrayref( [ map { substr( $_, -4 ) eq '_SSL' ? $vhosts_hr->{$_} : () } keys %$vhosts_hr ] );
}

=head2 get_config_with_all_vhosts(%opts)

This function returns the same apache configuration
structure as get_config with the 'vhost' and
'ssl_vhosts' keys included which include all the
vhost data.

=cut

sub get_config_with_all_vhosts {
    get_config(@_);
    $conf->{vhosts}     ||= get_httpd_vhosts_sorted();
    $conf->{ssl_vhosts} ||= get_httpd_ssl_vhosts_sorted();
    return $conf;
}

sub get_config {    ##no critic qw(ProhibitExcessComplexity) -- legacy
    my %opts = @_;

    # There's caching going on all over the place, so reset every global
    clearcache() if $opts{force};

    if ( $conf->{initialized} ) {
        return $conf;
    }

    $conf = Cpanel::EA4::Conf::Tiny::get_ea4_conf_distiller_hr();
    $conf->{ea4conf} = Cpanel::EA4::Conf::Tiny::get_ea4_conf_hr();

    delete $conf->{main}{optimize_htaccess};

    my $split_conf = {
        maxopen => undef,
        buffer  => undef,
    };
    Cpanel::Config::LoadConfig::loadConfig( "/var/cpanel/conf/splitlogs.conf", $split_conf );

    $cpconf = Cpanel::Config::LoadCpConf::loadcpconf_not_copy();
    if ( !scalar keys %{$wwwacct} ) {
        $wwwacct = Cpanel::Config::LoadWwwAcctConf::loadwwwacctconf();
    }

    # Initialize $main_ip
    $main_ip ||= Cpanel::NAT::get_local_ip( Cpanel::DIp::MainIP::getmainip() );
    $main_port = Cpanel::Config::Httpd::IpPort::get_main_httpd_port();
    $ssl_port  = Cpanel::Config::Httpd::IpPort::get_ssl_httpd_port();

    $ipmigration_map = _load_ipmigration_map();

    $reserved_ips = Cpanel::Ips::Reserved::load_apache_reserved_ips();

    # This is an OR.  If you specify reserved IP's, then you can't
    # specify an IP in the Tweaksettings port selector
    if ( scalar keys %$reserved_ips ) {
        my %ips = map { $_ => 1 } ( Cpanel::IP::Configured::getconfiguredips() );
        $conf->{configured}{ip_listen}     = ['127.0.0.1'];
        $conf->{configured}{main_port}     = $main_port;
        $conf->{configured}{main_port_ssl} = $ssl_port;
        foreach my $ip ( keys %ips ) {
            next if ( $reserved_ips->{$ip} || $ip eq '127.0.0.1' );    # Exclude 127.0.0.1 as it's added by default
            push @{ $conf->{configured}{ip_listen} }, $ip;
        }
        $conf->{configured}{ip_listen_ssl} = $conf->{configured}{ip_listen};
    }
    else {

        my $configured_httpd_ip_and_port = Cpanel::Config::Httpd::IpPort::get_main_httpd_ip_and_port();

        # If an alternative listen IP is specified, ensure the loop back is also listening
        if ( $configured_httpd_ip_and_port =~ m/(\d+\.\d+\.\d+\.\d+):/ && $1 ne '0.0.0.0' && $1 ne '127.0.0.1' ) {
            $conf->{configured}{ip_listen} = [ $1, '127.0.0.1' ];
            $conf->{configured}{main_port} = $main_port;
        }
        else {
            # Put everything under configured.ip_listen - then we can push [::] onto the list
            my @ip_info = Cpanel::IP::Parse::parse($configured_httpd_ip_and_port);
            $conf->{configured}{ip_listen} = [ $ip_info[1] ];
            $conf->{configured}{main_port} = $ip_info[2];
        }

        my $configured_httpd_ssl_ip_and_port = Cpanel::Config::Httpd::IpPort::get_ssl_httpd_ip_and_port();

        # If an alternative listen IP is specified, ensure the loop back is also listening
        if ( $configured_httpd_ssl_ip_and_port =~ m/(\d+\.\d+\.\d+\.\d+):/ && $1 ne '0.0.0.0' && $1 ne '127.0.0.1' ) {
            $conf->{configured}{ip_listen_ssl} = [ $1, '127.0.0.1' ];
            $conf->{configured}{main_port_ssl} = $ssl_port;
        }
        else {
            # Put everything under configured.ip_listen - then we can push [::] onto the list
            my @ip_info = Cpanel::IP::Parse::parse($configured_httpd_ssl_ip_and_port);
            $conf->{configured}{ip_listen_ssl} = [ $ip_info[1] ];
            $conf->{configured}{main_port_ssl} = $ip_info[2];
        }
    }

    # These can only be known when all vhosts have been loaded!
    # Do not expect namevirtualhosts or sharedips to be correct without a full load
    $conf->{namevirtualhosts} = [];
    $conf->{sharedips}        = [];

    $conf->{main_ip}     = $main_ip;
    $conf->{main_ipv6}   = Cpanel::Validate::IP::is_valid_ipv6( $wwwacct->{ADDR6} ) ? "[$wwwacct->{ADDR6}]"  : undef;
    $conf->{jailapache}  = exists $cpconf->{jailapache}                             ? $cpconf->{jailapache}  : 0;
    $conf->{skipmailman} = exists $cpconf->{skipmailman}                            ? $cpconf->{skipmailman} : 0;

    my $servername = Cpanel::HttpUtils::Conf::get_main_server_name();
    $conf->{compiled_support}              = Cpanel::ConfigFiles::Apache::modules::get_compiled_support();
    $conf->{options_support}               = Cpanel::ConfigFiles::Apache::modules::get_options_support();
    $conf->{so_dir}                        = Cpanel::ConfigFiles::Apache::modules::get_so_dir();
    $conf->{servername}                    = $servername;
    $conf->{serveradmin}                   = Cpanel::HttpUtils::Conf::get_main_server_admin();
    $conf->{allow_server_info_status_from} = get_allow_server_info_status_from();
    $conf->{paths}                         = apache_paths_facade->get_template_hashref();

    if ( $conf->{allow_server_info_status_from} ) {
        $conf->{serve_server_status} = 1;
        $conf->{serve_server_info}   = 1;
    }
    $conf->{proxysubdomains}               = exists $cpconf->{proxysubdomains}               ? $cpconf->{proxysubdomains}               : 0;
    $conf->{autodiscover_proxy_subdomains} = exists $cpconf->{autodiscover_proxy_subdomains} ? $cpconf->{autodiscover_proxy_subdomains} : 0;
    $conf->{logstyle}                      = $wwwacct->{LOGSTYLE} || 'combined';    # Hard-coding default instead of pulling from Whostmgr dependency
    $conf->{scriptalias}                   = length $wwwacct->{SCRIPTALIAS}       && lc $wwwacct->{SCRIPTALIAS} eq 'y' ? 1 : 0;
    $conf->{phpopenbasedirprotect_enabled} = exists $cpconf->{phpopenbasedirhome} && $cpconf->{phpopenbasedirhome}     ? 1 : 0;
    $conf->{userdirprotect_enabled}        = $cpconf->{userdirprotect}    || 0;
    $conf->{enable_piped_logs}             = $cpconf->{enable_piped_logs} || 0;
    $conf->{default_apache_port}           = ( split( /:/, $cpconf->{apache_port}     // '' ) )[1];
    $conf->{default_apache_ssl_port}       = ( split( /:/, $cpconf->{apache_ssl_port} // '' ) )[1];

    if (   Cpanel::IPv6::Has::system_has_ipv6()
        && $conf->{options_support}->{APR_HAVE_IPV6}
        && !$conf->{options_support}->{"v4-mapped"} ) {

        # Add the IPv6 wildcard to the stack of listen addresses
        push @{ $conf->{configured}{ip_listen} }, '[::]';

        # ip_listen_ssl will be a reference to ip_listen if apache reserved ips exist
        if ( $conf->{configured}->{ip_listen} ne $conf->{configured}->{ip_listen_ssl} ) {
            push @{ $conf->{configured}->{ip_listen_ssl} }, '[::]';
        }
    }

    # Reset userdir setting for DefaultHost
    my ( $userdir_status, $userdir_users ) = Cpanel::HttpUtils::Conf::fetchdirprotectconf('DefaultHost');
    if ($userdir_status) {
        $conf->{defaultvhost}{userdirprotect} = $userdir_users;
    }
    else {
        $conf->{defaultvhost}{userdirprotect} = '-1';
    }

    if ( !$conf->{options_support}{version} ) {
        die "Unable to detect Apache version from binary\n";
    }

    $conf->{shared_objects} = Cpanel::ConfigFiles::Apache::modules::get_shared_objects();

    $conf->{supported} = {};

    foreach my $item ( keys %{ $conf->{shared_objects} } ) {
        $item =~ s/\.so$//;
        $conf->{supported}{$item} = 1;
    }
    foreach my $item ( keys %{ $conf->{compiled_support} } ) {
        $item =~ s/\.c$//;
        $conf->{supported}{$item} = 1;
        $item =~ s/^mod_//;
        $conf->{supported}{ $item . '_module' } = 1;
    }

    $conf->{supported}{phpsuexec} = _is_phpsuexec_supported();
    $conf->{supported}{sni}       = 1;
    $conf->{supported}{stapling}  = Cpanel::HttpUtils::SSL::Stapling::is_stapling_supported();

    my $domainfwdip = Cpanel::DomainForward::get_domain_fwd_ip();
    $conf->{domainfwdip} = $domainfwdip if $domainfwdip;

    _configure_logprocessing( $conf, $split_conf );

    $conf->{_use_target_version} = Cpanel::ConfigFiles::Apache::modules::apache_version( { places => 2 } );
    my $template_filebase = "$Cpanel::Template::Files::tmpl_dir/apache$conf->{_use_target_version}/ea4";

    # EA4 custom, EA3 custom (for now), EA4 actual, EA3 actual (for until EA4 actual is published)
    for my $template_file ( "$template_filebase.custom", $template_filebase . "_main.local", "$template_filebase.cpanel", $template_filebase . "_main.default" ) {
        if ( -e $template_file ) {
            $conf->{template_file} = $template_file;
            last;
        }
    }
    die "No templates exist! Please ensure ea-apache24-config-runtime is installed and that the files it owns are all in place and unmodified.\n" if !$conf->{template_file};

    $conf->{path} ||= apache_paths_facade->file_conf();

    $conf->{initialized} = 1;
    return $conf;
}

sub clean_vhosts_hash {
    %vhosts_hash = ();
    return;
}

1;
