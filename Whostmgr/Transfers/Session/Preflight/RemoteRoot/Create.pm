package Whostmgr::Transfers::Session::Preflight::RemoteRoot::Create;

# cpanel - Whostmgr/Transfers/Session/Preflight/RemoteRoot/Create.pm
#                                                  Copyright 2022 cPanel, L.L.C.
#                                                           All rights reserved.
# copyright@cpanel.net                                         http://cpanel.net
# This code is subject to the cPanel license. Unauthorized copying is prohibited

use cPstrict;

use Cpanel::Capture              ();
use Whostmgr::Transfers::Version ();
use Cpanel::Config::LoadCpConf   ();
use Cpanel::IP::LocalCheck       ();
use Cpanel::Locale               ();
use Cpanel::LoadFile             ();

use Whostmgr::Remote                        ();
use Whostmgr::Remote::CommTransport         ();
use Whostmgr::Transfers::Session::Constants ();
use Whostmgr::Transfers::Session::Setup     ();
use Whostmgr::Whm5                          ();
use Whostmgr::XferClient                    ();

use Whostmgr::Transfers::RestrictedRestore ();
use Whostmgr::Transfers::MysqlStream       ();

our $ACCESS_HASH_USER         = 'root';
our $ACCESS_HASH_USER_HOMEDIR = '/root';
our $ACCESS_HASH_PATH         = "$ACCESS_HASH_USER_HOMEDIR/.accesshash";

sub create_remote_root_transfer_session {
    my (@args) = @_;

    local $@;
    local $SIG{'__DIE__'} = 'DEFAULT';

    my $ret = Cpanel::Capture::trap_stdout(
        sub {
            return _create_remote_root_transfer_session(@args);
        }
    );

    my @captured_return = @{ $ret->{'return'} };

    if ( !scalar @captured_return ) {
        @captured_return = ( 0, $ret->{'EVAL_ERROR'} );
    }

    return ( @captured_return, $ret->{'output'} );

}

sub _get_create_opts_err ($opts_hr) {
    my @errs;

    if ( my $comm_xport = $opts_hr->{'comm_transport'} ) {
        my @COMM_TRANSPORTS = Whostmgr::Remote::CommTransport::VALUES();

        if ( !grep { $_ eq $comm_xport } @COMM_TRANSPORTS ) {
            push @errs, "Invalid “comm_transport” ($comm_xport).";
        }
    }

    return "@errs";
}

sub _create_remote_root_transfer_session {
    my $opts = shift;

    if ( !Whostmgr::Transfers::RestrictedRestore::available() && !$opts->{'unrestricted_restore'} ) {
        return ( 0, _locale()->maketext('Restricted Restore is not available in this version of [output,asis,cPanel].') );
    }

    my $err = _get_create_opts_err($opts);
    return ( 0, $err ) if $err;

    # Normalize:
    local $opts->{'comm_transport'} = $opts->{'comm_transport'} || ( Whostmgr::Remote::CommTransport::VALUES() )[0];

    my ( $create_ok, $new_session_data ) = _create_session_data_from_opts($opts);
    return ( 0, $new_session_data ) if !$create_ok;

    my ( $cred_ok, $cred_msg, $remote_obj ) = _remote_basic_credential_check_and_setup( $new_session_data, $opts );
    return ( 0, $cred_msg ) if !$cred_ok;

    my ( $remote_check_ok, $remote_check_msg ) = _determine_servtype_from_remote_and_setup_access( $new_session_data, $remote_obj );
    return ( 0, $remote_check_msg ) if !$remote_check_ok;

    my ( $cp_ok, $cp_msg ) = _remote_cpanel_server_checks( $new_session_data, $remote_obj );
    return ( 0, $cp_msg ) if !$cp_ok;

    if ( Whostmgr::Transfers::Version::servtype_version_compare( $new_session_data->{'remote'}->{'type'}, '>=', '11.23' ) ) {

        if ( Whostmgr::Transfers::Version::servtype_version_compare( $new_session_data->{'remote'}->{'type'}, '>=', '11.63' ) ) {
            _create_api_token( $new_session_data, $remote_obj );
        }
        else {
            # generates an accesshash for $ACCESS_HASH_ROOT if none is set, on success resets whmuser to $ACCESS_HASH_ROOT and deletes whmpass
            # if $ACCESS_HASH_ROOT is not the same as $user;
            _get_access_hash( $new_session_data, $remote_obj );
        }

        # uses whmuser/whmpass to check for stream support on the source server if for some reason the access hash has not
        # been generated successfully otherwise, it uses the whmuser and the accesshash to do the check
        _check_for_streaming_support($new_session_data);

        _check_for_mysql_streaming_support($new_session_data);
    }

    $new_session_data->{'session'}->{'scriptdir'} = Whostmgr::Remote->remotescriptdir( $new_session_data->{'remote'}->{'type'} );

    my ( $session_ok, $session_obj ) = Whostmgr::Transfers::Session::Setup::setup_session_obj(
        {
            'initiator'           => Whostmgr::Transfers::Session::Constants::ROOT_API_SESSION_INITIATOR,
            'create'              => 1,
            'session_id_template' => $new_session_data->{'remote'}->{'sshhost'},
        },
        $new_session_data
    );

    print _locale()->maketext( "Remote Server Type: [_1]", $new_session_data->{'remote'}->{'type'} ) . "\n";

    return ( 0, $session_obj ) if !$session_ok;

    $session_obj->set_source_host( $new_session_data->{'remote'}->{'sshhost'} );

    my $id = $session_obj->id();

    $session_obj->disconnect();    # TP TASK 20767 disconnect before global destruct

    return ( 1, $id );
}

sub _check_for_mysql_streaming_support ($new_session_data) {
    my $remote_cp_version = $new_session_data->{'remote'}{'version'};

    my $mysql_stream_method;

    # API tokens require SSL.
    my $maybe_yn = $new_session_data->{'options'}{'ssl'};

    # Don’t try to stream MySQL if we already can’t stream the homedir.
    $maybe_yn &&= $new_session_data->{'remote'}{'can_stream'};

    $maybe_yn &&= $new_session_data->{'remote'}{'type'} =~ m<WHM>;

    if ($maybe_yn) {
        my $eleven_min = '11.' . Whostmgr::Transfers::MysqlStream::MINIMUM_CP_VERSION();
        require Cpanel::Version::Compare;
        if ( Cpanel::Version::Compare::compare( $remote_cp_version, '>=', $eleven_min ) ) {
            $mysql_stream_method = 'plain';
        }
    }

    $new_session_data->{'remote'}{'mysql_streaming_method'} = $mysql_stream_method;

    return;
}

sub _check_for_streaming_support {
    my ($new_session_data) = @_;

    # API tokens won't work here due to the lack of SSL, and it's rather
    # imprudent to send the root password over an unencrypted connection.
    if ( !$new_session_data->{'options'}{'ssl'} ) {
        $new_session_data->{'remote'}->{'can_stream'} = 0;
        print _locale()->maketext("The system is unable to stream account transfers because encryption is disabled.") . "\n";
        return;
    }

    if ( !defined $new_session_data->{'remote'}->{'can_stream'} && $new_session_data->{'authinfo'}->{'whmuser'} && $new_session_data->{'authinfo'}->{'whmpass'} ) {
        print _locale()->maketext( "Testing “[_1]” for transfer streaming support with password authentication …", $new_session_data->{'remote'}->{'sshhost'} );

        local $@;
        local $SIG{'__DIE__'} = 'DEFAULT';

        my $stream_ref;
        eval {
            $stream_ref = Whostmgr::XferClient::stream_test(
                'use_ssl' => $new_session_data->{'options'}->{'ssl'},         #
                'host'    => $new_session_data->{'remote'}->{'sshhost'},      #
                'user'    => $new_session_data->{'authinfo'}->{'whmuser'},    #
                'pass'    => $new_session_data->{'authinfo'}->{'whmpass'}     #
            );
        };

        if ($@) {
            $new_session_data->{'remote'}->{'can_stream'} = 0;
            print _locale()->maketext( "The system is unable to stream account transfers with password authentication: [_1]", "$@" ) . "\n";
        }
        else {
            if ( ref $stream_ref && ( $new_session_data->{'remote'}->{'can_stream'} = $stream_ref->{'streaming'} ) ) {
                $new_session_data->{'remote'}->{'can_rsync'} = $stream_ref->{'rsync'};
                print _locale()->maketext("[output,strong,Streaming Supported]") . "\n";

                if ( $new_session_data->{'remote'}{'can_rsync'} ) {
                    print _locale()->maketext("[output,strong,rsync Supported]") . "\n";
                }
            }
            else {
                print _locale()->maketext("Streaming NOT Supported") . "\n";
            }
        }
    }
    if ( !$new_session_data->{'remote'}->{'can_stream'} && defined $new_session_data->{'authinfo'}->{'whmuser'} && defined $new_session_data->{'authinfo'}->{'accesshash_pass'} ) {

        print _locale()->maketext( "Testing “[_1]” for transfer streaming support with accesshash authentication …", $new_session_data->{'remote'}->{'sshhost'} );

        local $@;
        local $SIG{'__DIE__'} = 'DEFAULT';

        my $stream_ref;
        eval {
            $stream_ref = Whostmgr::XferClient::stream_test(
                'use_ssl'    => $new_session_data->{'options'}->{'ssl'},                #
                'host'       => $new_session_data->{'remote'}->{'sshhost'},             #
                'user'       => $new_session_data->{'authinfo'}->{'whmuser'},           #
                'accesshash' => $new_session_data->{'authinfo'}->{'accesshash_pass'}    #
            );
        };

        if ($@) {
            $new_session_data->{'remote'}->{'can_stream'} = 0;
            print _locale()->maketext( "The system is unable to stream account transfers with accesshash authentication: [_1]", "$@" ) . "\n";
        }
        else {
            if ( $stream_ref && ( $new_session_data->{'remote'}{'can_stream'} = $stream_ref->{'streaming'} ) ) {
                $new_session_data->{'remote'}->{'can_rsync'} = $stream_ref->{'rsync'};

                print _locale()->maketext("[output,strong,Streaming Supported]") . "\n";

                if ( $new_session_data->{'remote'}{'can_rsync'} ) {
                    print _locale()->maketext("[output,strong,rsync Supported]") . "\n";
                }
            }
            else {
                print _locale()->maketext("Streaming NOT Supported") . "\n";
            }
        }
    }

    return;
}

sub _create_api_token {
    my ( $new_session_data, $remote_obj ) = @_;

    # can't shortcircuit this and go off what is in $new_session_data->{'authinfo'}->{'accesshash_pass'} already,
    # cause that is populated by the _determine_servtype_from_remote_and_setup_access() - as it will always try to load
    # the accesshash file content in.

    my $token_name = "transfer-" . time();
    my ( $ok, undef, undef, undef, undef, undef, undef, $json ) = $remote_obj->remoteexec(
        'cmd' => [ '/usr/local/cpanel/bin/whmapi1', 'api_token_create', "token_name=$token_name", '--output=json' ],
        'txt' => _locale()->maketext( "Creating API Token “[_1]” on “[_2]”.", $token_name, $new_session_data->{'remote'}->{'sshhost'} ),
    );

    my $token_details;
    eval {
        require Cpanel::JSON;
        my $_json = Cpanel::JSON::Load($json);
        if ( ref $_json eq 'HASH' && $_json->{'metadata'}->{'result'} ) {
            $token_details = $_json->{'data'};
        }
    };

    if ( !$token_details ) {
        my $err = $@;
        print _locale()->maketext( "The system failed to generate an [asis,API] token on “[_1]”.", $new_session_data->{'remote'}->{'sshhost'} );
        print $err if $err;
    }
    else {
        $new_session_data->{'authinfo'}->{'api_token'}       = $token_name;
        $new_session_data->{'authinfo'}->{'whmuser'}         = $ACCESS_HASH_USER;
        $new_session_data->{'authinfo'}->{'accesshash_pass'} = $token_details->{'token'};

        # whmuser and whmpass are initialized in with $user and $user's $password, respectively, so delete unless $ACCESS_HASH_USER and $user are the same
        # in order to avoid _check_for_streaming_support to use the bad whmpass rather than the $accesshash valid for $ACCESS_HASH_USER created above
        delete $new_session_data->{'authinfo'}->{'whmpass'} unless $ACCESS_HASH_USER eq $new_session_data->{'authinfo'}->{'user'};
    }

    return;
}

sub _get_access_hash {
    my ( $new_session_data, $remote_obj ) = @_;

    return 1 if $new_session_data->{'authinfo'}->{'accesshash_pass'};    # we already got it

    my ( $cat_ok, $accesshash ) = $remote_obj->cat_file($ACCESS_HASH_PATH);
    if ( !$accesshash ) {
        $remote_obj->remoteexec(
            'cmd' => "REMOTE_USER=$ACCESS_HASH_USER /usr/local/cpanel/bin/mkaccesshash",
            'txt' => _locale()->maketext( "Creating access hash on “[_1]”.", $new_session_data->{'remote'}->{'sshhost'} ),
        );
        ( $cat_ok, $accesshash ) = $remote_obj->cat_file($ACCESS_HASH_PATH);
    }
    if ($accesshash) {
        $accesshash =~ s/\s//g;
    }

    if ( !$accesshash ) {
        print _locale()->maketext( "The system failed to download the access hash from “[_1]”.", $new_session_data->{'remote'}->{'sshhost'} );
    }
    elsif ($cat_ok) {
        $new_session_data->{'authinfo'}->{'whmuser'}         = $ACCESS_HASH_USER;
        $new_session_data->{'authinfo'}->{'accesshash_pass'} = $accesshash;

        # whmuser and whmpass are initialized in with $user and $user's $password, respectively, so delete unless $ACCESS_HASH_USER and $user are the same
        # in order to avoid _check_for_streaming_support to use the bad whmpass rather than the $accesshash valid for $ACCESS_HASH_USER created above
        delete $new_session_data->{'authinfo'}->{'whmpass'} unless $ACCESS_HASH_USER eq $new_session_data->{'authinfo'}->{'user'};
    }
    else {
        # $accesshash has a localized error
        print $accesshash . "\n";
    }

    return;
}

sub _init_whmuser_whmpass {
    my ($new_session_data) = @_;

    if ( $new_session_data->{'authinfo'}->{'user'} eq 'root' || $new_session_data->{'authinfo'}->{'root_escalation_method'} eq 'su' ) {
        $new_session_data->{'authinfo'}->{'whmuser'} = 'root';

        if ( $new_session_data->{'authinfo'}->{'user'} eq 'root' ) {    #the UI will remove the root_password field...
            $new_session_data->{'authinfo'}->{'whmpass'} = $new_session_data->{'authinfo'}->{'password'};
        }
        else {
            $new_session_data->{'authinfo'}->{'whmpass'} = $new_session_data->{'authinfo'}->{'root_password'};
        }
    }
    else {
        $new_session_data->{'authinfo'}->{'whmuser'} = $new_session_data->{'authinfo'}->{'user'};
        $new_session_data->{'authinfo'}->{'whmpass'} = $new_session_data->{'authinfo'}->{'password'};
    }
    return 1;
}

sub _determine_servtype_from_remote_and_setup_access {
    my ( $new_session_data, $remote_obj ) = @_;

    my $remote_host_calculation_shell_code = Cpanel::LoadFile::load('/usr/local/cpanel/whostmgr/libexec/remote_host_calculation_shell_code.template');
    my @remote_exec_list                   = (
        { 'key' => 'accesshash',            'shell_safe_command' => "/bin/cat", 'shell_safe_arguments' => $ACCESS_HASH_PATH },
        { 'key' => 'cpanel_installed',      'shell_safe_command' => "[ -e '/usr/local/cpanel/cpanel.lisc' ] && echo 'cpanel'" },
        { 'key' => 'cpanel_version',        'shell_safe_command' => "/bin/cat", 'shell_safe_arguments' => '/usr/local/cpanel/version' },
        { 'key' => 'plesk_installed',       'shell_safe_command' => "[ -e '/usr/local/psa' ] && echo 'plesk'" },
        { 'key' => 'plesk_version',         'shell_safe_command' => "/bin/cat", 'shell_safe_arguments' => '/usr/local/psa/version' },
        { 'key' => 'plesk_smb_installed',   'shell_safe_command' => "/bin/grep \"Small Business Panel\" /etc/sw/keys/keys/*" },
        { 'key' => 'directadmin_installed', 'shell_safe_command' => "[ -e '/usr/local/directadmin' ] && echo 'directadmin'" },
        { 'key' => 'directadmin_version',   'shell_safe_command' => "/bin/grep", 'shell_safe_arguments' => 'directadmin /usr/local/directadmin/custombuild/versions.txt' },
        { 'key' => 'ensim_installed',       'shell_safe_command' => "[ -e '/usr/lib/opcenter' ] && echo 'ensim'" },
        { 'key' => 'ensim_version',         'shell_safe_command' => "/bin/cat", 'shell_safe_arguments' => '/usr/lib/opcenter/VERSION' },
        { 'key' => 'allow_ip_csf',          'shell_safe_command' => "$remote_host_calculation_shell_code /usr/sbin/csf " . '-ta $REMOTE_HOST 5d' },
        { 'key' => 'allow_ip_cphulkd',      'shell_safe_command' => "$remote_host_calculation_shell_code /usr/local/cpanel/scripts/cphulkdwhitelist " . '$REMOTE_HOST' },
    );
    my ( $status, $resultref ) = $remote_obj->multi_exec( \@remote_exec_list );
    if ($status) {
        my $system;
        if ( $resultref->{'cpanel_installed'} ) {
            $system = 'cpanel';
        }
        elsif ( $resultref->{'plesk_installed'} || $resultref->{'plesk_smb_installed'} =~ m{Small Business Panel} ) {
            $system = 'plesk';
        }
        elsif ( $resultref->{'directadmin_installed'} ) {
            $system = 'directadmin';
        }
        elsif ( $resultref->{'ensim_installed'} ) {
            $system = 'ensim';
        }

        if ($system) {
            my $version = $resultref->{"$system\_version"};
            $version ||= '';
            $version =~ s/^\s+//;
            $version =~ s/\s$//;
            $version ||= 'unknown';

            $new_session_data->{'remote'}->{'type'} = $system;

            if ( $system eq 'cpanel' ) {
                $new_session_data->{'remote'}->{'cpversion'} = $new_session_data->{'remote'}->{'version'} = ( split( /-/, $version, 2 ) )[0];
                if ( my $accesshash = $resultref->{'accesshash'} ) {
                    $accesshash =~ s/\s//g;
                    if ($accesshash) {
                        $new_session_data->{'authinfo'}->{'whmuser'}         = $ACCESS_HASH_USER;
                        $new_session_data->{'authinfo'}->{'accesshash_pass'} = $accesshash;
                    }
                }
                return ( 1, _locale()->maketext( "The system detected cPanel version “[_1]” on the source server.", $new_session_data->{'remote'}->{'version'} ) );
            }
            elsif ( $system eq 'directadmin' ) {
                $new_session_data->{'remote'}->{'version'} = ( split( m{:}, $version ) )[1];
                return ( 1, _locale()->maketext( "The system detected DirectAdmin version “[_1]” on the source server.", $version ) );
            }
            elsif ( $system eq 'plesk' ) {
                $new_session_data->{'remote'}->{'version'} = ( split( /\s+/, $version ) )[0];
                return ( 1, _locale()->maketext( "The system detected Parallels Plesk® version “[_1]” on the source server.", $new_session_data->{'remote'}->{'version'} ) );
            }
            elsif ( $system eq 'ensim' ) {
                $new_session_data->{'remote'}->{'version'} = ( split( /-/, $version, 2 ) )[0];
                return ( 1, _locale()->maketext( "The system detected Ensim version “[_1]” on the source server.", $version ) );
            }
        }
        return ( 1, _locale()->maketext("The system could not automatically detect a control panel type or version on the source server.") );
    }
    else {
        return ( 0, $resultref );
    }
}

sub _create_remote_obj_commandstream ($args) {

    require Whostmgr::Remote::CommandStream::Legacy;

    my $remote_obj = Whostmgr::Remote::CommandStream::Legacy->new($args);

    local $@;
    if ( !eval { $remote_obj->connect_or_die(); 1 } ) {
        my $err = $@;

        if ( eval { $err->isa('Cpanel::Exception') } ) {
            $err = $err->get_string_no_id();
        }

        return ( 0, $err );
    }

    return ( 1, $remote_obj );
}

sub _create_remote_obj_ssh ( $args, $new_session_data ) {
    my ( $remote_ok, $remote_obj ) = Whostmgr::Remote->new_trap_exceptions($args);
    return ( $remote_ok, $remote_obj ) if !$remote_ok;

    my ( $result, $reason, $remote_response, $data, $escalation_method_used_name ) = $remote_obj->remote_basic_credential_check();

    if ( !$result ) {
        my $displayable_remote_response = $remote_response || '';
        $displayable_remote_response =~ s/==sshcontrol_.*?==\n?//g;

        return ( 0, _locale()->maketext( 'The remote basic credential check failed due to an error ([_1]) and response: [_2]', $reason, $displayable_remote_response ) );
    }

    if ($escalation_method_used_name) {
        my ($escalation_method_used) = ( $escalation_method_used_name =~ m{^(\S+)} );
        if ( $escalation_method_used && $escalation_method_used ne $new_session_data->{'authinfo'}->{'root_escalation_method'} ) {
            print _locale()->maketext( "The root escalation method “[_1]” was unsuccessful, now using “[_2]”.", $new_session_data->{'authinfo'}->{'root_escalation_method'}, $escalation_method_used );
            $new_session_data->{'authinfo'}->{'root_escalation_method'} = $escalation_method_used;

            if ( $escalation_method_used eq 'sudo' ) {
                $new_session_data->{'authinfo'}->{'password'} ||= $new_session_data->{'authinfo'}->{'root_password'};
            }
            else {    # 'su'
                $new_session_data->{'authinfo'}->{'root_password'} ||= $new_session_data->{'authinfo'}->{'password'};
            }
        }
    }

    return ( 1, $remote_obj );
}

sub _remote_basic_credential_check_and_setup {
    my ( $new_session_data, $opts ) = @_;

    my $remote_host = $new_session_data->{'remote'}->{'sshhost'};

    my $remote_obj;

    my $tls_verification = Whostmgr::Remote::CommTransport::get_cpsrvd_tls_verification( $opts->{'comm_transport'} );

    my $try_ssh_cr = sub {
        my $args = {
            'host' => $remote_host,
            'port' => $new_session_data->{'remote'}->{'sshport'},
        };

        foreach my $key (qw(user password root_password root_escalation_method sshkey_name sshkey_passphrase)) {
            $args->{$key} = $opts->{$key};
        }

        if ( $args->{'user'} ne 'root' ) {
            $args->{'root_escalation_method'} ||= 'sudo';
        }

        return _create_remote_obj_ssh( $args, $new_session_data );
    };

    my $try_commandstream_cr = sub ($tls_verification) {
        my %args = (
            'host' => $remote_host,
            %{$opts}{ 'user', 'password' },
            tls_verification => $tls_verification,
        );

        return _create_remote_obj_commandstream( \%args );
    };

    my @try_order;

    if ($tls_verification) {
        @try_order = (
            [ $opts->{'comm_transport'}, $try_commandstream_cr, $tls_verification ],
            [ 'ssh', $try_ssh_cr ],
        );
    }
    else {
        @try_order = (
            [ 'ssh', $try_ssh_cr ],
        );

        if ( !grep { !length $opts->{$_} } qw( user password ) ) {
            push @try_order, [ 'whostmgr', $try_commandstream_cr, 'on' ];
        }
    }

    my $principal_err;

    for my $n ( 0 .. $#try_order ) {
        my $cr_args_ar = $try_order[$n];

        my ( $xport, $cr, @args ) = @$cr_args_ar;

        ( my $ok, $remote_obj ) = $cr->(@args);

        if ($ok) {
            $new_session_data->{'authinfo'}{'comm_transport'} = $xport;
            last;
        }

        $remote_obj =~ s<\s+\z><>;

        my $msg = "$xport transport failed ($remote_obj); ";
        if ( $n == $#try_order ) {
            $msg .= 'no more transports to try.';
        }
        else {
            my $next_xport = $try_order[ 1 + $n ][0];
            $msg .= "trying $next_xport …";
        }

        warn "$msg\n";

        $principal_err ||= $remote_obj;
        undef $remote_obj;

    }

    # We return the first error, not the most recent, because
    # that correlates with the actual request.
    return ( 0, $principal_err ) if !$remote_obj;

    # initialize whmuser and whmpass
    _init_whmuser_whmpass($new_session_data);

    my $escalation_method = $new_session_data->{'authinfo'}->{'root_escalation_method'};

    if ( !$escalation_method || $escalation_method ne 'sudo' ) {

        # It’s important that we not send root_password to sshcontrol
        # if sudo is the escalation method because sshcontrol interprets
        # a truthy root_password as a request to use su rather than sudo.
        # While normal commands will still work, they’ll be slow because
        # we have to wait for sshcontrol to fail su before falling back
        # to sudo.
        $new_session_data->{'authinfo'}->{'root_password'} ||= $new_session_data->{'authinfo'}->{'password'};
    }

    if ( $opts->{'comm_transport'} eq 'ssh' ) {

        # TODO: Whostmgr::Remote should have a set_auth_info so we can do
        # $remote_obj->set_auth_info($new_session_data->{'authinfo'});
        # however we have to just dig in the object for now.
        #
        $remote_obj->{'authinfo'} = $new_session_data->{'authinfo'};
    }

    return ( 1, "Check OK", $remote_obj );
}

sub _remote_cpanel_server_checks {
    my ( $new_session_data, $remote_obj ) = @_;
    if ( $new_session_data->{'remote'}->{'cpversion'} ) {

        #my ( $do_check, $check_msg ) = check_db_prefix_status( $remote_obj, $new_session_data->{'remote'}->{'cpversion'} );
        #return ( 0, $check_msg ) if !$do_check;

        $new_session_data->{'remote'}->{'type'} = Whostmgr::Whm5::find_WHM_version( $new_session_data->{'remote'}->{'cpversion'} );
    }

    if ( $new_session_data->{'remote'}->{'type'} ) {
        if ( $new_session_data->{'remote'}->{'type'} =~ m{^WHM} || $new_session_data->{'remote'}->{'type'} eq 'auto' ) {
            $new_session_data->{'remote'}->{'type'} = Whostmgr::Whm5::remote_get_whm_servtype( $remote_obj, $new_session_data->{'remote'}->{'type'} );
        }

        if ( $new_session_data->{'remote'}->{'type'} eq 'preWHM45' ) {
            return ( 0, _locale()->maketext("The remote server does not appear to be running a supported version of cPanel.") . ' ' . _locale()->maketext("Please ensure you have selected the correct [output,em,Remote Server Type].") . ' ' . _locale()->maketext("Account transfers from cPanel 11.18 servers or earlier are no longer supported.") );
        }
    }

    return ( 1, 'OK' );
}

sub _create_session_data_from_opts {
    my ($opts) = @_;

    if ( !$opts->{'host'} ) {
        return ( 0, _locale()->maketext("You must specify a source host.") );
    }

    my $timeout_seconds = 5;
    require Cpanel::SocketIP;
    my $ip = Cpanel::SocketIP::_resolveIpAddress( $opts->{'host'}, 'timeout' => $timeout_seconds, any_proto => 1 );
    if ( !$ip ) {
        return ( 0, _locale()->maketext( "The system was unable to resolve the host, “[_1]”, to an IP address.", $opts->{'host'} ) );
    }

    if ( Cpanel::IP::LocalCheck::ip_is_on_local_server($ip) ) {

        local ( $@, $! );
        require Cpanel::BuildState;

        # Allow “self-transfers” in development contexts since this
        # is useful for quick testing. For production, though, we
        # don’t want to go down this route.
        if ( !Cpanel::BuildState::is_development() ) {
            return ( 0, _locale()->maketext( '“[_1]” resolves to the local server. Provide a remote hostname or [asis,IP] address instead.', $opts->{'host'} ) );
        }
    }

    my $cpconf           = Cpanel::Config::LoadCpConf::loadcpconf();
    my $new_session_data = {
        'authinfo' => {
            'user'                   => $opts->{'user'},
            'password'               => $opts->{'password'},
            'comm_transport'         => $opts->{'comm_transport'},
            'root_password'          => $opts->{'root_password'},
            'root_escalation_method' => $opts->{'root_escalation_method'},
            'sshkey_name'            => $opts->{'sshkey_name'},
            'sshkey_passphrase'      => $opts->{'sshkey_passphrase'},
            'sphera_user'            => $opts->{'sphera_user'},
            'sphera_password'        => $opts->{'sphera_password'},
            'sphera_host'            => $opts->{'sphera_host'},
        },
        'session' => {
            'transfer_threads' => int( $opts->{'transfer_threads'} || 1 ),
            'restore_threads'  => int( $opts->{'restore_threads'}  || 1 ),
            'session_timeout'  => int( $opts->{'session_timeout'}  || $cpconf->{'transfers_timeout'} ),
            'state'            => 'preflight',
            'session_type'     => $Whostmgr::Transfers::Session::Constants::SESSION_TYPES{'RemoteRoot'},
        },
        'queue'   => { map { $_ => 0 } @Whostmgr::Transfers::Session::Constants::QUEUES },
        'options' => {
            'unrestricted'          => ( $opts->{'unrestricted_restore'}  ? 1 : 0 ),
            'skipres'               => ( $opts->{'copy_reseller_privs'}   ? 1 : 0 ),
            'uncompressed'          => ( $opts->{'compressed'}            ? 0 : 1 ),
            'ssl'                   => ( $opts->{'unencrypted'}           ? 0 : 1 ),
            'backups'               => ( $opts->{'use_backups'}           ? 1 : 0 ),
            'low_priority'          => ( $opts->{'low_priority'}          ? 1 : 0 ),
            'enable_custom_pkgacct' => ( $opts->{'enable_custom_pkgacct'} ? 1 : 0 ),
        },
        'remote' => {
            'can_stream'             => undef,
            'can_rsync'              => undef,
            'mysql_streaming_method' => undef,
            'type'                   => $opts->{'remote_server_type'},
            'sshhost'                => $opts->{'host'},
            'sshport'                => ( $opts->{'port'} || '22' ),
            'sship'                  => $ip,
        }
    };

    return ( 1, $new_session_data );
}

my $locale;

sub _locale {

    return ( $locale ||= Cpanel::Locale->get_handle() );
}

1;
