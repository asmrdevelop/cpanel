package Whostmgr::Transfers::Session::Preflight::RemoteRoot::Analyze;

# cpanel -            Whostmgr/Transfers/Session/Preflight/RemoteRoot/Analyze.pm
#                                                    Copyright 2022 cPanel, L.L.C.
#                                                           All rights reserved.
# copyright@cpanel.net                                         http://cpanel.net
# This code is subject to the cPanel license. Unauthorized copying is prohibited

=encoding utf-8

=head1 NAME

Whostmgr::Transfers::Session::Preflight::RemoteRoot::Analyze - Do Analysis of server for transfer

=head1 SYNOPSIS

    use Whostmgr::Transfers::Session::Preflight::RemoteRoot::Analyze;

=head1 DESCRIPTION

This is used by the transfer system to do an analysis of the remote system
to determine accounts and modules that are potentially available for transfer.

=cut

use cPstrict;

use Cpanel::Locale                   ();
use Cpanel::SafeRun::Simple          ();
use Cpanel::SafeRun::Errors          ();
use Cpanel::Exception                ();
use Cpanel::JSON                     ();
use Cpanel::Sys::Hostname            ();
use Cpanel::Ips::Fetch               ();
use Cpanel::MysqlUtils::MyCnf::Basic ();
use Cpanel::IP::Loopback             ();
use Cpanel::Capture                  ();
use Cpanel::SocketIP                 ();
use Cpanel::Version::Compare         ();

use Try::Tiny;

use Whostmgr::Transfers::Session::Constants          ();
use Whostmgr::Remote                                 ();
use Whostmgr::Remote::CommTransport                  ();
use Whostmgr::Remote::State                          ();
use Whostmgr::Transfers::Session::Remotes            ();
use Whostmgr::Transfers::Session::Setup              ();
use Whostmgr::Transfers::Session::Preflight::Restore ();

use Whostmgr::Transfers::Session::Preflight::RemoteRoot::Modules ();

our $MIN_BIN_PKGACCT_VERSION = 4.0;
our $BIN_PKGACCT_PATH        = '/usr/local/cpanel/bin/pkgacct';
our $CPCONF_RUN_KEY          = '_cpconf_run';

my $locale;

sub analyze_remote {
    my (@args) = @_;

    local $SIG{'__DIE__'} = 'DEFAULT';

    my $ret = Cpanel::Capture::trap_stdout(
        sub {
            return __PACKAGE__->_analyze_remote(@args);
        }
    );

    my @captured_return = @{ $ret->{'return'} };
    if ( !scalar @captured_return ) {
        @captured_return = ( 0, $ret->{'EVAL_ERROR'} );
    }

    return ( @captured_return[ 0, 1 ], $ret->{'output'} );
}

sub _analyze_remote {
    my ( $class, $opts ) = @_;

    if ( !$opts->{'transfer_session_id'} ) {
        return ( 0, _locale()->maketext( "You must submit a valid “[_1]” to analyze a remote transfer source.", 'transfer_session_id' ) );
    }

    my ( $session_ok, $session_obj ) = Whostmgr::Transfers::Session::Setup::setup_session_obj( { 'id' => $opts->{'transfer_session_id'} } );
    return ( 0, $session_obj ) if !$session_ok;

    my $self = {
        'session_obj'         => $session_obj,
        'remote_info'         => $session_obj->remoteinfo(),
        'session_info'        => $session_obj->sessioninfo(),
        'options'             => $session_obj->options(),
        'current_phase'       => 0,
        'local_versions'      => {},
        'remote_exec_results' => {},
    };

    bless $self, $class;

    if ( $self->{'session_info'}->{'session_type'} && $self->{'session_info'}->{'session_type'} != $Whostmgr::Transfers::Session::Constants::SESSION_TYPES{'RemoteRoot'} ) {
        return ( 0, _locale()->maketext( 'The supplied session ID has an invalid session type. You must provide a session ID with a session type of “[_1]”.', $Whostmgr::Transfers::Session::Constants::SESSION_TYPE_NAMES{ $Whostmgr::Transfers::Session::Constants::SESSION_TYPES{'RemoteRoot'} } ) );
    }

    foreach my $path (

        #Phase Zero
        qw(
        _create_whm_remote
        _generate_remote_exec
        _exec_phase
        _extract_cpconftool
        _check_supports_live_transfers
        ),

        #Phase One
        qw(
        _synctransfers
        _install_pkgacct_tools_on_remote_and_add_to_this_phase
        _update_outdated_scripts_and_add_to_this_phase
        _exec_phase
        ),

        #Phase Two
        qw(
        _determine_license_status
        _determine_remote_mysql_configuration
        _determine_remote_disk_space
        _determine_roundcube_dbtype
        _save_analysis_into_session
        )
    ) {

        my ( $status, $msg ) = $self->$path();
        if ( !$status ) {
            $session_obj->disconnect();    # TP TASK 20767 disconnect before global destruct
            return ( 0, $msg );
        }
    }

    $session_obj->disconnect();    # TP TASK 20767 disconnect before global destruct

    if ( $self->{'shared_mysql_server'} && !$self->{'options'}->{'unrestricted'} ) {
        return ( 0, _locale()->maketext( "The Restricted Restore mode is not available because the local machine and the source server share the same [output,asis,MySQL] server with the address: “[_1]”.", $self->{'remote_mysql_ip'} ) );
    }

    my ( $adjust_ok, $adjust_msg ) = Whostmgr::Transfers::Session::Preflight::Restore::ensure_mysql_is_sane_for_restore( 'open-files-limit' => $self->{'mysql-open-files-limit'}, 'max-allowed-packet' => $self->{'mysql-max-allowed-packet'} );
    return ( $adjust_ok, $adjust_msg ) if !$adjust_ok;

    return ( 1, 'ok' );
}

sub _create_whm_remote {
    my ($self) = @_;

    my $authinfo_hr = $self->{'session_obj'}->authinfo();

    my $remoteobj;

    my %args = (
        %{ $self->{'session_obj'}->authinfo() },
        'host'                  => $self->{'remote_info'}->{'sshhost'},
        'enable_custom_pkgacct' => $self->{'options'}->{'enable_custom_pkgacct'} ? 1 : 0,
        'scriptdir'             => $self->{'session_info'}->{'scriptdir'},
    );

    my $comm_xport              = $authinfo_hr->{'comm_transport'};
    my $cpsrvd_tls_verification = Whostmgr::Remote::CommTransport::get_cpsrvd_tls_verification($comm_xport);

    if ($cpsrvd_tls_verification) {
        $args{'tls_verification'} = $cpsrvd_tls_verification;

        require Whostmgr::Remote::CommandStream::Legacy;
        $remoteobj = Whostmgr::Remote::CommandStream::Legacy->new( \%args );

        $self->{'remoteobj'} = $remoteobj;
    }
    else {
        $args{'port'} = $self->{'remote_info'}->{'sshport'};

        ( my $new_ok, $remoteobj ) = Whostmgr::Remote->new_trap_exceptions( \%args );

        $self->{'remoteobj'} = $remoteobj if $new_ok;
    }

    return ( 1, $remoteobj );
}

sub _save_analysis_into_session {
    my ($self) = @_;

    my $dump_databases_and_users = Cpanel::SafeRun::Simple::saferun("$Whostmgr::Remote::LOCAL_PKGACCT_DIR/dump_databases_and_users");

    my $db_conflicts = $self->_determine_database_name_conflicts( $dump_databases_and_users, $self->{'remote_exec_results'}->{'dump_databases_and_users'} );

    my $exec_results = $self->{'remote_exec_results'};

    my $err;
    try {

        $self->{'session_obj'}->set_data(
            {
                'remote' => {
                    'xferpoint_version'          => $self->_version_string( $exec_results->{'xferpoint_VERSION'} ),
                    'pkgacct_file'               => $self->{'pkgacct_remote_filename'},
                    'shared_mysql_server'        => $self->{'shared_mysql_server'},
                    'mysql-open-files-limit'     => $self->{'mysql-open-files-limit'},
                    'mysql-max-allowed-packet'   => $self->{'mysql-max-allowed-packet'},
                    'pkgacct-target'             => $self->{'pkgacct-target'},
                    'pkgacct-target-blocks_free' => $self->{'pkgacct-target-blocks_free'},
                    'pkgacct-target-inodes_free' => $self->{'pkgacct-target-inodes_free'},
                    'roundcube_dbtype'           => $self->{'roundcube_dbtype'},
                    'is_cpanel_license_valid'    => $self->{'is_cpanel_license_valid'},
                },
                'local_data' => {
                    'dump_databases_and_users_VERSION' => $self->{'local_versions'}->{'dump_databases_and_users_VERSION'},
                    'dump_databases_and_users'         => $dump_databases_and_users,
                },
                'remote_data' => {
                    'conflicts' => Cpanel::JSON::Dump($db_conflicts),
                },
            }
        );

        # Just in case the hostname got this far with trailing CRLF.
        local $exec_results->{'hostname'} = ( $exec_results->{'hostname'} =~ s<[\r\n]+\z><>r ) if $exec_results->{'hostname'};

        # Avoid mysql max packet length problems
        foreach my $key ( keys %$exec_results ) {

            $self->{'session_obj'}->set_data(
                {
                    'remote_data' => { $key => $exec_results->{$key} },
                }
            );
        }
    }
    catch { $err = $_ };

    if ($err) {
        return ( 0, Cpanel::Exception::get_string($err) );
    }
    return ( 1, 'ok' );
}

sub _determine_database_name_conflicts {
    my ( $self, $local_db_and_users, $remote_db_and_users ) = @_;

    return if !$remote_db_and_users || !$remote_db_and_users;

    my $remote_dbs = eval { Cpanel::JSON::Load($remote_db_and_users) } || {};
    my $local_dbs  = eval { Cpanel::JSON::Load($local_db_and_users) }  || {};

    my %conflicts;
    foreach my $dbobject ( keys %{$local_dbs} ) {
        foreach my $dbsystem ( keys %{ $local_dbs->{$dbobject} } ) {
            my $local_list  = $local_dbs->{$dbobject}{$dbsystem};
            my $remote_list = $remote_dbs->{$dbobject}{$dbsystem};
            foreach my $item ( keys %{$local_list} ) {
                if ( $remote_list->{$item} && $local_list->{$item}{'owner'} ne $remote_list->{$item}{'owner'} ) {
                    my $local_owner  = $local_list->{$item}{'owner'};
                    my $remote_owner = $remote_list->{$item}{'owner'};

                    $conflicts{$remote_owner}{$dbobject}{$dbsystem}{$item} = {
                        'remote_owner' => $remote_owner,
                        'local_owner'  => $local_owner,
                    };
                }
            }
        }
    }
    return \%conflicts;
}

sub _version_string {
    my ( $self, $version_output ) = @_;

    if ( !length $version_output ) { return ''; }

    my ($version_string) = $version_output =~ m{VERSION:? (\S+)};

    return "$version_string";
}

sub _synctransfers {
    my ($self) = @_;

    # No need to download the transfer scripts for non-cPanel platforms
    # if the remote is cPanel & WHM
    if ( $self->{'remote_info'}->{'type'} !~ m{^WHM} ) {
        Cpanel::SafeRun::Errors::saferunnoerror('/usr/local/cpanel/scripts/synctransfers');
    }

    return ( 1, 'ok' );
}

sub _determine_remote_mysql_configuration {
    my ($self) = @_;

    my $analyze_config_ref = $self->_get_analyze_config();

    my %REMOTE_IPS = map { my $ip = $_; $ip =~ s/\s+//g; $ip => 1 } split( m{,}, $analyze_config_ref->{'ips'} );
    if ( $self->{'remote_info'}->{'sship'} ) {
        $REMOTE_IPS{ $self->{'remote_info'}->{'sship'} } = 1;
    }
    my %LOCAL_IPS = Cpanel::Ips::Fetch::fetchipslist();    #we need a copy

    my $local_dbhost             = Cpanel::MysqlUtils::MyCnf::Basic::getmydbhost() || 'localhost';
    my $local_dbhost_ip          = Cpanel::SocketIP::_resolveIpAddress( $local_dbhost, 'timeout' => 5 );
    my $local_dbhost_is_loopback = Cpanel::IP::Loopback::is_loopback($local_dbhost) ? 1 : 0;

    my $remote_dbhost             = $analyze_config_ref->{'mysql-host'} || 'localhost';
    my $remote_dbhost_ip          = Cpanel::SocketIP::_resolveIpAddress( $remote_dbhost, 'timeout' => 5 );
    my $remote_dbhost_is_loopback = Cpanel::IP::Loopback::is_loopback($remote_dbhost) ? 1 : 0;

    my $remote_mysql_ip     = $local_dbhost_ip;
    my $shared_mysql_server = 0;

    if ( $LOCAL_IPS{$remote_dbhost_ip} && !$remote_dbhost_is_loopback ) {
        #
        #LOCAL server is the shared mysql host
        #
        $shared_mysql_server = 1;
        $remote_mysql_ip     = $remote_dbhost_ip;
    }
    elsif ( $REMOTE_IPS{$local_dbhost_ip} && !$local_dbhost_is_loopback ) {
        #
        #REMOTE server is the shared mysql host
        #

        $shared_mysql_server = 1;
    }
    elsif ( $local_dbhost_ip eq $remote_dbhost_ip && !$local_dbhost_is_loopback && !$remote_dbhost_is_loopback ) {
        #
        # Some other server is the shared mysql host
        #
        $shared_mysql_server = 1;
    }

    $self->{'shared_mysql_server'}      = $shared_mysql_server;
    $self->{'remote_mysql_ip'}          = $remote_mysql_ip;
    $self->{'mysql-open-files-limit'}   = $analyze_config_ref->{'mysql-open-files-limit'}   || 2048;
    $self->{'mysql-max-allowed-packet'} = $analyze_config_ref->{'mysql-max-allowed-packet'} || '16M';

    return ( 1, 'ok' );
}

sub _determine_remote_disk_space {
    my ($self) = @_;

    my $analyze_config_ref = $self->_get_analyze_config();

    $self->{'pkgacct-target'}             = $analyze_config_ref->{'pkgacct-target'}             || '';
    $self->{'pkgacct-target-blocks_free'} = $analyze_config_ref->{'pkgacct-target-blocks_free'} || '';
    $self->{'pkgacct-target-inodes_free'} = $analyze_config_ref->{'pkgacct-target-inodes_free'} || '';

    return ( 1, 'ok' );
}

sub _determine_roundcube_dbtype {
    my ($self) = @_;

    my $analyze_config_ref = $self->_get_analyze_config();

    $self->{'roundcube_dbtype'} = ( split( '=', $self->{'remote_exec_results'}->{'roundcube_dbtype'} ) )[1] || '';
    chomp $self->{'roundcube_dbtype'};

    return ( 1, 'ok' );
}

sub _determine_license_status {
    my ($self) = @_;

    my $analyze_config_ref = $self->_get_analyze_config();

    if ( $self->{'remote_exec_results'}->{'is_cpanel_license_valid'} =~ m/does not have a valid license/ ) {
        return ( 0, _locale()->maketext('The source server does not contain a valid license. You cannot transfer accounts from an unlicensed server.') );
    }

    return ( 1, 'ok' );
}

sub _get_analyze_config {
    my ($self) = @_;
    my %ANALYZE_CONFIG = map { ( split( m{\s*:\s*}, $_, 2 ) )[ 0, 1 ] } split( /\n/, $self->{'remote_exec_results'}->{'analyze_config'} || '' );
    return \%ANALYZE_CONFIG;
}

sub _install_pkgacct_tools_on_remote_and_add_to_this_phase {
    my ($self) = @_;

    my ( $pkgacct_remote_filename, $pkgacct_source_filename );

    if ( $self->{'remote_info'}->{'type'} !~ m{^WHM} ) {
        my $locations_ref = Whostmgr::Transfers::Session::Remotes::get_locations_for_server_type( $self->{'remote_info'}->{'type'} );

        $pkgacct_source_filename = $locations_ref->{'pkgacct_script'};
        if ( !length $pkgacct_source_filename ) {
            die "Missing “pkgacct_script” for server type “$self->{'remote_info'}->{'type'}”!";
        }

        my ( $userdomains_copy_ok, $userdomains_copy_msg ) = $self->{'remoteobj'}->remotescriptcopy(
            'srcfile' => $locations_ref->{'updateuserdomains_script'},
        );

        if ( !$userdomains_copy_ok ) {
            return ( 0, _locale()->maketext( "The system failed to upload the file “[_1]” to the remote server because of an error: [_2]", $locations_ref->{'updateuserdomains_script'}, $userdomains_copy_msg ) );
        }

        $self->_queue_remote_exec( { 'key' => 'non_native_updatedomains_update', 'shell_safe_arguments' => '', 'shell_safe_command' => "$self->{'session_info'}->{'scriptdir'}/$locations_ref->{'updateuserdomains_script'}" } );

        if ( $locations_ref->{'packages_script'} ) {
            my ( $pkgcopy_ok, $pkgcopy_msg ) = $self->{'remoteobj'}->remotescriptcopy(
                'srcfile'  => $locations_ref->{'packages_script'},
                'destfile' => 'packages',
            );

            if ( !$pkgcopy_ok ) {
                return ( 0, _locale()->maketext( "The system failed to upload the file “[_1]” to the remote server because of an error: [_2]", $locations_ref->{'packages_script'}, $pkgcopy_msg ) );
            }

            $self->_queue_remote_exec( { 'key' => 'non_native_packages_update', 'shell_safe_arguments' => '', 'shell_safe_command' => "$self->{'session_info'}->{'scriptdir'}/package" } );
        }
    }

    if ( $pkgacct_source_filename || ( $self->{'options'}->{'enable_custom_pkgacct'} && -e "$Whostmgr::Remote::CUSTOM_PKGACCT_DIR/pkgacct" ) ) {
        $pkgacct_remote_filename = 'pkgacct.' . Cpanel::Sys::Hostname::gethostname();
        my ( $pkgacct_copy_ok, $pkgacct_copy_msg ) = $self->{'remoteobj'}->remotescriptcopy(
            'srcfile'  => ( $pkgacct_source_filename || 'pkgacct' ),    # This is really "$Whostmgr::Remote::CUSTOM_PKGACCT_DIR/pkgacct"
            'destfile' => $pkgacct_remote_filename,
        );

        if ( !$pkgacct_copy_ok ) {
            return ( 0, _locale()->maketext( "The system failed to upload the file “[_1]” to the remote server because of an error: [_2]", $pkgacct_source_filename, $pkgacct_copy_msg ) );
        }
    }

    if ($pkgacct_remote_filename) {
        $self->{'pkgacct_remote_filename'} = $pkgacct_remote_filename;
    }
    elsif ( $self->{'remote_exec_results'}->{'pkgacct_bin_VERSION'} && $self->{'remote_exec_results'}->{'pkgacct_bin_VERSION'} > $MIN_BIN_PKGACCT_VERSION ) {
        $self->{'pkgacct_remote_filename'} = $BIN_PKGACCT_PATH;
    }

    #FORCE this to run before the pkgacct stuff, since it fixes the .my.cnf
    my $dump_databases_and_users_script = 'dump_databases_and_users';
    if ( $self->{'remote_info'}->{'type'} !~ m{^WHM} ) {
        my $locations_ref = Whostmgr::Transfers::Session::Remotes::get_locations_for_server_type( $self->{'remote_info'}->{'type'} );

        if ( $locations_ref->{'dump_databases_and_users_script'} ) {
            $dump_databases_and_users_script = $locations_ref->{'dump_databases_and_users_script'};
        }
    }
    $self->_queue_remote_exec(
        {
            'key'                  => 'dump_databases_and_users',
            'shell_safe_arguments' => '',
            'shell_safe_command'   => "$self->{'session_info'}->{'scriptdir'}/$dump_databases_and_users_script"
        }
    );

    #NOTE: Nothing actually seems to consume this .. ?
    return ( 1, $pkgacct_remote_filename );
}

sub _generate_remote_exec {
    my ($self) = @_;

    # TODO: add a flag to only turn this on when needed so we don't
    # do on every account transfer if it gets to the point these
    # commands are expensive
    my $mods = Whostmgr::Transfers::Session::Preflight::RemoteRoot::Modules::get_module_objects();
    my @cpconf_modules;
    my @cpconf_keys;
    foreach my $mod ( sort keys %{$mods} ) {
        if ( $mods->{$mod}->can('cpconftool_module') ) {
            push @cpconf_modules, $mods->{$mod}->cpconftool_module();
            push @cpconf_keys,    $mods->{$mod}->get_analysis_key();
        }
    }

    my $dump_databases_and_users_script = 'dump_databases_and_users';
    if ( $self->{'remote_info'}->{'type'} !~ m{^WHM} ) {
        my $locations_ref = Whostmgr::Transfers::Session::Remotes::get_locations_for_server_type( $self->{'remote_info'}->{'type'} );

        if ( $locations_ref->{'dump_databases_and_users_script'} ) {
            $dump_databases_and_users_script = $locations_ref->{'dump_databases_and_users_script'};
        }
    }

    $self->{'remote_exec_phases'} = [

        # Phase 0
        [
            {
                'key'                  => 'analyze_config_VERSION',
                'shell_safe_command'   => "$self->{'session_info'}->{'scriptdir'}/analyze_config",
                'shell_safe_arguments' => '--version',
                'updateable'           => 1
            },
            {
                'key'                  => 'unpkgacct_VERSION',
                'shell_safe_command'   => "$self->{'session_info'}->{'scriptdir'}/unpkgacct",
                'shell_safe_arguments' => '--version',
                'updateable'           => 1
            },
            {
                'key'                  => 'dump_databases_and_users_VERSION',
                'shell_safe_command'   => "$self->{'session_info'}->{'scriptdir'}/$dump_databases_and_users_script",
                'shell_safe_arguments' => '--version',
                'updateable'           => 1
            },

            {
                'key'                  => 'pkgacct-wrapper_VERSION',
                'shell_safe_command'   => "$self->{'session_info'}->{'scriptdir'}/pkgacct-wrapper",
                'shell_safe_arguments' => '--version',
                'updateable'           => 1
            },

            {
                'key'                  => 'xferpoint_VERSION',
                'shell_safe_command'   => "$self->{'session_info'}->{'scriptdir'}/xferpoint",
                'shell_safe_arguments' => '--version',
            },

            {
                'key'                  => '/usr/local/cpanel/version',
                'shell_safe_command'   => '/bin/cat',
                'shell_safe_arguments' => '/usr/local/cpanel/version',
            },

            {
                'key'                  => 'pkgacct_bin_VERSION',
                'shell_safe_command'   => $BIN_PKGACCT_PATH,
                'shell_safe_arguments' => '--get_version',
                'updateable'           => 0
            },

            {
                'key'                  => 'has_package_extensions',
                'shell_safe_command'   => "[ -d '/var/cpanel/packages/extensions' ] && echo 1",
                'shell_safe_arguments' => '',
            },

            {
                'key'                  => 'scripts_dir_ensure',
                'shell_safe_command'   => "[ ! -e '$self->{'session_info'}->{'scriptdir'}' ] && mkdir -p $self->{'session_info'}->{'scriptdir'}",
                'shell_safe_arguments' => '',
            },

            {
                'key'                  => 'Cpanel_dir_ensure',
                'shell_safe_command'   => "[ ! -e '$self->{'session_info'}->{'scriptdir'}/Cpanel' ] && mkdir -p $self->{'session_info'}->{'scriptdir'}/Cpanel",
                'shell_safe_arguments' => '',
            },

            {
                'key'                  => 'homedir',
                'shell_safe_command'   => '/bin/grep',
                'shell_safe_arguments' => 'HOMEDIR /etc/wwwacct.conf',
            },

            {
                'key'                  => 'roundcube_dbtype',
                'shell_safe_command'   => '/bin/grep',
                'shell_safe_arguments' => 'roundcube_db= -- /var/cpanel/cpanel.config',
            },

            {
                key                  => 'hostname',
                shell_safe_command   => '/bin/hostname',
                shell_safe_arguments => '--fqdn',
            },

            {
                key                  => 'is_cpanel_license_valid',
                shell_safe_command   => '/usr/local/cpanel/cpanel',
                shell_safe_arguments => '-F',
            },

            (
                $self->{'remote_info'}->{'type'} eq 'spectro'
                ? (
                    { 'key' => 'fix_scp',  'shell_safe_arguments' => '', 'shell_safe_command' => "[ ! -e /usr/bin/scp ] && ln -s /usr/local/ssh/bin/scp /usr/bin/scp" },
                    { 'key' => 'fix_scp1', 'shell_safe_arguments' => '', 'shell_safe_command' => "[ ! -e /usr/bin/scp1 ] && ln -s /usr/local/ssh/bin/scp1 /usr/bin/scp1" }
                  )
                : ()
            ),

            _cpconftool_modules( \@cpconf_modules, \@cpconf_keys )
        ],

        # Phase 1
        [
            {
                'key'                  => '/etc/userdomains',
                'shell_safe_command'   => '/bin/cat',
                'shell_safe_arguments' => '/etc/userdomains',
                'locale'               => $Whostmgr::Remote::State::UTF8_LOCALE
            },

            {
                'key'                  => '/etc/trueuserdomains',
                'shell_safe_command'   => '/bin/cat',
                'shell_safe_arguments' => '/etc/trueuserdomains',
                'locale'               => $Whostmgr::Remote::State::UTF8_LOCALE
            },

            {
                'key'                  => '/etc/trueuserowners',
                'shell_safe_command'   => '/bin/cat',
                'shell_safe_arguments' => '/etc/trueuserowners',
                'locale'               => $Whostmgr::Remote::State::UTF8_LOCALE
            },

            {
                'key'                  => '/etc/domainips',
                'shell_safe_command'   => '/bin/cat',
                'shell_safe_arguments' => '/etc/domainips',
                'locale'               => $Whostmgr::Remote::State::UTF8_LOCALE
            },

            {
                'key'                  => 'packages',
                'shell_safe_command'   => '/bin/ls',
                'shell_safe_arguments' => '-C1 -A /var/cpanel/packages',
                'locale'               => $Whostmgr::Remote::State::UTF8_LOCALE
            },

            {
                'key'                  => 'featurelists',
                'shell_safe_command'   => '/bin/grep',
                'shell_safe_arguments' => '-aH FEATURELIST -- /var/cpanel/packages/*',
                'locale'               => $Whostmgr::Remote::State::UTF8_LOCALE
            },

            {
                'key'                  => 'analyze_config',
                'shell_safe_command'   => "$self->{'session_info'}->{'scriptdir'}/analyze_config",
                'shell_safe_arguments' => '',
            },

            {
                'key'                  => 'dumpquotas',
                'shell_safe_command'   => "$self->{'session_info'}->{'scriptdir'}/dumpquotas",
                'shell_safe_arguments' => '',
            },

            {
                'key'                  => 'dumpinodes',
                'shell_safe_command'   => "$self->{'session_info'}->{'scriptdir'}/dumpinodes",
                'shell_safe_arguments' => '',
            },

            {
                'key'                  => 'user_worker_nodes',
                'shell_safe_command'   => '/usr/local/cpanel/bin/whmapi1',
                'shell_safe_arguments' => 'list_user_child_nodes --output=json',
                'locale'               => $Whostmgr::Remote::State::UTF8_LOCALE
            },

            {
                'key'                  => 'linked_nodes',
                'shell_safe_command'   => '/usr/local/cpanel/bin/whmapi1',
                'shell_safe_arguments' => 'list_linked_server_nodes --output=json',
                'locale'               => $Whostmgr::Remote::State::UTF8_LOCALE
            },

            {
                'key'                  => 'linked_nodes',
                'shell_safe_command'   => '/usr/local/cpanel/bin/whmapi1',
                'shell_safe_arguments' => 'list_linked_server_nodes --output=json',
                'locale'               => $Whostmgr::Remote::State::UTF8_LOCALE
            },
            {
                'key'                  => 'reseller_list',
                'shell_safe_command'   => '/usr/local/cpanel/bin/whmapi1',
                'shell_safe_arguments' => 'listresellers --output=json',
                'locale'               => $Whostmgr::Remote::State::UTF8_LOCALE
            }
        ]
    ];

    # TODO: add a flag to only turn this on when needed so we don't
    # do on every account transfer if it gets to the point these
    # commands are expensive
    foreach my $mod ( sort keys %{$mods} ) {
        my $additions = $mods->{$mod}->get_analysis_commands();    # FIXME: error checking
        foreach my $phase ( 0 .. 1 ) {
            push @{ $self->{'remote_exec_phases'}->[$phase] }, @{ $additions->[$phase] };
        }
    }

    return ( 1, 'ok' );
}

sub _update_outdated_scripts_and_add_to_this_phase {
    my ($self) = @_;

    foreach my $execref ( @{ $self->{'remote_exec_phases'}->[0] } ) {
        next if !$execref->{'updateable'};

        my $key = $execref->{'key'};
        my $cmd = ( split( m{/}, $execref->{'shell_safe_command'} ) )[-1];

        $self->{'local_versions'}->{$key} = Cpanel::SafeRun::Simple::saferun( "$Whostmgr::Remote::LOCAL_PKGACCT_DIR/$cmd", "--version" );

        if ( !$self->{'remote_exec_results'}->{$key} || $self->{'remote_exec_results'}->{$key} !~ m{VERSION} || Cpanel::Version::Compare::compare( $self->_version_string( $self->{'remote_exec_results'}->{$key} ), '<', $self->_version_string( $self->{'local_versions'}->{$key} ) ) ) {
            my ( $ok, $msg ) = $self->{'remoteobj'}->remotescriptcopy(
                'srcfile' => $cmd,
            );

            if ( !$ok ) {
                return ( 0, _locale()->maketext( "The system failed to update the file “[_1]” on the remote server because of an error: [_2]", $key, $msg ) );
            }

            $self->_queue_remote_exec($execref);
        }
    }

    return ( 1, 'ok' );
}

sub _queue_remote_exec {
    my ( $self, $execref ) = @_;

    return unshift @{ $self->{'remote_exec_phases'}->[ $self->{'current_phase'} ] }, $execref;
}

=head2 _cpconftool_modules

This subroutine collapses cpconftool calls into a single exec call (_cpconf_run),
which is then extracted in _extract_cpconftool after the _exec_phase

=over 2

=item Input

=over 3

=item C<ARRAYREF>

Array ref of cpconf modules

=item C<ARRAYREF>

Array ref of cpconf keys

=back

=item Output

=over 3

=item C<ARRAY>

returns status and status message
example (1, 'ok');

=back

=back

=cut

sub _cpconftool_modules ( $cpconf_modules_ar, $cpconf_keys_ar ) {    ## no critic qw(Subroutines::ProhibitManyArgs) adding prohibit due to bug with signatures

    if ( @$cpconf_modules_ar && @$cpconf_keys_ar ) {

        die "The module to key ratio must be equal length." if scalar(@$cpconf_modules_ar) != scalar(@$cpconf_keys_ar);

        return {
            'key'                  => $CPCONF_RUN_KEY,
            'shell_safe_arguments' => '--query-module-info --modules=' . join( ',', @$cpconf_modules_ar ),
            'shell_safe_command'   => "/usr/local/cpanel/bin/cpconftool",
            'modules'              => $cpconf_modules_ar,
            'keys'                 => $cpconf_keys_ar,
        };
    }

    return;
}

=head2 _extract_cpconftool

After _exec_phase this subroutine expands the _cpconf_run results into the
individual modules that it was previously setup to do

=over 2

=item Output

=over 3

=item C<ARRAY>

returns status and status message
example (1, 'ok');

=back

=back

=cut

sub _extract_cpconftool {
    my ($self) = @_;

    # TODO: can we have the other  modules consume this as-is and skip this?
    #
    #only bother with this if a _cplint run exists
    if ( $self->{'remote_exec_results'}{$CPCONF_RUN_KEY} ) {

        # in the $self->{'remote_exec_results'} expand the results of each module
        require Cpanel::YAML::Syck;

        my $phase_zero_modules = $self->{'remote_exec_phases'}->[0];

        my $result = YAML::Syck::Load( $self->{'remote_exec_results'}{$CPCONF_RUN_KEY} );

        if ( !$result || !ref $result || ref $result ne 'HASH' ) {

            # Handle: The source server has a cPanel version older than 55. Therefore, transferring system configurations is not available.
            warn "The system failed to fetch information about the remote server Service Configurations because the data returned could not be parsed: " . $self->{'remote_exec_results'}{$CPCONF_RUN_KEY};
            return ( 1, 'skipped' );
        }

        # find the _cpconf_run
        foreach my $mod_exec ( @{$phase_zero_modules} ) {
            if ( $mod_exec->{'key'} eq $CPCONF_RUN_KEY ) {

                my @modules = @{ $mod_exec->{'modules'} };
                my @keys    = @{ $mod_exec->{'keys'} };

                # for each module reinstate only it's part of the _cpconf_run to the results
                for my $i ( 0 .. $#keys ) {
                    my $key    = $keys[$i];
                    my $module = $modules[$i];

                    # we have to recollapse this back down as the _parse_analysis_commands parse this as lines, not YAML
                    # TODO: Make each module _parse_analysis_commands handle the parsed object instead of the string (or both?)
                    $self->{'remote_exec_results'}{$key} = YAML::Syck::Dump( { "$module" => $result->{$module} } );
                }

                # remove the superflous key
                delete $self->{'remote_exec_results'}{$CPCONF_RUN_KEY};
                last;
            }
        }

    }

    return ( 1, 'ok' );
}

=head2 _check_supports_live_transfers

After _exec_phase this subroutine verifies whether the source supports hot transfers

=over 2

=item Output

=over 3

=item C<ARRAY>

returns status and status message
example (1, 'ok');

=back

=back

=cut

sub _check_supports_live_transfers {
    my ($self) = @_;

    my $remote_version = $self->{'remote_exec_results'}{'/usr/local/cpanel/version'};

    require Cpanel::Version::Support;
    my $source_is_supported_version = Cpanel::Version::Support::version_supports_feature( $remote_version, 'live_transfers' );

    $self->{'remote_exec_results'}{'supports_live_transfers'} = $source_is_supported_version ? "1" : "0";

    return ( 1, 'ok' );
}

sub _exec_phase {
    my ($self) = @_;

    my @execs = map { !$_->{'dynamic'} ? $_ : $_->{'dynamic'}->($self) } @{ $self->{'remote_exec_phases'}->[ $self->{'current_phase'} ] };

    my ( $phase_exec_status, $phase_resultref ) = $self->{'remoteobj'}->multi_exec( \@execs );

    return ( 0, _locale()->maketext( "The system failed to fetch information about the remote server in preflight phase [numf,_1], and returned the error: [_2]", scalar $self->{'current_phase'}, $phase_resultref ) ) if !$phase_exec_status;

    @{ $self->{'remote_exec_results'} }{ keys %{$phase_resultref} } = @{$phase_resultref}{ keys %{$phase_resultref} };

    $self->{'current_phase'}++;

    return ( 1, 'ok' );
}

sub _locale {
    return ( $locale ||= Cpanel::Locale->get_handle() );
}

1;
