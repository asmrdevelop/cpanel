package Whostmgr::API::1::Cpanel;

# cpanel - Whostmgr/API/1/Cpanel.pm                Copyright 2022 cPanel, L.L.C.
#                                                           All rights reserved.
# copyright@cpanel.net                                         http://cpanel.net
# This code is subject to the cPanel license. Unauthorized copying is prohibited

use cPstrict;

=encoding utf-8

=head1 NAME

Whostmgr::API::1::Cpanel

=head1 DESCRIPTION

This module implements logic for general upkeep of cPanel & WHM.

=cut

#----------------------------------------------------------------------

use Try::Tiny;

use Cpanel::LoadModule      ();
use Whostmgr::API::1::Utils ();
use Whostmgr::Authz         ();

use constant NEEDS_ROLE => {
    get_available_profiles               => undef,
    get_current_profile                  => undef,
    PRIVATE_write_uniqueness_token       => undef,
    get_tweaksetting                     => undef,
    is_role_enabled                      => undef,
    restore_config_from_file             => undef,
    restore_config_from_upload           => undef,
    set_tweaksetting                     => undef,
    start_profile_activation             => undef,
    start_cpanel_update                  => undef,
    systemloadavg                        => undef,
    version                              => undef,
    list_user_child_nodes                => undef,
    link_server_node_with_api_token      => undef,
    list_linked_server_nodes             => undef,
    get_linked_server_node               => undef,
    update_linked_server_node            => undef,
    unlink_server_node                   => undef,
    get_server_node_status               => undef,
    uapi_cpanel                          => undef,
    execute_remote_whmapi1_with_password => undef,
    force_dedistribution_from_node       => undef,

    PRIVATE_list_accounts_distributed_to_child_node => undef,

    PRIVATE_set_as_child_node   => undef,
    PRIVATE_unset_as_child_node => undef,
};

# As of v88 we only care about the truthiness of values in this hash;
# however, it’s left this way in anticipation of needing to whitelist
# specific functions within a given API module.
#
my %_uapi_cpanel_reduced_privs_whitelist = ( 'StatsBar' => { 'get_stats' => 1 } );

=head1 FUNCTIONS

=cut

#----------------------------------------------------------------------

sub version {
    my ( undef, $metadata ) = @_;

    require Cpanel::Version::Full;

    my $version = Cpanel::Version::Full::getversion();
    if ( !defined $version ) {
        $metadata->{'result'} = 0;
        $metadata->{'reason'} = 'Unable to determine version.';
    }
    $metadata->{'result'} = 1;
    $metadata->{'reason'} = 'OK';
    return { 'version' => $version };
}

sub systemloadavg {
    my ( undef, $metadata ) = @_;
    require Cpanel::Sys::Load;

    my %rs;
    ( $rs{'one'}, $rs{'five'}, $rs{'fifteen'} ) = Cpanel::Sys::Load::getloadavg($Cpanel::Sys::Load::ForceFloat);
    $metadata->{'result'} = 1;
    $metadata->{'reason'} = 'OK';
    return \%rs;
}

sub _tweaksetting_module_exists {
    my ($module) = @_;
    require Whostmgr::TweakSettings;

    return if !defined $module;
    return if $module !~ m/^[a-z0-9]+$/i;

    return Whostmgr::TweakSettings::get_conf($module);
}

sub _tweaksetting_key_is_safe {
    my ($key) = @_;
    return if !defined $key;

    return $key !~ tr{_a-zA-Z0-9-}{}c;
}

sub _tweaksetting_args_are_ok {
    my ( $args, $metadata ) = @_;

    my $conf;
    if ( !( $conf = _tweaksetting_module_exists( $args->{'module'} ) ) ) {
        $metadata->{'result'} = 0;
        $metadata->{'reason'} = 'Invalid tweaksetting module';
        return;
    }

    if ( !_tweaksetting_key_is_safe( $args->{'key'} ) || !exists $conf->{ $args->{'key'} } ) {
        $metadata->{'result'} = 0;
        $metadata->{'reason'} = 'Invalid tweaksetting key';
        return;
    }

    return 1;
}

sub _get_tweaksetting {
    my ( $module, $key, $value_ref ) = @_;
    require Cpanel::Validate::FilesystemNodeName;
    Cpanel::Validate::FilesystemNodeName::validate_or_die($module);

    my $namespace = "Whostmgr::TweakSettings::Configure::$module";

    Cpanel::LoadModule::load_perl_module($namespace);

    my $configure_object = $namespace->new();
    my $conf             = $configure_object->get_conf();
    return if !$conf;

    $$value_ref = $conf->{$key};
    return 1;
}

sub get_tweaksetting {
    my ( $args, $metadata ) = @_;
    $args->{'module'} ||= 'Main';
    return if !_tweaksetting_args_are_ok( $args, $metadata );

    my $value;
    if ( !_get_tweaksetting( $args->{'module'}, $args->{'key'}, \$value ) ) {
        $metadata->{'result'} = 0;
        $metadata->{'reason'} = 'Unable to get tweaksetting';
        return;
    }

    $metadata->{'result'} = 1;
    $metadata->{'reason'} = 'OK';

    my $tweaksetting = {
        'key' => $args->{'key'},
    };

    if ( defined $value ) {
        $tweaksetting->{'value'} = $value;
    }

    return { 'tweaksetting' => $tweaksetting };
}

sub restore_config_from_upload {
    my ( $args, $metadata ) = @_;

    require Cpanel::Form;

    my $uploaded_files_ar = Cpanel::Form::get_uploaded_files_ar($args);
    my $path              = $uploaded_files_ar->[0]->{'temppath'};

    if ( !$path ) {
        die Cpanel::Exception::create( 'MissingParameter', "Upload a configuration file with “multipart/form-data” encoding for this function." );
    }
    my $module = Whostmgr::API::1::Utils::get_length_required_argument( $args, 'module' );

    if ( _restore_config( $module, $path ) ) {
        Whostmgr::API::1::Utils::set_metadata_ok($metadata);
    }

    return;
}

sub restore_config_from_file {
    my ( $args, $metadata ) = @_;

    my $module = Whostmgr::API::1::Utils::get_length_required_argument( $args, 'module' );
    my $path   = Whostmgr::API::1::Utils::get_length_required_argument( $args, 'path' );

    if ( _restore_config( $module, $path ) ) {
        Whostmgr::API::1::Utils::set_metadata_ok($metadata);
    }

    return;
}

sub _restore_config {
    my ( $module, $path ) = @_;

    require Cpanel::Autodie;
    require Cpanel::JSON;
    my $key_value_pairs;
    Cpanel::Autodie::open( my $fh, '<', $path );
    if ( -B $path || -z _ ) {

        # Binary data or empty, fall through and error
    }
    elsif ( Cpanel::JSON::looks_like_json($fh) ) {
        require Cpanel::AdminBin::Serializer;
        seek( $fh, 0, 0 );
        $key_value_pairs = Cpanel::AdminBin::Serializer::LoadFile($fh);
    }
    else {
        require Cpanel::Config::LoadConfig;
        require Cpanel::LoadFile;
        my $rawdata = Cpanel::LoadFile::load($path);

        # cpanel.config is = seperated
        # wwwacct.conf is space seperated

        my $delimiter;
        my $passed_simple_validation = 0;
        if ( index( $rawdata, '=' ) == -1 ) {
            $delimiter                = '[ \t]+';
            $passed_simple_validation = 1 if $rawdata =~ m/(?:\A|\n)[^\t \n]+[ \t]*[^\t \n]*(?:\z|\n+)/g;
        }
        else {
            $delimiter                = '=';
            $passed_simple_validation = 1 if $rawdata =~ m/(?:\A|\n)[^\n=]+=[^\n=]*(?:\z|\n+)/g;
        }

        if ($passed_simple_validation) {
            $key_value_pairs = Cpanel::Config::LoadConfig::loadConfig( $path, (undef) x 5, { 'delimiter' => $delimiter, 'nocache' => 1, 'allow_undef_values' => 1 } );
        }

    }

    if ( !$key_value_pairs || !scalar keys %$key_value_pairs ) {
        require Cpanel::Exception;
        die Cpanel::Exception::create( 'InvalidParameter', 'The file located in the “[_1]” directory does not contain JSON, space-separated key and value pairs on newlines, or equals sign-separated key and value pairs on newlines.', [$path] );

    }

    require Whostmgr::TweakSettings;
    my $result = Whostmgr::TweakSettings::apply_module_settings( $module, $key_value_pairs );

    return $result->{'modified'};
}

sub set_tweaksetting {
    my ( $args, $metadata ) = @_;
    $args->{'module'} ||= 'Main';
    return if !_tweaksetting_args_are_ok( $args, $metadata );
    require Whostmgr::TweakSettings;

    my $result         = Whostmgr::TweakSettings::apply_module_settings( $args->{'module'}, { $args->{'key'} => $args->{'value'} } );
    my $new_value_for  = $result->{'config_hr'};
    my $reject_reasons = $result->{'reject_reasons'};
    my $rejected       = $result->{'rejects'};

    if ( !$result->{'modified'} ) {
        $metadata->{'result'} = 0;
        $metadata->{'reason'} = 'Error encountered applying new setting.  Changes were not saved.';
        return;
    }

    if ( ( !exists $new_value_for->{ $args->{'key'} } || ( $new_value_for->{ $args->{'key'} } || 0 ) ne ( $args->{'value'} || 0 ) ) && exists $rejected->{ $args->{'key'} } ) {
        $metadata->{'result'} = 0;
        $metadata->{'reason'} = exists $reject_reasons->{ $args->{'key'} } ? $reject_reasons->{ $args->{'key'} } : "Invalid value for $args->{'key'}; The setting will not be updated.";
        return;
    }

    my $value = $new_value_for->{ $args->{'key'} };
    $metadata->{'result'} = 1;
    $metadata->{'reason'} = 'OK';
    return;
}

sub _get_role_data {
    my ($role) = @_;
    Cpanel::LoadModule::load_perl_module($role);
    my $module = substr( $role, rindex( $role, ":" ) + 1 );
    return { module => $module, name => $role->_NAME()->to_string(), description => $role->_DESCRIPTION()->to_string() };
}

sub _is_role_available {
    my ($role) = @_;
    Cpanel::LoadModule::load_perl_module($role);
    return $role->is_available();
}

sub _translate_roles {
    my ($roles) = @_;
    return [ map { _get_role_data($_) } grep { _is_role_available($_) } @$roles ];
}

sub get_current_profile {

    my ( $args, $metadata ) = @_;
    $args->{'module'} ||= 'Main';

    require Cpanel::Server::Type::Profile;
    my $META              = Cpanel::Server::Type::Profile::get_meta_with_descriptions();
    my $current           = Cpanel::Server::Type::Profile::get_current_profile();
    my $disabled_roles_ar = Cpanel::Server::Type::Profile::get_disabled_roles_for_profile($current);

    my $ret_val = {
        code           => $current,
        name           => $META->{$current}{name}->to_string(),
        description    => $META->{$current}{description}->to_string(),
        experimental   => $META->{$current}{experimental} ? 1 : 0,
        enabled_roles  => _translate_roles( $META->{$current}{enabled_roles} ),
        disabled_roles => _translate_roles($disabled_roles_ar),
        optional_roles => _translate_roles( $META->{$current}{optional_roles} )
    };

    $metadata->{'result'} = 1;
    $metadata->{'reason'} = 'OK';

    return $ret_val;
}

sub PRIVATE_write_uniqueness_token ( $args, $metadata, @ ) {
    require Cpanel::LinkedNode::UniquenessToken;

    my $token = Whostmgr::API::1::Utils::get_length_required_argument( $args, 'token' );
    die 'bad token' if $token !~ m<\A[0-9a-zA-Z_]+\z>;

    my $created = Cpanel::LinkedNode::UniquenessToken::write($token);

    $metadata->set_ok();

    return { payload => $created ? 1 : 0 };
}

sub get_available_profiles {

    my ( $args, $metadata ) = @_;

    require Cpanel::Server::Type::Profile;
    my $META = Cpanel::Server::Type::Profile::get_meta_with_descriptions();

    require Cpanel::Server::Type;
    require Cpanel::Server::Type::Profile::Constants;
    my $product_type = Cpanel::Server::Type::get_producttype();
    my $STANDARD     = Cpanel::Server::Type::Profile::Constants::STANDARD();

    my @profiles;

    if ( $product_type ne $STANDARD ) {
        push @profiles, _get_profile_attributes_for_code( $META, $product_type );
    }
    else {

        my $standard_disabled_roles_ar = Cpanel::Server::Type::Profile::get_disabled_roles_for_profile($STANDARD);

        # Always put the STANDARD profile first
        my @profile_list = (
            $STANDARD,
            grep { $_ ne $STANDARD } sort {
                if ( $META->{$a}{experimental} eq $META->{$b}{experimental} ) {
                    return $a cmp $b;
                }
                return $META->{$a}{experimental} cmp $META->{$b}{experimental};
            } keys %$META
        );
        foreach my $code (@profile_list) {
            push @profiles, _get_profile_attributes_for_code( $META, $code );
        }

    }

    $metadata->{'result'} = 1;
    $metadata->{'reason'} = 'OK';

    return { 'profiles' => \@profiles };
}

sub _get_profile_attributes_for_code {

    my ( $META, $code ) = @_;

    my $disabled_roles_ar = Cpanel::Server::Type::Profile::get_disabled_roles_for_profile($code);

    return {
        code           => $code,
        name           => $META->{$code}{name}->to_string(),
        description    => $META->{$code}{description}->to_string(),
        experimental   => $META->{$code}{experimental} ? 1 : 0,
        enabled_roles  => _translate_roles( $META->{$code}{enabled_roles} ),
        disabled_roles => _translate_roles($disabled_roles_ar),
        optional_roles => _translate_roles( $META->{$code}{optional_roles} )
    };

}

sub start_profile_activation {

    my ( $args, $metadata ) = @_;
    $args->{'module'} ||= 'Main';

    require Whostmgr::API::1::Utils;
    Whostmgr::API::1::Utils::get_length_required_argument( $args, 'code' );

    my $optional = {};

    if ( $args->{'optional'} ) {

        require Cpanel::JSON;
        $optional = Cpanel::JSON::Load( $args->{'optional'} );

        for ( keys %$optional ) {
            $optional->{"Cpanel::Server::Type::Role::$_"} = delete $optional->{$_};
        }

    }

    require Cpanel::Server::Type::Change;
    my $log_id = Cpanel::Server::Type::Change::start_profile_activation( $args->{code}, $optional );

    Whostmgr::API::1::Utils::set_metadata_ok($metadata);

    return { log_id => $log_id };
}

sub start_cpanel_update ( $args, $metadata, @ ) {
    require Cpanel::Update::Start;

    my %ret;
    @ret{ 'pid', 'log_path', 'is_new' } = Cpanel::Update::Start::start( %{$args}{'mode'} );

    $ret{'is_new'} ||= 0;

    $metadata->set_ok();

    return \%ret;
}

sub is_role_enabled {

    my ( $args, $metadata ) = @_;
    $args->{'module'} ||= 'Main';

    require Whostmgr::API::1::Utils;
    Whostmgr::API::1::Utils::get_length_required_argument( $args, 'role' );

    require Cpanel::Server::Type::Profile::Roles;
    my $enabled = eval { Cpanel::Server::Type::Profile::Roles::is_role_enabled( $args->{'role'} ) };

    if ($@) {
        $metadata->{'result'} = 0;
        $metadata->{'reason'} = $@;
    }
    else {
        $metadata->{'result'} = 1;
        $metadata->{'reason'} = 'OK';
    }

    return { enabled => $enabled ? "1" : "0" };
}

sub list_user_child_nodes ( $args, $metadata, @ ) {
    require Cpanel::LinkedNode::List;

    my $results_ar = Cpanel::LinkedNode::List::list_user_worker_nodes();

    # Whitelist the hashrefs’ contents in case the backend function
    # adds anything else (e.g., the API token) later.
    %$_ = %{$_}{ 'user', 'alias', 'type' } for @$results_ar;

    $metadata->set_ok();

    return { payload => $results_ar };
}

sub link_server_node_with_api_token {

    my ( $args, $metadata ) = @_;

    Whostmgr::API::1::Utils::get_length_required_argument( $args, 'alias' );
    Whostmgr::API::1::Utils::get_length_required_argument( $args, 'username' );
    Whostmgr::API::1::Utils::get_length_required_argument( $args, 'hostname' );
    Whostmgr::API::1::Utils::get_length_required_argument( $args, 'api_token' );

    require Cpanel::LinkedNode;

    my $result;

    local $@;
    my $ok = eval {
        Cpanel::LinkedNode::link_server_node_with_api_token( %$args, capabilities => [qw(Mail)] );
        1;
    };

    if ( !$ok ) {
        my $err = $@;

        $metadata->set_not_ok($err);

        require Whostmgr::API::1::Utils::TLS;
        require Cpanel::Services::Ports;

        $result = Whostmgr::API::1::Utils::TLS::create_remoteapi_typed_error_if_tls(
            $err,
            $args->{'hostname'},
            $Cpanel::Services::Ports::SERVICE{'whostmgrs'},
        );
    }
    else {
        $metadata->set_ok();
    }

    return $result;
}

sub list_linked_server_nodes {

    my ( $args, $metadata ) = @_;

    require Cpanel::LinkedNode::Index::Read;
    my $nodes_hr = Cpanel::LinkedNode::Index::Read::get();

    my @payload = map { $_->TO_JSON() } values %$nodes_hr;
    delete $_->{api_token} for @payload;

    Whostmgr::API::1::Utils::set_metadata_ok($metadata);

    return { payload => \@payload };
}

sub get_linked_server_node {

    my ( $args, $metadata ) = @_;

    my $alias = Whostmgr::API::1::Utils::get_length_required_argument( $args, 'alias' );

    require Cpanel::LinkedNode;
    my $node_obj = Cpanel::LinkedNode::get_linked_server_node( alias => $alias );

    Whostmgr::API::1::Utils::set_metadata_ok($metadata);

    my $ret_val = $node_obj->TO_JSON();
    delete $ret_val->{api_token};

    return $ret_val;
}

sub update_linked_server_node {

    my ( $args, $metadata ) = @_;

    Whostmgr::API::1::Utils::get_length_required_argument( $args, 'alias' );

    require Cpanel::LinkedNode;
    Cpanel::LinkedNode::update_linked_server_node( %$args, capabilities => [qw(Mail)] );

    Whostmgr::API::1::Utils::set_metadata_ok($metadata);

    return;
}

sub unlink_server_node {

    my ( $args, $metadata ) = @_;

    my $alias            = Whostmgr::API::1::Utils::get_length_required_argument( $args, 'alias' );
    my $handle_api_token = $args->{'handle_api_token'};

    require Cpanel::LinkedNode;
    my $deleted = do {
        local $SIG{'__WARN__'} = sub { $metadata->add_warning(shift) };

        Cpanel::LinkedNode::unlink_server_node(
            alias            => $alias,
            handle_api_token => $handle_api_token,
        );
    };

    my $ret_val = $deleted->TO_JSON();

    # The API token is removed from the output for security reasons
    delete $ret_val->{api_token};

    Whostmgr::API::1::Utils::set_metadata_ok($metadata);

    return $ret_val;
}

sub get_server_node_status {

    my ( $args, $metadata ) = @_;

    my $host      = Whostmgr::API::1::Utils::get_length_required_argument( $args, 'hostname' );
    my $user      = Whostmgr::API::1::Utils::get_length_required_argument( $args, 'username' );
    my $api_token = Whostmgr::API::1::Utils::get_length_required_argument( $args, 'api_token' );

    require Cpanel::LinkedNode;
    my $remote_status = Cpanel::LinkedNode::get_server_node_status(
        hostname              => $host,
        username              => $user,
        api_token             => $api_token,
        skip_tls_verification => $args->{skip_tls_verification}
    );

    Whostmgr::API::1::Utils::set_metadata_ok($metadata);

    return $remote_status;
}

sub _extract_remote_whmapi1_args ($args) {
    my @names = Whostmgr::API::1::Utils::get_length_arguments( $args, 'parameter_name' );

    my @values = Whostmgr::API::1::Utils::get_arguments( $args, 'parameter_value' );

    if ( @names != @values ) {
        die "mismatch names/values";
    }

    my %remote_args;

    for my $n ( 0 .. $#names ) {
        my $name = $names[$n];

        if ( exists $remote_args{$name} ) {
            if ( 'ARRAY' ne ref $remote_args{$name} ) {
                $remote_args{$name} = [ $remote_args{$name} ];
            }
            push @{ $remote_args{$name} }, $values[$n];
        }
        else {
            $remote_args{$name} = $values[$n];
        }
    }

    return \%remote_args;
}

sub _reject_multi_level_proxy ( $args, $metadata ) {
    my $this_api_function = $metadata->{'command'};

    my $is_multi_proxy = $args->{'function'} eq $this_api_function;

    if ( $args->{'function'} eq 'batch' ) {

        # Strictly speaking, someone could nest a proxy call within a batch
        # within another batch. We don’t prevent that because it’ a lot of
        # work to detect for what would be a pretty contorted way to shoot
        # oneself in the foot.

        my @commands = Whostmgr::API::1::Utils::get_arguments( $args, 'parameter_value' );

        $is_multi_proxy = grep { m<\A$this_api_function>x } @commands;
    }

    if ($is_multi_proxy) {
        die 'Multi-level proxying is unsupported.';
    }

    return;
}

sub execute_remote_whmapi1_with_password ( $args, $metadata, @ ) {
    for my $arg (qw( host username password function )) {
        Whostmgr::API::1::Utils::get_length_required_argument( $args, $arg );
    }

    _reject_multi_level_proxy( $args, $metadata );

    my $tls_verification = $args->{'tls_verification'};

    my $verify_tls = !length $tls_verification;
    $verify_tls ||= $tls_verification eq 'on';

    if ( !$verify_tls && $tls_verification ne 'off' ) {
        die "bad “tls_verification”: “$tls_verification”";
    }

    my $remote_args_hr = _extract_remote_whmapi1_args($args);

    require Cpanel::RemoteAPI::WHM;
    require Cpanel::TempFH;
    require Cpanel::RedirectFH;

    my $api = Cpanel::RemoteAPI::WHM->new_from_password(
        @{$args}{ 'host', 'username', 'password' },
    );

    $api->disable_tls_verify() if !$verify_tls;

    my $tfh = Cpanel::TempFH::create();

    my $result;

    local $@;
    my $ok = do {
        my $redir = Cpanel::RedirectFH->new( \*STDERR => $tfh );

        eval {
            $result = $api->request_whmapi1( $args->{'function'}, $remote_args_hr );
            1;
        };
    };

    if ( !$ok ) {
        my $err = $@;

        $metadata->set_not_ok($err);

        require Whostmgr::API::1::Utils::TLS;
        require Cpanel::Services::Ports;

        $result = Whostmgr::API::1::Utils::TLS::create_remoteapi_typed_error_if_tls(
            $err,
            $args->{'host'},
            $Cpanel::Services::Ports::SERVICE{'whostmgrs'},
        );
    }
    else {
        for my $msg_ar ( @{ $result->get_nonfatal_messages() } ) {
            if ( $msg_ar->[0] eq 'warn' ) {
                $metadata->add_warning( $msg_ar->[1] );
            }
            elsif ( $msg_ar->[0] eq 'info' ) {
                $metadata->add_message( $msg_ar->[1] );
            }
            else {

                # Shouldn’t happen unless there’s an update to the API
                # to introduce a new type of nonfatal message.
                warn "Untranslatable message from $args->{'host'}: @$msg_ar";
            }
        }

        if ( my $err = $result->get_error() ) {
            $metadata->set_not_ok($err);
        }
        else {
            $metadata->set_ok();
        }

        $result = $result->get_raw_data();
    }

    if ( -s $tfh ) {
        sysseek $tfh, 0, 0;
        require Cpanel::LoadFile::ReadFast;

        Cpanel::LoadFile::ReadFast::read_all_fast( $tfh, my $buf );
        $metadata->add_warning($buf);
    }

    return $result;
}

sub uapi_cpanel {
    my ( $args, $metadata ) = @_;

    my $cpanel_user     = Whostmgr::API::1::Utils::get_length_required_argument( $args, 'cpanel.user' );
    my $cpanel_module   = Whostmgr::API::1::Utils::get_length_required_argument( $args, 'cpanel.module' );
    my $cpanel_function = Whostmgr::API::1::Utils::get_length_required_argument( $args, 'cpanel.function' );
    delete $args->{'cpanel.user'};
    delete $args->{'cpanel.module'};
    delete $args->{'cpanel.function'};
    Whostmgr::Authz::verify_account_access($cpanel_user);

    local %ENV;
    require Cpanel;
    require Cpanel::API;

    my $data;
    if ( _module_is_unshipped($cpanel_module) ) {
        require Cpanel::AccessIds;
        require Cpanel::XML;
        require Cpanel::JSON;
        $data = Cpanel::AccessIds::do_as_user(
            $cpanel_user,
            sub {
                my $form_ref = {%$args};
                $form_ref->{'api.module'}   = $cpanel_module;
                $form_ref->{'api.function'} = $cpanel_function;
                local $ENV{'REMOTE_USER'} = $cpanel_user;
                my ( $serialized_results_length, $serialized_results_ref, $internal_error, $internal_error_reason ) = Cpanel::XML::cpanel_exec_fast( $form_ref, { 'uapi' => 1, 'json' => 1, } );
                if ($internal_error) {
                    return {
                        'messages' => undef,
                        'errors'   => [$internal_error_reason],
                        'status'   => 0,
                        'data'     => undef,
                    };
                }
                return Cpanel::JSON::Load($$serialized_results_ref);
            }
        );
    }
    elsif ( _module_function_is_whitelisted_for_reduced_privs( $cpanel_module, $cpanel_function ) ) {
        require Cpanel::AccessIds::ReducedPrivileges;
        $data = Cpanel::AccessIds::ReducedPrivileges::call_as_user( $cpanel_user, sub { return _run_uapi_for_public( $cpanel_user, $cpanel_module, $cpanel_function, $args ) } );
    }
    else {
        require Cpanel::AccessIds;
        $data = Cpanel::AccessIds::do_as_user( $cpanel_user, sub { return _run_uapi_for_public( $cpanel_user, $cpanel_module, $cpanel_function, $args ) } );
    }
    Whostmgr::API::1::Utils::set_metadata_ok($metadata);
    return { 'uapi' => $data };
}

#----------------------------------------------------------------------

=head1 PRIVATE APIS

=head2 PRIVATE_list_accounts_distributed_to_child_node

Takes in an C<alias> and returns C<{ payload => \@items }>, where
each member of @items is a hashref of:

=over

=item * C<username> - The account’s name.

=back

=cut

sub PRIVATE_list_accounts_distributed_to_child_node ( $args, $metadata, @ ) {
    my $alias = Whostmgr::API::1::Utils::get_length_required_argument( $args, 'alias' );

    require Cpanel::LinkedNode;

    my @payload = Cpanel::LinkedNode::list_accounts_distributed_to_child_node($alias);

    $_ = { username => $_ } for @payload;

    $metadata->set_ok();

    return { payload => \@payload };
}

#----------------------------------------------------------------------

sub _run_uapi_for_public {
    my ( $cpanel_user, $cpanel_module, $cpanel_function, $args ) = @_;

    require Cpanel::Security::Authz;
    Cpanel::Security::Authz::verify_not_root();

    local $Cpanel::App::appname = 'cpanel';
    local $Cpanel::user;
    local $Cpanel::homedir;
    local $Cpanel::authuser = $cpanel_user;
    Cpanel::initcp($cpanel_user);

    if ( $INC{"Cpanel/API/$cpanel_module.pm"} && $_uapi_cpanel_reduced_privs_whitelist{$cpanel_module} ) {

        # If we ever exapand the whitelist we will need to implement
        # a _clear_cache function for each UAPI module added or
        # refactor this.
        "Cpanel::API::$cpanel_module"->_clear_cache();
    }

    return Cpanel::API::execute( $cpanel_module, $cpanel_function, $args )->for_public();
}

sub _module_is_unshipped {
    my ($module) = @_;
    return $module eq 'Email' ? 1 : 0;
}

sub _module_function_is_whitelisted_for_reduced_privs {
    my ( $module, $function ) = @_;

    # WARNING: Only add functions to this list that are safe to run with
    # ReducedPrivileges.  If the function ever accesses an sqlite database
    # or executes a process it is likely unsafe to add here
    return $_uapi_cpanel_reduced_privs_whitelist{$module}{$function} ? 1 : 0;

}

sub force_dedistribution_from_node ( $args, $metadata, @ ) {
    state @LOG_MESSAGE_PIECES = ( 'type', 'contents', 'indent' );

    my $worker_alias = Whostmgr::API::1::Utils::get_length_required_argument( $args, 'node_alias' );
    my @usernames    = Whostmgr::API::1::Utils::get_length_required_arguments( $args, 'user' );

    require Cpanel::LinkedNode::Convert;
    require Cpanel::Output::Callback;
    require Cpanel::TaskRunner::Icons;

    my @log_messages;

    my $output_obj = Cpanel::Output::Callback->new(
        on_render => sub ($msg_hr) {
            my %msg = %{$msg_hr}{@LOG_MESSAGE_PIECES};

            $msg{'contents'} = Cpanel::TaskRunner::Icons::strip_icon( $msg{'contents'} );

            push @log_messages, \%msg;
        },
    );

    my $results_ar = Cpanel::LinkedNode::Convert::force_dedistribution_from_node( $output_obj, $worker_alias, \@usernames );

    $metadata->set_ok();

    # Since for v94 we only have 1 workload there’s no point in
    # exposing this information to users.
    delete $_->{'workloads'} for @$results_ar;

    return {

        # We need this here so that clients don’t reduce “log” out
        # from the response payload. (cf. reduce_whm1_list_data())
        # As of v94, though, all it contains is the same usernames
        # that were passed in.
        user_info => $results_ar,

        log => \@log_messages,
    };
}

=head2 PRIVATE_set_as_child_node()

Wraps L<Cpanel::LinkedNode::ChildNode>’s C<set()>.

=cut

sub PRIVATE_set_as_child_node ( $args, $metadata, @ ) {
    require Cpanel::LinkedNode::ChildNode;

    Cpanel::LinkedNode::ChildNode::set();

    $metadata->set_ok();

    return;
}

=head2 PRIVATE_unset_as_child_node()

Wraps L<Cpanel::LinkedNode::ChildNode>’s C<unset()>. Returns
C<{ was_set =E<gt> $yn }>, where C<$yn> is C<unset()>’s return.

=cut

sub PRIVATE_unset_as_child_node ( $args, $metadata, @ ) {
    require Cpanel::LinkedNode::ChildNode;

    my $was = Cpanel::LinkedNode::ChildNode::unset();

    $metadata->set_ok();

    return { was_set => $was };
}

1;
