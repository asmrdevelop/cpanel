package Whostmgr::Transfers::Session::Preflight::RemoteRoot::Results;

# cpanel - Whostmgr/Transfers/Session/Preflight/RemoteRoot/Results.pm
#                                                  Copyright 2022 cPanel, L.L.C.
#                                                           All rights reserved.
# copyright@cpanel.net                                         http://cpanel.net
# This code is subject to the cPanel license. Unauthorized copying is prohibited

use strict;
use warnings;

use Cpanel::Config::LoadCpConf                                   ();
use Cpanel::ConfigFiles                                          ();
use Cpanel::PwCache::Build                                       ();
use Cpanel::DIp::Group                                           ();
use Cpanel::DIp::Owner                                           ();
use Cpanel::JSON                                                 ();
use Cpanel::Locale                                               ();
use Cpanel::PwCache::GID                                         ();
use Cpanel::Config::LoadUserDomains                              ();
use Cpanel::Version::Full                                        ();
use Cpanel::Hostname                                             ();
use Whostmgr::Transfers::Version                                 ();
use Whostmgr::Transfers::Session::Constants                      ();
use Whostmgr::Transfers::Session::Setup                          ();
use Whostmgr::Transfers::Session::Preflight::RemoteRoot::Modules ();

my $locale;

#Parameters:
#   transfer_session_id (required)
#
sub retrieve_analysis {    ## no critic (ProhibitExcessComplexity)
    my ($opts) = @_;

    if ( !$opts->{'transfer_session_id'} ) {
        $locale ||= Cpanel::Locale->get_handle();
        return ( 0, $locale->maketext("A valid [asis,transfer_session_id] is required to analyze a remote transfer source.") );
    }

    my ( $session_ok, $session_obj ) = Whostmgr::Transfers::Session::Setup::setup_session_obj( { 'id' => $opts->{'transfer_session_id'} } );
    return ( 0, $session_obj ) if !$session_ok;

    my $remote_info  = $session_obj->remoteinfo();
    my $session_info = $session_obj->sessioninfo();

    if ( $session_info->{'session_type'} && $session_info->{'session_type'} != $Whostmgr::Transfers::Session::Constants::SESSION_TYPES{'RemoteRoot'} ) {
        $locale ||= Cpanel::Locale->get_handle();
        return ( 0, $locale->maketext( 'The supplied session ID has an invalid session type. You must provide a session ID with a session type of “[_1]”.', $Whostmgr::Transfers::Session::Constants::SESSION_TYPE_NAMES{ $Whostmgr::Transfers::Session::Constants::SESSION_TYPES{'RemoteRoot'} } ) );
    }

    my $cpversion         = $remote_info->{'cpversion'};
    my $version           = $remote_info->{'version'};
    my $servtype          = $remote_info->{'type'};
    my $host              = $remote_info->{'sshhost'};
    my $xferpoint_version = $remote_info->{'xferpoint_version'};

    my $remote_data = $session_obj->get_data('remote_data');
    my $local_data  = $session_obj->get_data('local_data');

    my $local_roundcube_dbtype  = Cpanel::Config::LoadCpConf::loadcpconf()->{'roundcube_db'};
    my $remote_roundcube_dbtype = $remote_info->{'roundcube_dbtype'};

    my $conflicts = $remote_data->{'conflicts'};

    my $options = $session_obj->options();

    my $available_ips = Cpanel::DIp::Group::get_available_ips();
    my $ip_count      = scalar @{$available_ips};

    my %DISK_SPACE_USED = map { ( split( m{=}, $_, 2 ) )[ 0, 1 ] } grep { !m/(?:^#|^[\s#]*$)/ } split( /\r*\n/, $remote_data->{'dumpquotas'} || '' );
    delete $DISK_SPACE_USED{''};

    my %FILES_USED = map { ( split( m{=}, $_, 2 ) )[ 0, 1 ] } grep { !m/(?:^#|^[\s#]*$)/ } split( /\r*\n/, $remote_data->{'dumpinodes'} || '' );
    delete $FILES_USED{''};

    my %REMOTE_DEDICATEDIPS = map { ( split( m{:\s*}, $_, 2 ) )[ 1, 0 ] } grep { !m/(?:^#|^[\s#]*$)/ } split( /\r*\n/, $remote_data->{'/etc/domainips'} || '' );
    delete $REMOTE_DEDICATEDIPS{''};

    my %LOCAL_DEDICATEDIPS = Cpanel::DIp::Owner::get_all_dedicated_ips();

    my %OWNERS = map { ( split( m{:\s*}, $_, 2 ) )[ 0, 1 ] } grep { !m/(?:^#|^[\s#]*$)/ } split( /\r*\n/, $remote_data->{$Cpanel::ConfigFiles::TRUEUSEROWNERS_FILE} || '' );
    delete $OWNERS{''};

    my $reseller_data = _get_api_result_payload( $remote_data->{'reseller_list'} ) // {};
    my $reseller_list = $reseller_data->{'reseller'} || [];
    push( @$reseller_list, 'root' );

    my %RESELLERS = map { $_ => 1 } @$reseller_list;
    delete $RESELLERS{''};

    my %MAINDOMAINS = map {
        my $ref = [ ( split( m{:\s*}, $_, 2 ) ) ];
        $ref->[1] =~ s/\^site[0-9]+$//;    # for ensim: convert example1^site1 to example1
        ( $ref->[0] => $ref->[1] )
      }
      grep { !m/(?:^#|^[\s#]*$)/ }
      split( /\r*\n/, $remote_data->{$Cpanel::ConfigFiles::TRUEUSERDOMAINS_FILE} || '' );
    delete $MAINDOMAINS{''};

    # note this is identical above in non ensim tranfers
    my %ENSIMDOMAINUSERS = map {
        my $ref = [ ( split( m{:\s*}, $_, 2 ) ) ];
        ( $ref->[0] => $ref->[1] )
      }
      grep { !m/(?:^#|^[\s#]*$)/ }
      split( /\r*\n/, $remote_data->{$Cpanel::ConfigFiles::TRUEUSERDOMAINS_FILE} || '' );
    delete $ENSIMDOMAINUSERS{''};

    if ( $remote_info->{'type'} eq "ensim" ) {

        # need to deal with possible duplicates

        my %user_counts;

        foreach my $domain ( keys %MAINDOMAINS ) {
            my $user = $MAINDOMAINS{$domain};
            if ( exists $user_counts{$user} ) {
                $user_counts{$user}++;
            }
            else {
                $user_counts{$user} = 1;
            }
        }

        foreach my $user ( keys %user_counts ) {
            my $count = $user_counts{$user};
            if ( $count == 1 ) { next; }

            foreach my $domain ( keys %MAINDOMAINS ) {
                if ( $MAINDOMAINS{$domain} eq $user ) {
                    my $xuser = $ENSIMDOMAINUSERS{$domain};
                    my ( $yuser, $ysite ) = split( /\^/, $xuser );

                    # to make sure the first 8 chars are unique reverse order
                    # site and username

                    $xuser = $ysite . $yuser;

                    $MAINDOMAINS{$domain} = $xuser;
                }
            }
        }
    }

    my %ALLDOMAINS = map { ( split( m{:\s*}, $_, 2 ) )[ 0, 1 ] } grep { !m/(?:^#|^[\s#]*$)/ } split( /\r*\n/, $remote_data->{'/etc/userdomains'} || '' );
    delete $ALLDOMAINS{''};
    delete $ALLDOMAINS{'*'};    # *: nobody

    my $has_package_extensions = $remote_data->{'has_package_extensions'};
    my %PKGS                   = map { $_ => undef } grep { !m{^\s*$} } split( m{\r*\n}, $remote_data->{'packages'} || '' );
    if ($has_package_extensions) {
        delete $PKGS{'extensions'};
    }

    my %PKGFEATURES = map {
        my $pkg_ref = [ split( m{:\s*}, $_, 2 ) ];
        ( split( m{/}, $pkg_ref->[0] ) )[-1] => ( split( m{=}, $pkg_ref->[1], 2 ) )[-1]
    } split( /\r*\n/, $remote_data->{'featurelists'} || '' );

    my $worker_nodes_ar = _get_api_result_payload( $remote_data->{'user_worker_nodes'} ) || [];
    my $linked_nodes_ar = _get_api_result_payload( $remote_data->{'linked_nodes'} )      || [];

    my %LOCALUSERS   = map { $_->[0] => 1 } @{ Cpanel::PwCache::Build::fetch_pwcache() };
    my $localdomains = Cpanel::Config::LoadUserDomains::loaduserdomains( undef, 1 );
    my %LOCALGROUPS  = map { $_->[0] => 1 } values %{ Cpanel::PwCache::GID::get_gid_cacheref() };

    my $remote_dbs     = eval { Cpanel::JSON::Load( $remote_data->{'dump_databases_and_users'} ) };
    my $local_dbs      = eval { Cpanel::JSON::Load( $local_data->{'dump_databases_and_users'} ) };
    my $remote_version = 0;
    if ($cpversion) {
        $remote_version = Whostmgr::Transfers::Version::servtype_to_version($servtype);
    }

    my $items_packages = [
        map {
            {
                'name'        => $_,                 #
                'featurelist' => $PKGFEATURES{$_}    #
            }
        } sort keys %PKGS
    ];
    my $items_accounts = [
        map {
            my $user         = $MAINDOMAINS{$_};
            my %worker_nodes = map { $_->{'type'} => $_->{'alias'} } grep { $_->{'user'} eq $user } @{$worker_nodes_ar};
            {
                'user'             => $user,                                          #
                'ensim_user'       => $ENSIMDOMAINUSERS{$_},                          #
                'domain'           => $_,                                             #
                'bytesused'        => ( ( $DISK_SPACE_USED{$user} || 0 ) * 1024 ),    #
                'filesused'        => ( ( $FILES_USED{$user}      || 0 ) ),           #
                'owner'            => $OWNERS{$user},                                 #
                'has_dedicated_ip' => ( $REMOTE_DEDICATEDIPS{$_} ? 1 : 0 ),
                'worker_nodes'     => \%worker_nodes,
            }
        } sort keys %MAINDOMAINS
    ];

    my %analysis = (
        'transfer_session_id' => $session_obj->id(),
        'items'               => {
            'packages' => $items_packages,
            'accounts' => $items_accounts,
        },
        'local' => {
            'dedicated_ips'    => \%LOCAL_DEDICATEDIPS,
            'groups'           => \%LOCALGROUPS,
            'users'            => \%LOCALUSERS,
            'domains'          => $localdomains,
            'dbs'              => $local_dbs,
            'version'          => Cpanel::Version::Full::getversion(),
            'available_ips'    => $available_ips,
            'host'             => Cpanel::Hostname::gethostname(),
            'major_version'    => join( '.', ( split( m{\.}, Cpanel::Version::Full::getversion() ) )[ 0, 1 ] ),
            'roundcube_dbtype' => $local_roundcube_dbtype,
        },
        'remote' => {
            'dbs'                     => $remote_dbs,
            'resellers'               => \%RESELLERS,
            'has_owners'              => ( $remote_data->{$Cpanel::ConfigFiles::TRUEUSEROWNERS_FILE} ? 1 : 0 ),
            'has_disk_used'           => ( scalar keys %DISK_SPACE_USED                              ? 1 : 0 ),
            'has_files_used'          => ( scalar keys %FILES_USED                                   ? 1 : 0 ),
            'has_xfertool'            => ( $xferpoint_version                                        ? 1 : 0 ),
            'server_type'             => $servtype,
            'hostname'                => $remote_data->{'hostname'},
            'cpversion'               => $remote_version,
            'version'                 => $version,
            'host'                    => $host,
            'has_package_extensions'  => ( $has_package_extensions ? 1 : 0 ),
            'conflicts'               => Cpanel::JSON::Load($conflicts),
            'major_version'           => $remote_version ? join( '.', ( split( m{\.}, $version ) )[ 0, 1 ] ) : undef,    # undef if not cPanel
            'roundcube_dbtype'        => $remote_roundcube_dbtype,
            'linked_nodes'            => $linked_nodes_ar,
            'supports_live_transfers' => $remote_data->{'supports_live_transfers'},
        },
        'config' => {
            'shared_mysql_server' => $remote_info->{'shared_mysql_server'},
        },
        'options' => {
            'unrestricted'        => $options->{'unrestricted'},
            'skip_reseller_privs' => $options->{'skipres'},
        }
    );

    my $mods = Whostmgr::Transfers::Session::Preflight::RemoteRoot::Modules::get_module_objects();
    foreach my $mod ( sort keys %{$mods} ) {

        $analysis{'modules'}{$mod}{'analysis'} = $mods->{$mod}->parse_analysis_commands($remote_data);
        $analysis{'modules'}{$mod}{'name'}     = $mods->{$mod}->name();

        if ( exists( $analysis{'modules'}{$mod}{'analysis'}{'warnings'} ) ) {
            foreach my $warning_line ( @{ $analysis{'modules'}{$mod}{'analysis'}{'warnings'} } ) {
                $analysis{'modules'}{$mod}{'warning'} .= $warning_line . "\n";
            }
            delete $analysis{'modules'}{$mod}{'analysis'}{'warnings'};
        }

        if ( exists( $analysis{'modules'}{$mod}{'analysis'}{'errors'} ) ) {
            foreach my $error_line ( @{ $analysis{'modules'}{$mod}{'analysis'}{'errors'} } ) {
                $analysis{'modules'}{$mod}{'error'} .= $error_line . "\n";
            }
            delete $analysis{'modules'}{$mod}{'analysis'}{'errors'};
        }

        # Clean up output of raw keys a bit for display in UI
        foreach my $key ( keys %{ $analysis{'modules'}{$mod}{'analysis'} } ) {
            my $cleankey = $key;
            $cleankey =~ s/_/ /g;
            $analysis{'modules'}{$mod}{'analysis'}{$cleankey} = $analysis{'modules'}{$mod}{'analysis'}{$key};
            delete $analysis{'modules'}{$mod}{'analysis'}{$key};
        }
    }
    $session_obj->disconnect();    # TP TASK 20767 disconnect before global destruct

    return ( 1, \%analysis );
}

sub _get_api_result_payload {
    my ($api_result_json) = @_;

    my $api_result = eval { Cpanel::JSON::Load( $api_result_json || '' ) };

    if ( $api_result && $api_result->{'metadata'} && $api_result->{'metadata'}->{'result'} && $api_result->{'data'} ) {
        return $api_result->{'data'}->{'payload'} ? $api_result->{'data'}->{'payload'} : $api_result->{'data'};
    }

    return;
}

1;
