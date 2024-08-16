package Whostmgr::Transfers::Session::Items::AccountRemoteRoot;

# cpanel - Whostmgr/Transfers/Session/Items/AccountRemoteRoot.pm
#                                                  Copyright 2022 cPanel, L.L.C.
#                                                           All rights reserved.
# copyright@cpanel.net                                         http://cpanel.net
# This code is subject to the cPanel license. Unauthorized copying is prohibited

use cPstrict;

our $VERSION = '1.7';

use parent 'Whostmgr::Transfers::Session::Items::AccountRemoteBase';

use Cpanel::AcctUtils::Domain       ();
use Cpanel::Config::HasCpUserFile   ();
use Cpanel::Config::LoadCpUserFile  ();
use Cpanel::Config::LoadWwwAcctConf ();
use Cpanel::DIp::IsDedicated        ();
use Cpanel::Gzip::Detect            ();
use Cpanel::DiskCheck               ();
use Cpanel::Exception               ();
use Cpanel::JSON                    ();
use Cpanel::FileUtils::Path         ();
use Cpanel::Filesys::FindParse      ();
use Cpanel::Filesys::Home           ();
use Cpanel::Filesys::Info           ();
use Cpanel::Email::RoundCube        ();
use Cpanel::MD5                     ();
use Cpanel::Mysql::Constants        ();
use Cpanel::NAT                     ();
use Cpanel::Version::Compare        ();
use Cpanel::PwCache                 ();
use Cpanel::Debug                   ();
use Cpanel::Signals                 ();
use Cpanel::DnsUtils::Fetch         ();
use Cpanel::ZoneFile                ();

use Cpanel::LogTailer::Client::LiveTailLog ();
use Cpanel::HTTP::Tiny::FastSSLVerify      ();

use Cpanel::PublicSuffix ();    # PPI USE OK -- laod before cPanel::PublicAPI so we provide our PublicSuffix module to HTTP::CookieJar

use cPanel::PublicAPI ();

use Whostmgr::Backup::Pkgacct::Parser  ();
use Whostmgr::Remote                   ();
use Whostmgr::Transfers::Session::Item ();
use Whostmgr::Whm5                     ();
use Whostmgr::XferClient               ();

use Cpanel::MysqlUtils::Version ();

use Cwd ();

use Try::Tiny;

use constant {
    _IS_USER_USABLE          => 0,
    _PRIVILEGE_LEVEL         => 'root',
    _LIVE_TRANSFER_FLAG_NAME => 'live_transfer',

    # _IS_ROOT_USABLE is inherited.
};

our $PERCENT_FILE_TRANSFER_PHASE        = 45;
our $PERCENT_PKGACCT_PHASE              = 50;
our $MAX_FILE_TRANSFER_ATTEMPTS         = 3;
our $MAX_CONCURRENT_LOG_STREAM_FAILURES = 5;
our $MAX_TOTAL_LOG_STREAM_FAILURES      = 50;

# cf. Whostmgr::Transfers::Session::Item’s prevalidate_or_die().
sub _prevalidate_live_transfer ( $class, $session_obj, $input_hr ) {

    return if !$input_hr->{ _LIVE_TRANSFER_FLAG_NAME() };

    my $remoteinfo_hr = $session_obj->remoteinfo();

    my $cpversion = $remoteinfo_hr->{'cpversion'} or do {
        my $hostname = $remoteinfo_hr->{'sshhost'};
        my $type     = $remoteinfo_hr->{'type'};

        die Cpanel::Exception::create( 'InvalidParameter', 'The “[_1]” option requires a source server that runs [asis,cPanel amp() WHM]. “[_2]” runs “[_3]”.', [ _LIVE_TRANSFER_FLAG_NAME, $hostname, $type ] );
    };

    require Cpanel::Version::Support;

    if ( !Cpanel::Version::Support::version_supports_feature( $cpversion, 'live_transfers' ) ) {
        my $hostname = $remoteinfo_hr->{'sshhost'};
        my $min      = Cpanel::Version::Support::get_minimum_version('live_transfers');

        die Cpanel::Exception::create( 'InvalidParameter', 'The “[_1]” option requires a source server that runs [asis,cPanel amp() WHM] version “[_2]” or greater. “[_3]” runs version “[_4]”.', [ _LIVE_TRANSFER_FLAG_NAME, $min, $hostname, $cpversion ] );
    }

    return;
}

sub _run_remote_xferpoint {
    my ( $self, @other_domains ) = @_;

    my $creator = 'root';
    if ( Cpanel::Config::HasCpUserFile::has_cpuser_file( $self->{'local_user'} ) ) {
        my $cpuser_ref = Cpanel::Config::LoadCpUserFile::loadcpuserfile( $self->{'local_user'} );
        if ( $cpuser_ref->{'OWNER'} ) { $creator = $cpuser_ref->{'OWNER'}; }
    }
    my $primary_domain = Cpanel::AcctUtils::Domain::getdomain( $self->{'local_user'} );

    # We need the source account to indicate the same authoritative
    # nameservers as our local account. We only do this for the primary
    # zone.
    #
    my $zone_text_hr = Cpanel::DnsUtils::Fetch::fetch_zones(
        zones => [$primary_domain],
    );

    require Cpanel::DomainIp;
    my $domainip          = Cpanel::DomainIp::getdomainip($primary_domain);
    my $newip             = Cpanel::NAT::get_public_ip($domainip);
    my $shared_ip_address = Cpanel::NAT::get_public_ip( Cpanel::Config::LoadWwwAcctConf::loadwwwacctconf()->{'ADDR'} );
    my $ftpip             = Cpanel::DIp::IsDedicated::isdedicatedip($domainip) ? $newip : $shared_ip_address;

    $self->create_remote_object() if !$self->{'remoteobj'};

    $self->{'output_obj'}->set_source( { 'host' => $self->{'remote_info'}->{'sshhost'} } );

    foreach my $domain ( $primary_domain, @other_domains ) {
        my @CMD = (
            "$self->{'session_info'}->{'scriptdir'}/xferpoint",
            $self->{'detected_remote_user'},
            '-1',       #old ip is auto detected
            $newip,
            $domain,    # the domain to point
        );

        my $xferpoint_ver = $self->{'remote_info'}->{'xferpoint_version'};

        if ( Cpanel::Version::Compare::compare( $xferpoint_ver, '>=', '0.5' ) ) {
            push @CMD, $ftpip;

            if ( Cpanel::Version::Compare::compare( $xferpoint_ver, '>=', '0.6' ) ) {
                my $flagsnum = 0;
                $flagsnum |= 1 if $self->{'input'}->{'live_transfer'};

                push @CMD, $flagsnum;
            }
        }

        if ( my $zone_text = $zone_text_hr->{$domain} ) {
            my @nameservers = _extract_nameservers( $domain, $zone_text );
            push @CMD, @nameservers;
        }

        my ( $status, $err ) = $self->{'remoteobj'}->remoteexec(
            'txt' => $self->_locale()->maketext( 'Pointing “[_1]”’s DNS records to the new server …', $domain ),
            'cmd' => \@CMD,
        );

        warn "$domain: $err" if !$status;
    }

    my ( $status, $err ) = $self->{'remoteobj'}->remoteexec(
        'txt' => $self->_locale()->maketext('Updating mail routing on the source server …'),
        'cmd' => [
            "$self->{'session_info'}->{'scriptdir'}/xfertool",
            '--setupmaildest',
            $self->{'detected_remote_user'},
            'secondary',
        ],
    );

    warn "Update mail routing failed: $err" if !$status;

    ( $status, $err ) = $self->{'remoteobj'}->remoteexec(
        'txt' => $self->_locale()->maketext('Disabling logins on the source server …'),
        'cmd' => [
            "$self->{'session_info'}->{'scriptdir'}/xfertool",
            '--disallowlogins',
            $self->{'detected_remote_user'},
        ],
    );

    warn "Disallow source-server logins failed: $err" if !$status;

    $self->{'output_obj'}->set_source();

    return 1;
}

sub _extract_nameservers ( $origin, $zone_text ) {
    my $zf = Cpanel::ZoneFile->new(
        domain => $origin,
        text   => $zone_text,
    );

    my $results_ar = $zf->find_records(
        type => 'NS',
        name => "$origin.",
    );

    return map { $_->{'nsdname'} =~ s<\.\z><>r } @$results_ar;
}

sub transfer {
    my ($self) = @_;

    return $self->exec_path(
        [
            qw(_transfer_init
              _validate_usernames
              _find_location_with_most_free_space
              create_remote_object
              _remote_pkgacct_decision
              _check_transfer_disk_space
              _locate_remote_files
              _verify_each_remote_cpmove_has_md5sum
              _chown_remote_files_if_not_connecting_as_root
              _transfer_cpmove_files
              _assemble_cpmove_file
              _save_results_to_session
              _remove_remote_cpmove_files
            )
        ],
        [qw(tear_down_transfer)],
        $Whostmgr::Transfers::Session::Item::ABORTABLE,
    );
}

sub _custom_account_restore_args ($self) {
    return (

        # NB: remote_host and remote_cpversion are provided
        # via AccountBase.
        remote_api_token_username => $self->{'authinfo'}{'whmuser'},
        remote_api_token          => $self->{'authinfo'}{'accesshash_pass'},

        $self->{'remote_info'}{'mysql_streaming_method'}
        ? (
            'mysql_stream' => {
                method             => $self->{'remote_info'}{'mysql_streaming_method'},
                host               => $self->{'remote_info'}{'sshhost'},
                api_token_username => $self->{'authinfo'}{'whmuser'},
                api_token          => $self->{'authinfo'}{'accesshash_pass'},
                application        => 'whm',
            },
          )
        : ()
    );
}

sub _transfer_init {
    my ($self) = @_;

    $self->session_obj_init();

    $self->{'local_user'}  = $self->{'input'}->{'localuser'};
    $self->{'remote_user'} = $self->item();                     # AKA $self->{'input'}->{'user'};

    $self->{'compressionsetting'} = $self->{'options'}->{'uncompressed'} ? 'nocompress' : 'compressed';
    $self->{'skippkghomedir'}     = $self->{'input'}->{'skiphomedir'} || $self->{'can_stream'};

    $self->{'orig_cwd'} = Cwd::fastcwd();

    return $self->validate_input( [qw(session_obj options authinfo remote_info session_info output_obj local_user remote_user compressionsetting can_rsync can_stream skippkghomedir orig_cwd)] );
}

sub _verify_each_remote_cpmove_has_md5sum {
    my ($self) = @_;

    $self->set_percentage($PERCENT_PKGACCT_PHASE);

    foreach my $fileref ( @{ $self->{'remote_cpmove_files'} } ) {
        if ( !$fileref->{'md5'} ) {
            print $self->_locale()->maketext( 'The MD5 for the remote files “[_1]” is missing.', $fileref->{'path'} ) . "\n";
            return ( 0, $self->_locale()->maketext("The remote server didn’t report a correct [asis,MD5] checksum of the archive. Ensure that you selected the correct type of remote server.") );
        }
    }
    return ( 1, 'OK' );
}

# test above

sub _verify_package_md5 {
    my ( $self, $file, $remotemd5sum ) = @_;

    print $self->_locale()->maketext('Verifying [asis,cpmove] file checksum …');

    my $localmd5sum = Cpanel::MD5::getmd5sum($file);
    if ( $localmd5sum eq $remotemd5sum ) {
        print $self->_locale()->maketext( "Checksum Matches (Actual remote username is “[_1]”).", $self->{'detected_remote_user'} ) . "\n";
        return 1;
    }
    else {
        print $self->_locale()->maketext("Checksum Failed: The file transfer was not successful!") . "\n";
        print $self->_locale()->maketext( "Expected Checksum: [_1]", $remotemd5sum ) . "\n";
        print $self->_locale()->maketext( "Actual Checksum: [_1]",   $localmd5sum ) . "\n";
    }
    return 0;
}

sub _remote_pkgacct_decision {
    my ( $self, %OPTS ) = @_;

    print $self->_locale()->maketext( "Remote server type: “[_1]”.", $self->{'remote_info'}->{'type'} ) . "\n";

    # We'll attempt to use an API token, which won't work over an unencrypted
    # connection.
    if ( Cpanel::Version::Compare::compare( $self->{'remote_info'}{'cpversion'}, '>=', '11.53' ) && $self->{options}{ssl} ) {
        my ($status) = $self->_remote_background_pkgacct(%OPTS);
        return ($status) if $status;
        if ( Cpanel::Signals::has_signal('TERM') ) {
            return ( 0, 'Aborted.' );
        }
        elsif ( Cpanel::Signals::has_signal('USR1') ) {
            return ( 0, "Skipped." );
        }

        # If the above failed we've already outputted a localized error message to the output_obj, no need to repeat ourselves with unlocalized strings
        $self->{output_obj}->warn( _format_message_for_output_obj( $self->_locale()->maketext('The system failed to package the account on the remote system via [output,abbr,API,Application Programming Interface] connection. It will now attempt to package the account via [output,abbr,SSH,Secure Shell].') ) );

        return $self->_remote_pkgacct(%OPTS);
    }
    else {
        return $self->_remote_pkgacct(%OPTS);
    }
}

sub _remote_background_pkgacct {
    my ($self) = @_;

    $self->_disconnect_remote_object();

    print $self->_locale()->maketext("Initiating a remote [output,abbr,API,Application Programming Interface] connection in order to package the account in a background process …") . "\n";

    $self->set_percentage(5);

    $self->{output_obj}->set_source( { host => $self->{remote_info}{sshhost} } );

    my $session_data;

    my $err;
    try {
        $session_data = $self->_call_remote_background_pkgacct_with_internal_data();
    }
    catch {
        $err = $_;
    };

    if ($err) {
        $self->{output_obj}->error( _format_message_for_output_obj( $self->_locale()->maketext( 'The system failed to initiate a remote background package account due to an error: [_1]', Cpanel::Exception::get_string($err) ) ) );

        # Will output an error to the output_obj if it fails
        $self->_reconnect_remote_object();

        return ( 0, 'Unable to call remote pkgacct on source server.' );
    }

    my ( $session_id, $log_files ) = $self->_parse_pkgacct_api_response($session_data);

    my $parser        = Whostmgr::Backup::Pkgacct::Parser->new();
    my $log_parser_cr = sub {

        # Avoid Cpanel::Signals::signal_needs_to_be_handled  and use
        # Cpanel::Signals::has_signal as it does not clear the state.
        #
        # Since we are not handling the signal here we only
        # need to break out of the loop as the signal will
        # ultimately be handled in the transfer system at
        # a higher level.
        if ( Cpanel::Signals::has_signal('TERM') ) {
            die Cpanel::Exception::create( 'RemoteAbort', 'Aborted.' );
        }
        elsif ( Cpanel::Signals::has_signal('USR1') ) {
            die Cpanel::Exception::create( 'RemoteSkip', 'Skipped.' );
        }
        $self->_pkgacct_callback( $_[0] );
        $parser->process_line( $_[0] );

        return;
    };

    my $message_processor_cr = sub {
        my ( $file_name, $message_bytes, $json_message ) = @_;

        $self->_process_json_message( $log_parser_cr, $file_name, $json_message );

        return;
    };

    # Default timeout is 60 second.. that should be enough since we send keep alives during long running processes.
    my $http = Cpanel::HTTP::Tiny::FastSSLVerify->new( verify_SSL => 0 );
    my $stream_status;

    try {
        my $log_tailer_client = Cpanel::LogTailer::Client::LiveTailLog->new(
            session_id                     => $session_id,
            system_id                      => 'pkgacct',
            log_file_data                  => $log_files,
            max_concurrent_stream_failures => $MAX_CONCURRENT_LOG_STREAM_FAILURES,
            max_total_stream_failures      => $MAX_TOTAL_LOG_STREAM_FAILURES,
            use_ssl                        => $self->{options}{ssl},
            host                           => $self->{remote_info}{sshhost},
            whmuser                        => $self->{authinfo}{whmuser},
            accesshash_pass                => $self->{authinfo}{accesshash_pass},
            output_obj                     => $self->{output_obj},
            http_client                    => $http,
        );

        $stream_status = $log_tailer_client->read_log_stream(
            log_parser_cr        => $log_parser_cr,
            message_processor_cr => $message_processor_cr,
        );
    }
    catch {
        $err = $_;
    };

    if ($err) {
        $self->{output_obj}->error( _format_message_for_output_obj( $self->_locale()->maketext( 'The system failed to stream log data from the remote server due to an error: [_1]', Cpanel::Exception::get_string($err) ) ) );

        # Will output an error to the output_obj if it fails
        $self->_reconnect_remote_object();

        return ( 0, 'Unable to stream pkgacct log data from source server.' );
    }

    $parser->finish();

    # Will output an error via the output_obj
    my ( $remote_object_creation_status, $status_message ) = $self->_reconnect_remote_object();

    return ( 0, $status_message ) if !$remote_object_creation_status;

    if ( Cpanel::Signals::has_signal('TERM') ) {
        return ( 0, 'Aborted.' );
    }
    elsif ( Cpanel::Signals::has_signal('USR1') ) {
        return ( 0, "Skipped." );
    }

    $self->_populate_remote_pkgacct_info(
        $parser->remote_username(),
        $parser->remote_archive_is_split(),
        $parser->remote_file_paths(),
        $parser->remote_file_md5sums(),
        $parser->remote_file_sizes()
    );

    if ( !$stream_status ) {
        $self->{output_obj}->error( _format_message_for_output_obj( $self->_locale()->maketext('The system failed to determine the status of the remote package account.') ) );

        return ( 0, 'Unable to determine status of remote background pkgacct' );
    }

    return ( 1, 'Remote background pkgacct completed' );
}

sub _add_warning {
    my ( $self, $warning ) = @_;

    my $warnings_ar = $self->warnings() || [];
    push @$warnings_ar, $warning;

    $self->set_warnings($warnings_ar);

    return;
}

sub _process_json_message {
    my ( $self, $log_parser_cr, $file_name, $json_message ) = @_;

    # Just trap the error, we'll output the message if it isn't JSON below
    my $message_ref;
    try {
        $message_ref = Cpanel::JSON::Load($json_message);
    };

    if ($message_ref) {
        my $formatted_msg = _format_message_for_output_obj($message_ref);

        $log_parser_cr->( $message_ref->{contents} );

        if ( $file_name =~ /error_log/ ) {
            $self->_add_warning($formatted_msg);

            if ( $message_ref->{type} eq 'error' || $message_ref->{type} eq 'fail' || $message_ref->{type} eq 'failed' ) {
                $self->{output_obj}->error($formatted_msg);
            }
            else {
                $self->{output_obj}->warn($formatted_msg);
            }
        }
        else {
            if ( $message_ref->{type} eq 'error' || $message_ref->{type} eq 'warn' ) {
                $self->_add_warning($formatted_msg);
            }

            $self->{output_obj}->message(
                $message_ref->{type},
                $formatted_msg,
                $message_ref->{source},
                $message_ref->{partial}
            );
        }
    }
    else {
        my $formatted_msg = _format_message_for_output_obj($json_message);

        $log_parser_cr->($json_message);

        if ( $file_name =~ /error_log/ ) {
            $self->_add_warning($formatted_msg);
            $self->{output_obj}->error($formatted_msg);
        }
        else {
            $self->{output_obj}->out($formatted_msg);
        }
    }

    return;
}

sub _format_message_for_output_obj {
    my ($message) = @_;

    # This { msg => [$message] } format is the only way it'll output in the browser
    if ( ref $message ) {
        return { msg => [ ( $message->{timestamp} ? "[$message->{timestamp}] $message->{contents}" : $message->{contents} ) ] };
    }
    else {
        return { msg => [$message] };
    }
}

sub _disconnect_remote_object {
    my ($self) = @_;

    delete $self->{remoteobj};

    return;
}

sub _reconnect_remote_object {
    my ($self) = @_;

    my ( $status, $message ) = $self->create_remote_object();
    return ( $status, $message ) if $status;

    $self->{output_obj}->error( _format_message_for_output_obj( $self->_locale()->maketext( 'The system failed to recreate the connection to the source server due to an error: [_1]', $message ) ) );

    return ( 0, $message );
}

sub _run_whm_api {
    my ( $self, $func_name, $args_hr ) = @_;

    my $cpanel_api = $self->{'_cpanel_api'} ||= cPanel::PublicAPI->new(
        user            => 'root',
        accesshash      => $self->{authinfo}{accesshash_pass},
        usessl          => $self->{options}{ssl},
        ssl_verify_mode => 0,
        host            => $self->{remote_info}{sshhost}
    );

    return $cpanel_api->whm_api( $func_name, $args_hr );
}

sub _create_common_pkgacct_args ($self) {
    my @args = (
        'tarroot' => ( $self->{'authinfo'}->{'user'} eq 'root' ? q{''} : '~' . $self->{'authinfo'}->{'user'} ),

        'servtype' => $self->{'remote_info'}->{'type'},
        'ssh_host' => $self->{'remote_info'}->{'sshhost'},

        'compressionsetting' => $self->{'compressionsetting'},
        'use_backups'        => $self->{'options'}->{'backups'},
        'low_priority'       => $self->{'options'}->{'low_priority'},
        'can_stream'         => $self->{'can_stream'},
        'can_rsync'          => $self->{'can_rsync'},

        'mysqlver' => Cpanel::MysqlUtils::Version::get_mysql_version_with_fallback_to_default(),

        'skiphomedir' => $self->{'skippkghomedir'},
        'skipacctdb'  => $self->{'input'}->{'skipacctdb'},
        'skipbwdata'  => $self->{'input'}->{'skipbwdata'},

        'split'     => 1,
        'roundcube' => _get_roundcube_version_info(),
    );

    if ( $self->_remote_has_pkgacct_dbbackup_mysql_option() ) {
        push @args, (
            'dbbackup_mysql' => $self->{'remote_info'}{'mysql_streaming_method'} ? 'schema' : 'all',
        );
    }

    return @args;
}

sub _call_remote_background_pkgacct_with_internal_data {
    my ($self) = @_;

    # These are options that are passed into Whostmgr::Whm5::get_pkgcmd
    # and converted to pkgacct arguments.
    my $response = $self->_run_whm_api(
        'start_background_pkgacct',
        {
            'api.version' => 1,
            'user'        => $self->{'remote_user'},

            $self->_create_common_pkgacct_args(),

            # Whostmgr::Whm5::get_pkgcmd will auto-set skiphomedir if can_stream is set as well as both of these, but we might as well not send the root password - just in case.
            'whmuser' => length $self->{'authinfo'}->{'whmuser'} ? 1 : 0,
            'whmpass' => length $self->{'authinfo'}->{'whmpass'} ? 1 : 0,
        }
    );

    # Already localized and being caught in the calling function
    die $response->{metadata}{reason} if !$response->{metadata}{result};

    return $response->{data};
}

sub _parse_pkgacct_api_response {
    my ( $self, $response ) = @_;

    my $session_id = delete $response->{session_id};

    my $count     = 0;
    my $log_files = {};
    for my $file_key ( keys %$response ) {
        $log_files->{ $response->{$file_key} } = {
            file_number   => $count++,
            file_position => 0,
        };
    }

    return ( $session_id, $log_files );
}

sub _get_roundcube_version_info {

    # case CPANEL-18442: uninstalled roundcube should not cause a transfer to fail
    my $roundcube_version;
    try {
        $roundcube_version = Cpanel::Email::RoundCube::get_cached_version();
    }
    catch {
        $roundcube_version = 0;
        Cpanel::Debug::log_warn( Cpanel::Exception::get_string($_) );
    };

    return $roundcube_version;
}

sub _remote_pkgacct {
    my ($self) = @_;

    print $self->_locale()->maketext("Initiating process to package the account over [output,abbr,SSH,Secure Shell] connection …") . "\n";

    my $pkgcmd = Whostmgr::Whm5::get_pkgcmd(
        $self->_get_pkgacct_filename(),
        $self->{'remote_user'},
        {
            $self->_create_common_pkgacct_args(),

            'whmuser'   => $self->{'authinfo'}->{'whmuser'},
            'whmpass'   => $self->{'authinfo'}->{'whmpass'},
            'hr_sphera' => {
                'sphera_user'     => $self->{'authinfo'}->{'sphera_user'},
                'sphera_host'     => $self->{'authinfo'}->{'sphera_host'},
                'sphera_password' => $self->{'authinfo'}->{'sphera_password'},
            },
        }
    );

    # CPANEL-30091: Allow users to control the --no-reseller/--reseller pkgacct flag
    # via the Reseller Privileges checkbox in the account transfer options.
    if ( $self->{'remote_info'}{'type'} eq 'plesk' ) {
        $pkgcmd .= $self->{'input'}{'skipres'} ? ' --no-reseller' : ' --reseller';
    }

    $self->set_percentage(5);

    $self->{'output_obj'}->set_source( { 'host' => $self->{'remote_info'}->{'sshhost'} } );
    my ( $status, $message, $rawout, $detected_remote_user, $issplit, $ar_filelocs, $ar_md5s, $ar_sizes ) = (
        $self->{'remoteobj'}->remoteexec(
            'txt'      => $self->_locale()->maketext( "Packaging the account with the command: [_1]", $pkgcmd ),
            'cmd'      => $pkgcmd,
            'callback' => sub {
                my ($output) = @_;
                return $self->_pkgacct_callback($output);
            }
        )
    )[ $Whostmgr::Remote::STATUS, $Whostmgr::Remote::MESSAGE, $Whostmgr::Remote::RAWOUT, $Whostmgr::Remote::REMOTE_USERNAME, $Whostmgr::Remote::REMOTE_ARCHIVE_IS_SPLIT, $Whostmgr::Remote::REMOTE_FILE_PATHS, $Whostmgr::Remote::REMOTE_FILE_MD5SUMS, $Whostmgr::Remote::REMOTE_FILE_SIZES ];
    $self->{'output_obj'}->set_source();

    if ($status) {
        $self->_populate_remote_pkgacct_info(
            $detected_remote_user,
            $issplit,
            $ar_filelocs,
            $ar_md5s,
            $ar_sizes
        );
        return ( 1, 'OK' );
    }
    elsif ($message) {
        return ( 0, $message );
    }
    else {
        return ( 0, $self->_locale()->maketext( "The system is unable to package the account due to remote command “[_1]” failure.", $pkgcmd ) );
    }

}

sub _populate_remote_pkgacct_info {
    my ( $self, $detected_remote_user, $issplit, $ar_filelocs, $ar_md5s, $ar_sizes ) = @_;

    my @sizes      = grep { $_ } map { $_->{'size'} } @{$ar_sizes};
    my @home_sizes = grep { $_ } map { $_->{'homesize'} } @{$ar_sizes};
    my @home_files = grep { $_ } map { $_->{'homefiles'} } @{$ar_sizes};
    my @files      = grep { $_ } map { $_->{'files'} } @{$ar_sizes};

    # INODES
    if ( !@home_files && !@files && $self->{'input'}->{'files'} ) {
        push @{$ar_sizes}, { 'files' => $self->{'input'}->{'files'} };
    }

    # BLOCKS
    if ( !@home_sizes && $self->{'input'}->{'size'} ) {
        my $non_home_size = 0;
        foreach (@sizes) { $non_home_size += $_; }
        my $home_size = ( $self->{'input'}->{'size'} - $non_home_size );
        if ( $home_size > 0 ) {
            push @{$ar_sizes}, { 'homesize' => $home_size };
            @home_sizes = ($home_size);
        }
        else {
            push @sizes, { 'size' => abs($home_size) };
        }
    }

    my @cpmove_files;

    for my $file_count ( 0 .. $#$ar_filelocs ) {
        push @cpmove_files,
          {
            'path' => $ar_filelocs->[$file_count],
            'size' => $sizes[$file_count],
            'md5'  => $ar_md5s->[$file_count],
          };
    }
    $self->{'all_remote_sizes'}     = $ar_sizes;
    $self->{'home_size'}            = $home_sizes[0];
    $self->{'remote_cpmove_files'}  = [ sort { $a->{'path'} cmp $b->{'path'} } @cpmove_files ];
    $self->{'issplit'}              = $issplit;
    $self->{'detected_remote_user'} = $detected_remote_user || $self->{'remote_user'};

    return;
}

# All the pkgacct scripts should be sending this.
# This is a legacy hold over until we get rid of the
# older scripts that do not send the file location.
sub _guess_cpmove_location {
    my ($self) = @_;

    my $guess;

    print $self->_locale()->maketext("WARNING: The remote server failed to send the location of the transfer archive.") . "\n";
    print $self->_locale()->maketext("WARNING: Attempting to guess the location of the remote transfer archive.") . "\n";

    my $guessuser = $self->{'detected_remote_user'} || $self->{'remote_user'} || $self->{'local_user'};

    if ( $self->{'authinfo'}->{'user'} && $self->{'authinfo'}->{'user'} ne 'root' ) {
        $guess = "/home/$self->{'authinfo'}->{'user'}/cpmove-$guessuser.tar.gz";
    }
    else {
        $guess = "/home/cpmove-$guessuser.tar.gz";
    }

    my $md5sum = $self->{'remoteobj'}->get_md5sum_for($guess);

    return ( $guess, $md5sum );
}

sub _transfer_cpmove_files {
    my ($self) = @_;

    my $remote_file_count = scalar @{ $self->{'remote_cpmove_files'} };
    $self->{'portion_of_percentage_of_each_transfer_file'} = int( $PERCENT_FILE_TRANSFER_PHASE / $remote_file_count );

    $self->{'download_methods'} = [
        $self->{'can_stream'} ? { 'name' => 'WHM', 'sub' => '_download_via_whm' } : (),
        { 'name' => 'SCP', 'sub' => '_download_via_whm_remote' }

    ];

    for my $file_number ( 0 .. ( $remote_file_count - 1 ) ) {
        my $fileinfo = { 'number' => $file_number };

        @{$fileinfo}{ 'remote_path', 'md5sum', 'size' } = @{ $self->{'remote_cpmove_files'}->[$file_number] }{ 'path', 'md5', 'size' };

        if ( !$fileinfo->{'remote_path'} ) {
            return ( 0, $self->_locale()->maketext( "Could not determine the location of file number: “[_1]”", $fileinfo->{'number'} ) );
        }

        print $self->_locale()->maketext( "Remote file is: “[_1]” with size: [_2]", $fileinfo->{'remote_path'}, $fileinfo->{'size'} ) . "\n";

        ( $fileinfo->{'remote_dir'}, $fileinfo->{'remote_filename'} ) = Cpanel::FileUtils::Path::dir_and_file_from_path( $fileinfo->{'remote_path'} );

        $fileinfo->{'local_path'} = "$self->{'copypoint'}/$fileinfo->{'remote_filename'}";

        # Remove the target file to ensure we do not
        # incorrectly assume the old file is the correct only
        if ( -f $fileinfo->{'local_path'} ) { unlink( $fileinfo->{'local_path'} ); }

        my $download_success = $self->_attempt_download($fileinfo);

        if ( !$download_success ) {
            return ( 0, $self->_locale()->maketext( "Unable to download “[_1]” from the remote server.", $fileinfo->{'remote_path'} ) );
        }

        $self->{'remote_cpmove_files'}->[$file_number]->{'localpath'} = $fileinfo->{'local_path'};

        $self->set_percentage( int( $self->{'portion_of_percentage_of_each_transfer_file'} * ( $file_number + 1 ) + $PERCENT_PKGACCT_PHASE ) );
    }
    return ( 1, "Transfer completed" );
}

sub _attempt_download {
    my ( $self, $fileinfo ) = @_;

    if ( !$self->{'download_methods'} ) { die "_attempt_download called without setting up download_methods in _transfer_cpmove_files"; }

    my $download_success = 0;
  DOWNLOADATTEMPTS:
    for my $number_of_transfer_attempts ( 1 .. $MAX_FILE_TRANSFER_ATTEMPTS ) {
        if ( $number_of_transfer_attempts == $MAX_FILE_TRANSFER_ATTEMPTS ) {
            print $self->_locale()->maketext("Multiple copy failures, switching to verbose mode and trying one final attempt.") . "\n";
        }

      DOWNLOADMETHOD:
        foreach my $download_method ( @{ $self->{'download_methods'} } ) {
            my ( $download_method_name, $func ) = @{$download_method}{ 'name', 'sub' };

            print $self->_locale()->maketext(
                "Attempt #[_1] to transfer using “[_2]” method.",
                $number_of_transfer_attempts, $download_method_name
            ) . "\n";

            my ( $status, $statusmsg ) = $self->$func($fileinfo);

            if ($status) {
                if ( $self->_verify_package_md5( $fileinfo->{'local_path'}, $fileinfo->{'md5sum'} ) ) {
                    $download_success = 1;
                    last DOWNLOADATTEMPTS;
                }
                else {
                    print $self->_locale()->maketext("Failed to validate cpmove file.") . "\n";
                }
            }
            else {
                print $self->_locale()->maketext( "Downloading with method “[_1]” failed: [_2]", $download_method_name, $statusmsg ) . "\n";
            }
        }

        if ( $number_of_transfer_attempts != $MAX_FILE_TRANSFER_ATTEMPTS ) {
            print $self->_locale()->maketext("Retrying transfer.") . "\n";
        }
    }

    return $download_success;
}

sub _chown_remote_files_if_not_connecting_as_root {
    my ($self) = @_;

    if ( $self->{'authinfo'}->{'user'} ne 'root' ) {
        my @REMOTE_FILE_LIST = map { $_->{'path'} } @{ $self->{'remote_cpmove_files'} };

        if ( $REMOTE_FILE_LIST[0] =~ m{tar(\.gz)?\.part[0-9]+$} ) {
            my ( $remote_dir, $remote_filename ) = Cpanel::FileUtils::Path::dir_and_file_from_path( $REMOTE_FILE_LIST[0] );
            unshift @REMOTE_FILE_LIST, $remote_dir;
        }

        my ( $status, $msg ) = $self->{'remoteobj'}->remoteexec(
            'txt' => 'Setting permissions on the account package',
            'cmd' => "/bin/chown $self->{'authinfo'}->{'user'} " . join( ' ', @REMOTE_FILE_LIST )
        );

        return ( 0, $msg ) if !$status;
        return ( 1, 'Chown ok' );
    }

    return ( 1, 'Chown not needed' );
}

sub _assemble_cpmove_file {
    my ($self) = @_;

    my @REMOTE_FILE_LIST = map { $_->{'path'} } @{ $self->{'remote_cpmove_files'} };
    my @LOCAL_FILE_LIST  = map { $_->{'localpath'} } @{ $self->{'remote_cpmove_files'} };

    print $self->_locale()->maketext( "The remote file list contains: [list_and,_1]", \@REMOTE_FILE_LIST ) . "\n";
    print $self->_locale()->maketext( "The local file list contains: [list_and,_1]",  \@LOCAL_FILE_LIST ) . "\n";

    if ( scalar @{ $self->{'remote_cpmove_files'} } == 1 ) {
        if ( !-e $self->{'remote_cpmove_files'}->[0]->{'localpath'} ) {
            return ( 0, $self->_locale()->maketext( "Failed to copy the [asis,cpmove] file to: “[_1]”.", $self->{'remote_cpmove_files'}->[0]->{'localpath'} ) );
        }

        print $self->_locale()->maketext( "Copied cpmove file to: “[_1]”.", $self->{'remote_cpmove_files'}->[0]->{'localpath'} ) . "\n";

        $self->{'cpmovefile'} = ( split( /\/+/, $self->{'remote_cpmove_files'}->[0]->{'localpath'} ) )[-1];

        return ( 1, $self->{'cpmovefile'} );
    }
    else {
        my $is_compressed = Cpanel::Gzip::Detect::file_is_gzipped( $self->{'remote_cpmove_files'}->[0]->{'localpath'} ) ? 1 : 0;

        my $cpmovefile = "cpmove-$self->{'detected_remote_user'}.tar" . ( $is_compressed ? '.gz' : '' );

        my $recombine_ok = Whostmgr::Whm5::splitfile_recombine( $self->{'copypoint'}, $cpmovefile, \@LOCAL_FILE_LIST );

        print $self->_locale()->maketext( "Removing intermediate split file(s) [list_and,_1] …", \@LOCAL_FILE_LIST ) . "\n";

        unlink(@LOCAL_FILE_LIST);

        if ($recombine_ok) {
            $self->{'cpmovefile'} = $cpmovefile;
            return ( 1, $cpmovefile );
        }

        return ( 0, $self->_locale()->maketext( "Failed to recombine the assemble list: “[list_and,_1]”.", \@LOCAL_FILE_LIST ) );
    }

}

sub _remote_has_delete_account_archives_api ($self) {
    return $self->_remote_cpversion_is_at_least('11.71');
}

sub _remote_has_pkgacct_dbbackup_mysql_option ($self) {
    return $self->_remote_cpversion_is_at_least('11.87');
}

sub _get_remote_cpversion ($self) {
    return $self->{'remote_info'}{'cpversion'};
}

sub _remote_cpversion_is_at_least ( $self, $version ) {
    return Cpanel::Version::Compare::compare( $self->_get_remote_cpversion(), '>=', $version );
}

sub _remove_remote_cpmove_files_via_api {
    my ( $self, $mountpoint ) = @_;

    local $@;
    my $response = eval {
        $self->_run_whm_api(
            'delete_account_archives',
            {
                user       => $self->{'remote_user'},
                mountpoint => $mountpoint,
            },
        );
    };

    return 1 if $response && $response->{metadata}{result};

    my $err = $response ? $response->{'metadata'}{'reason'} : $@;

    $self->_add_warning( _format_message_for_output_obj( $self->_locale()->maketext( 'The system failed to remove “[_1]”’s remote account archive via the [output,abbr,API,Application Programming Interface] because of an error ([_2]). The system will now try to delete the account via [output,abbr,SSH,Secure Shell] instead.', $self->{'remote_user'}, $err ) ) );

    return;
}

sub _remove_remote_cpmove_files {
    my ($self) = @_;

    return ( 1, 'ok' ) if $self->{'_removed_remote_files'};
    $self->{'_removed_remote_files'} = 1;

    return ( 0, 'Could not remove remote cpmove files because init failed.' ) if !$self->{'output_obj'} || !$self->{'remoteobj'};

    my $mountpoint;

    # If we know where the files are we should pass the directory
    # to unpkacct.  If we do not know we just run pkgacct with the name of the
    # remote user.  This is important to do even if pkgacct has failed
    # so files are not left around on the remote machine that are filling up the disk.
    if ( ref $self->{'remote_cpmove_files'} eq 'ARRAY' && scalar( @{ $self->{'remote_cpmove_files'} } ) ) {
        my ($remote_filedir) = Cpanel::FileUtils::Path::dir_and_file_from_path( $self->{'remote_cpmove_files'}->[0]->{'path'} );
        $mountpoint = $self->_strip_cpmove_dir($remote_filedir);
    }

    # We'll attempt to use an API token, which won't work over an unencrypted
    # connection.
    if ( $self->_remote_has_delete_account_archives_api() && $self->{options}{ssl} ) {
        return 1 if $self->_remove_remote_cpmove_files_via_api($mountpoint);
    }

    my @cmd = (
        "$self->{'session_info'}->{'scriptdir'}/unpkgacct",
        $self->{'remote_user'},
        $mountpoint // (),
    );

    $self->{'output_obj'}->set_source( { 'host' => $self->{'remote_info'}->{'sshhost'} } );

    my ( $status, $err ) = $self->{'remoteobj'}->remoteexec(
        'txt' => $self->_locale()->maketext('Removing copied archive on remote server.'),
        'cmd' => \@cmd,                                                                     #remove the orginal file
    );
    $self->{'output_obj'}->set_source();

    if ( !$status ) {
        return ( 0, $self->_locale()->maketext( "The system failed to delete “[_1]”’s account archive from the remote system because of an error: [_2]", $self->{'remote_user'}, $err ) );
    }

    return ( 1, 'ok' );
}

sub _mysql_shares_mount_point_with_path ($path) {
    require Cpanel::Mysql::Constants;
    my $datadir = Cpanel::Mysql::Constants::DEFAULT()->{'datadir'};

    my $filesys_ref = Cpanel::Filesys::Info::_all_filesystem_info();

    my $mysql_mp = Cpanel::Filesys::FindParse::find_mount( $filesys_ref, $datadir );
    my $path_mp  = Cpanel::Filesys::FindParse::find_mount( $filesys_ref, $path );

    return $mysql_mp eq $path_mp;
}

sub _check_transfer_disk_space {
    my ($self) = @_;

    my ( @home_sizes, @sizes );

    my $mysqlsize;

    ##
    ## Whostmgr/Remote.pm captures cpmove file sizes and the homedir as a hashref,
    ## tagged accordingly as size and homesize and pushes each one into
    ## and arrayref.
    ##
    ## Here we convert them to something Cpanel::DiskCheck::target_has_enough_free_space_to_fit_source_sizes
    ## can handle
    foreach my $size_ref ( @{ $self->{'all_remote_sizes'} } ) {

        # INODES
        if ( $size_ref->{'homefiles'} && $self->{'can_stream'} && !$self->{'input'}->{'skiphomedir'} ) {
            push @home_sizes, { 'files' => $size_ref->{'homefiles'} };
        }
        elsif ( $size_ref->{'files'} ) {
            push @sizes, { 'files' => $size_ref->{'files'} };
        }

        # BLOCKS
        if ( $size_ref->{'homesize'} && $self->{'can_stream'} && !$self->{'input'}->{'skiphomedir'} ) {
            push @home_sizes, { 'streamed' => $size_ref->{'homesize'} };
        }
        elsif ( $size_ref->{'size'} ) {
            push @sizes, { 'gzip_compressed_tarball' => $size_ref->{'size'} };
        }
        elsif ( $size_ref->{'mysqlsize'} ) {
            $mysqlsize = $size_ref->{'mysqlsize'};
        }
    }

    my $target = $self->{'copypoint'};

    # If we are streaming the homedir, it will go to their current homedir
    # or if the account is about to be created, it will go to the homematch
    # location with the most free space
    if (@home_sizes) {
        my $user_homeroot = Cpanel::PwCache::gethomedir( $self->{'input'}->{'localuser'} ) || Cpanel::Filesys::Home::get_homematch_with_most_free_space();
        my $filesys_ref   = Cpanel::Filesys::Info::_all_filesystem_info();

        # If we are restoring their homedir and extracting the cpmove file
        # on the same partition, just check the highest level by combining
        # the sizes into the final check. For example: if we restore
        # the homedir to /home/dog and extract the tarball to /home, we
        # only have to check /home since we know that will include both
        # paths.
        if ( Cpanel::Filesys::FindParse::find_mount( $filesys_ref, $user_homeroot ) eq Cpanel::Filesys::FindParse::find_mount( $filesys_ref, $self->{'copypoint'} ) ) {

            # Display the highest level directory
            if ( length $user_homeroot < length $self->{'copypoint'} ) { $target = $user_homeroot; }

            # On the same partition
            push @sizes, @home_sizes;
        }
        else {
            my ( $space_ok, $space_msg ) = Cpanel::DiskCheck::target_has_enough_free_space_to_fit_source_sizes( 'source_sizes' => \@home_sizes, 'target' => $user_homeroot );
            return ( $space_ok, $space_msg ) if !$space_ok;
        }
    }

    my $skip_mysqlsize_check;

    if ( $mysqlsize && _mysql_shares_mount_point_with_path($target) ) {
        $skip_mysqlsize_check = 1;
        push @sizes, { mysqlsize => $mysqlsize };
    }

    my ( $ok, $why ) = Cpanel::DiskCheck::target_has_enough_free_space_to_fit_source_sizes( 'source_sizes' => \@sizes, 'target' => $target );
    return ( $ok, $why ) if !$ok;

    if ( $ok && $mysqlsize && !$skip_mysqlsize_check ) {
        ( $ok, $why ) = Cpanel::DiskCheck::target_has_enough_free_space_to_fit_source_sizes(
            target       => Cpanel::Mysql::Constants::DEFAULT()->{'datadir'},
            source_sizes => [
                { mysqlsize => $mysqlsize },
            ],
        );
    }

    return ( $ok, $why );
}

sub _locate_remote_files {
    my ($self) = @_;
    if ( $self->{'issplit'} ) {
        print $self->_locale()->maketext("Using the archive split method!");
        for ( my $i = 0; $i < scalar @{ $self->{'remote_cpmove_files'} }; $i++ ) {
            print $self->_locale()->maketext( "File #[_1]: “[_2]” with [asis,md5sum]: [_3]", ( $i + 1 ), $self->{'remote_cpmove_files'}->[$i]->{'path'}, $self->{'remote_cpmove_files'}->[$i]->{'md5'} ) . "\n";
        }
    }
    else {
        if ( !$self->{'remote_cpmove_files'} || !scalar @{ $self->{'remote_cpmove_files'} } ) {
            my ( $guess, $md5sum ) = $self->_guess_cpmove_location();
            if ($md5sum) {
                push @{ $self->{'remote_cpmove_files'} },
                  {
                    'path' => $guess,
                    'md5'  => $md5sum,
                    'size' => 1000,
                  };
                print $self->_locale()->maketext( "Using the single archive method with guessed filename: “[_1]”.", $guess ) . "\n";

            }
            else {
                return ( 0, $self->_locale()->maketext( "The remote execution of “[_1]” failed, or the requested account, “[_2]”, was not found on the server: “[_3]”.", $self->_get_pkgacct_filename(), $self->item(), $self->{'remote_info'}->{'sshhost'} ) );
            }
        }
        print $self->_locale()->maketext( "Using the single archive method with filename: “[_1]”.", $self->{'remote_cpmove_files'}->[0]->{'path'} ) . "\n";
    }

    return ( 1, 'OK' );
}

sub _download_via_whm {
    my ( $self, $fileinfo ) = @_;

    ## case 16718: whm_xfer_download-ssl currently fails for non-root user that is not a reseller on the remote machine
    ### try streaming
    my ( $status, $statusmsg ) = Whostmgr::XferClient::download(
        'use_ssl'          => ( $self->{'options'}->{'ssl'} ? 1 : 0 ),
        'host'             => $self->{'remote_info'}->{'sshhost'},
        'user'             => $self->{'authinfo'}->{'whmuser'},
        'pass'             => $self->{'authinfo'}->{'whmpass'},
        'source_file_path' => $fileinfo->{'remote_path'},
        'target_file_path' => "$self->{'copypoint'}/$fileinfo->{'remote_filename'}",
        'accesshash'       => $self->{'authinfo'}->{'accesshash_pass'}
    );

    return ( $status, $statusmsg );
}

sub _download_via_whm_remote {
    my ( $self, $fileinfo ) = @_;

    $self->{'output_obj'}->set_source( { 'host' => $self->{'remote_info'}->{'sshhost'} } );

    my ( $status, $statusmsg ) = $self->{'remoteobj'}->remotecopy(
        'txt'       => $self->_locale()->maketext("Copying account package file …"),
        'size'      => $fileinfo->{'size'},
        'direction' => 'download',
        'srcfile'   => $fileinfo->{'remote_path'},
        'destfile'  => '.',
        'callback'  => sub {
            my ($output) = @_;

            $self->set_percentage( int( ( $self->{'portion_of_percentage_of_each_transfer_file'} * $fileinfo->{'number'} ) + ( $self->{'portion_of_percentage_of_each_transfer_file'} * ( $output / 100 ) ) + $PERCENT_PKGACCT_PHASE ) );
        },
    );
    $self->{'output_obj'}->set_source();

    return ( $status, $statusmsg );
}

sub _get_pkgacct_filename {
    my ($self) = @_;

    #
    # If we are using enable_custom_pkgacct, we have uploaded pkgacct to the remote machine
    # and appended our hostname to know where it came from
    #
    return ( $self->{'remote_info'}->{'pkgacct_file'} || 'pkgacct' );
}

sub _validate_usernames {
    my ($self) = @_;
    if ( !length $self->{'remote_user'} ) {
        return ( 0, $self->_locale()->maketext("The remote username cannot be empty.") );
    }
    elsif ( !$self->{'remote_user'} ) {
        return ( 0, $self->_locale()->maketext( "The remote username “[_1]” is not a valid username.", 0 ) );
    }
    if ( !length $self->{'local_user'} ) {
        return ( 0, $self->_locale()->maketext("The local username cannot be empty.") );
    }
    elsif ( !$self->{'local_user'} ) {
        return ( 0, $self->_locale()->maketext( "The local username “[_1]” is not a valid username.", 0 ) );
    }

    my ( $ok, $why ) = $self->_validate_local_username_against_system_state( $self->{'local_user'} );
    return ( 0, $why ) if !$ok;

    return ( 1, "User validated" );
}

sub _find_location_with_most_free_space {
    my ($self) = @_;

    #Add Support for non-compressed .tar files
    $self->{'copypoint'} = Cpanel::Filesys::Home::get_homematch_with_most_free_space() || '/home';
    chdir( $self->{'copypoint'} ) or return ( 0, $self->_locale()->maketext( "Copy Destination [_1] does not exist!", $self->{'copypoint'} ) );
    print $self->_locale()->maketext( "Copy Destination: [_1]", $self->{'copypoint'} ) . "\n";

    return ( 1, "Using location $self->{'copypoint'}" );
}

sub tear_down_transfer {
    my ($self) = @_;

    $self->_remove_remote_cpmove_files();

    if ( $self->{'orig_cwd'} ) {
        return chdir( $self->{'orig_cwd'} );
    }

    return 1;
}

sub _save_results_to_session {
    my ($self) = @_;

    my $ok =
         $self->set_key( 'detected_remote_user', $self->{'detected_remote_user'} )
      && $self->set_key( 'copypoint',            $self->{'copypoint'} )
      && $self->set_key( 'cpmovefile',           $self->{'cpmovefile'} );

    if ( !$ok ) {
        return ( 0, $self->_locale()->maketext("Failed to save the result of the transfer to the session database.") );
    }
    return ( 1, "Saved resulted to session database." );
}

sub _pkgacct_callback {
    my ( $self, $output ) = @_;

    return if !length $output;

    if ( $output =~ m{^Copying Mail}i ) {
        $self->set_percentage(10);
    }
    elsif ( $output =~ m{^Copying homedir}i ) {
        $self->set_percentage(20);
    }
    elsif ( $output =~ m{^Storing mysql}i ) {
        $self->set_percentage(30);
    }
    elsif ( $output =~ m{^Creating Archive}i ) {
        $self->set_percentage(40);
    }

    return 1;
}

sub _strip_cpmove_dir {
    my ( $self, $remote_filedir ) = @_;

    #
    # If we have a cpmove- dir, unpkgacct expects it to be removed
    # as it will search the provided directory for the following:
    #
    # cpmove-USER-split
    # cpmove-USER
    # cpmove-USER.tar
    # cpmove-USER.tar.gz
    #
    # and remove them
    #
    if ( $remote_filedir =~ m{/cpmove-[^-]+-split/?$} ) {
        $remote_filedir =~ s{/cpmove-[^-]+-split/?$}{};
    }
    else {
        $remote_filedir =~ s{/cpmove-[^/]+/?$}{};
    }
    return $remote_filedir;
}

1;
