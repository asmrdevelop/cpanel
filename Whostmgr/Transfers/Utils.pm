package Whostmgr::Transfers::Utils;

# cpanel - Whostmgr/Transfers/Utils.pm             Copyright 2022 cPanel, L.L.C.
#                                                           All rights reserved.
# copyright@cpanel.net                                         http://cpanel.net
# This code is subject to the cPanel license. Unauthorized copying is prohibited

use cPstrict;

our $VERSION = '2.2';

use parent 'Cpanel::Destruct::DestroyDetector';

use Carp ();

use Cpanel::AccountProxy::Storage  ();
use Cpanel::PwCache                ();
use Cpanel::LoadModule             ();
use Cpanel::Config::LoadCpUserFile ();
use Cpanel::Output::Legacy         ();
use Cpanel::Exception              ();
use Cpanel::Locale                 ();
use Cpanel::DB::Utils              ();
use Cpanel::SafeRun::Object        ();

use Cpanel::Validate::Hostname           ();
use Cpanel::Validate::Username           ();
use Cpanel::Validate::Domain             ();
use Cpanel::Validate::FilesystemNodeName ();
use Cpanel::Validate::IP                 ();
use Cpanel::Validate::LineTerminatorFree ();

use Cpanel::LinkedNode::Alias::Constants ();    # PPI USE OK - Constants
use Cpanel::LinkedNode::Worker::GetAll   ();
use Cpanel::LinkedNode::Worker::Storage  ();

use Whostmgr::Transfers::AccountRestoration::Mutex ();
use Whostmgr::Accounts::SuspensionData             ();
use Whostmgr::Transfers::ArchiveManager::Validate  ();
use Whostmgr::Transfers::Session::Config           ();
use Whostmgr::Transfers::Utils::LinkedNodes        ();
use Whostmgr::Transfers::Utils::Logger             ();
use Whostmgr::Transfers::Utils::WorkerNodesObj     ();

use Try::Tiny;

my $cpanel_config_ref;

sub new {
    my ( $class, %OPTS ) = @_;

    return bless {
        'unrestricted_restore' => ( $OPTS{'unrestricted_restore'} && $OPTS{'unrestricted_restore'} == $Whostmgr::Transfers::Session::Config::UNRESTRICTED ) ? 1 : 0,
        '_pid'                 => $$,
        'skipped_items'        => [],
        'dangerous_items'      => [],
        'altered_items'        => [],
        'warnings'             => [],
        'messages'             => [],
        'restored_domains'     => [],
        'flags'                => ( $OPTS{'flags'}      || {} ),
        'output_obj'           => ( $OPTS{'output_obj'} || Cpanel::Output::Legacy->new() ),

    }, $class;

}

sub set_archive_manager {
    my ( $self, $archive_manager_obj ) = @_;

    $self->{'_archive_manager'} = $archive_manager_obj;

    local ( $@, $! );
    require Scalar::Util;

    # Weaken this reference in order to avoid a circular reference
    # between $self and $archive_manager_obj (which itself stores
    # a reference to $self).
    Scalar::Util::weaken( $self->{'_archive_manager'} );

    return 1;
}

sub start_module {
    my ( $self, $module, $custom ) = @_;

    $self->end_action() if $self->{'_in_action'};

    $self->end_module() if $self->{'_in_module'};

    $self->{'_in_module'} = 1;

    $self->{'_current_module'} = $module;

    $self->new_control_message( 'start_module', $custom ? "$module (CUSTOM)" : $module );

    return 1;
}

sub end_module {
    my ($self) = @_;

    $self->end_action() if $self->{'_in_action'};

    return if !$self->{'_in_module'};

    $self->{'_in_module'} = 0;

    $self->new_control_message( 'end_module', $self->{'_current_module'} );

    return 1;
}

sub start_action {
    my ( $self, $action ) = @_;

    $self->end_action() if $self->{'_in_action'};

    $self->{'_in_action'} = 1;

    my $module_action = ( $action || $self->{'_current_module'} || q{} );

    $self->{'_current_action'} = $module_action;

    $self->new_control_message( 'start_action', $module_action );

    return 1;
}

sub end_action {
    my ($self) = @_;

    return if !$self->{'_in_action'};

    $self->{'_in_action'} = 0;

    my $module_action = $self->{'_current_action'} || q{};

    $self->new_control_message( 'end_action', $module_action );

    return 1;
}

sub logger ($self) {
    return $self->{'_logger'} ||= Whostmgr::Transfers::Utils::Logger->new( $self->{'output_obj'} );
}

sub out ( $self, @args ) {
    return $self->logger()->out(@args);
}

sub debug {
    my ( $self, @args ) = @_;

    if ( ref $args[0] && ref $args[0] eq 'ARRAY' ) {
        @args = @{ $args[0] };
    }

    return $self->{'output_obj'}->debug( { 'msg' => \@args, 'time' => time() } );
}

sub warn ( $self, @args ) {
    my @warn_args;

    if ( ref $args[0] && ref $args[0] eq 'ARRAY' ) {
        @warn_args = @{ $args[0] };
    }
    else {
        @warn_args = @args;
    }

    $self->add_warning(@warn_args);

    return $self->logger()->warn(@args);
}

sub new_control_message {
    my ( $self, $action, @message ) = @_;
    return $self->{'output_obj'}->message( 'control', { 'time' => time(), 'action' => $action, 'msg' => \@message } );
}

sub new_message {

    #my ( $self, $message_type, $data ) = @_;
    return $_[0]->{'output_obj'}->message( $_[1], $_[2] );
}

sub is_restorable_domain {
    my ( $self, $domain ) = @_;

    my @domains = $self->domains();

    return grep { /\A\Q$domain\E\z/i } @domains;
}

# add and get restored domains for tests
sub add_restored_domain {

    #my ( $self, $domain ) = @_;

    push @{ $_[0]->{'restored_domains'} }, $_[1];

    return;
}

# add and get restored domains for tests
sub get_restored_domains {
    my ($self) = @_;

    return @{ $self->{'restored_domains'} } || ();
}

sub get_ip_address_from_cpuser_data {
    my ($self) = @_;

    my ( $status, $cpuser_data ) = $self->{'_archive_manager'}->get_raw_cpuser_data_from_archive();
    if ( !$status ) {
        $self->warn($cpuser_data);
        return;
    }

    my $ip = $cpuser_data->{'IP'};
    return if !$ip;

    return if !Cpanel::Validate::IP::is_valid_ip($ip);

    return $ip;
}

sub get_demo_mode {
    my ($self) = @_;

    return $self->{'_DEMO'} if exists $self->{'_DEMO'};

    my ( $status, $cpuser_data ) = $self->{'_archive_manager'}->get_raw_cpuser_data_from_archive();
    if ( !$status ) {
        $self->warn($cpuser_data);
        return;
    }

    $self->{'_DEMO'} = exists $cpuser_data->{'DEMO'} ? $cpuser_data->{'DEMO'} : 0;

    return $self->{'_DEMO'};
}

sub is_unrestricted_restore {
    my ($self) = @_;

    return 1 if $self->{'unrestricted_restore'};
    return 0;
}

sub set_original_domains {
    my ( $self, $domains ) = @_;
    $self->{'_original_domains'} = $domains;
    return 1;
}

sub get_original_domains {
    my ($self) = @_;
    return $self->{'_original_domains'};
}

sub set_ns_records_for_zone {
    my ( $self, $zone, $nsrecords ) = @_;
    $self->{'_ns_records_for_zone'}{$zone} = $nsrecords;
    return 1;
}

sub get_ns_records_for_zone {
    my ( $self, $zone ) = @_;
    return $self->{'_ns_records_for_zone'}{$zone};
}

sub get_zones_with_ns_records {
    my ($self) = @_;
    return [ keys %{ $self->{'_ns_records_for_zone'} } ];
}

sub ensure_user_mysql_access ($self) {
    $self->{'_verified_mysql_access'} ||= do {
        my $username = $self->local_username();

        if ( Whostmgr::Accounts::SuspensionData->exists($username) ) {
            require Cpanel::ConfigFiles;
            $self->out( _locale()->maketext( '“[_1]” is a suspended account, but the system must access [asis,MySQL]/[asis,MariaDB] as this user. Because of this, the system will temporarily unsuspend “[_1]”’s local [asis,MySQL]/[asis,MariaDB] access.', $username ) );

            Cpanel::SafeRun::Object->new_or_die(
                program => "$Cpanel::ConfigFiles::CPANEL_ROOT/scripts/unsuspendmysqlusers",
                args    => [ '--local-only', $username ],
            );
        }

        1;
    };

    return;
}

# possibly TEMPORARY until I can figure out a better pattern for these
# Since validation was broken into another module, we need to keep track of skipped data too
sub set_cpuser_data {
    my ( $self, $cpuser_data, $skipped_cpuser_data ) = @_;

    return $self->{'_cpuser_data'} = [ $cpuser_data, $skipped_cpuser_data ];
}

*get_cpuser_data = *get_cached_cpuser_data;

sub get_cached_cpuser_data {
    my ($self) = @_;

    return @{ $self->{'_cpuser_data'} } if $self->{'_cpuser_data'};

    my ( $status, $cpuser_data, $skipped_cpuser_data ) = $self->_read_and_parse_cpuser_data_from_archive();

    if ( !$status ) {
        die( _locale()->maketext( "The system could not load the [asis,cPanel] user attributes file from the archive because of an error: [_1]", $cpuser_data ) );
    }

    # if this setting does not exist, explicitly set it to 0.
    $cpuser_data->{'UTF8MAILBOX'} = 0 if !$cpuser_data->{'UTF8MAILBOX'};

    $self->set_original_domains( $skipped_cpuser_data->{'DOMAINS'} );
    delete $skipped_cpuser_data->{'DOMAINS'};

    my $unvalidated_owner  = $cpuser_data->{'OWNER'};
    my $unvalidated_domain = $cpuser_data->{'DOMAIN'};

    if ( !$self->is_unrestricted_restore() ) {
        my $username = $self->local_username();
        ( $cpuser_data, $skipped_cpuser_data ) = Whostmgr::Transfers::ArchiveManager::Validate::validate_cpuser_data( $username, $cpuser_data );
    }

    my $err;
    try {
        Cpanel::Validate::Domain::valid_domainname_for_customer_or_die($unvalidated_domain);
    }
    catch {
        $err = $_;
    };

    if ($err) {
        die(
            _locale()->maketext(
                "The value “[_1]” for the “[_2]” key in the [asis,cPanel] user attributes file failed to validate because of an error: [_3]",
                $unvalidated_domain, 'DNS', Cpanel::Exception::get_string($err)
            )
        );
    }

    my $extractdir = $self->{'_archive_manager'}->trusted_archive_contents_dir();

    # We remove all node linkages from the cpuser file for now.
    # If we end up recreating those linkages, that’ll happen
    # near the end (with a fresh token created).
    my @all_cpuser = Cpanel::LinkedNode::Worker::GetAll::get_aliases_and_tokens_from_cpuser($cpuser_data);

    for my $worker_hr (@all_cpuser) {
        Cpanel::LinkedNode::Worker::Storage::unset( $cpuser_data, $worker_hr->{'worker_type'} );
    }

    $self->set_cpuser_data( $cpuser_data, $skipped_cpuser_data );

    $self->set_main_domain($unvalidated_domain);
    if (   $unvalidated_owner
        && Cpanel::Validate::Username::is_valid($unvalidated_owner)
        && !Cpanel::Validate::Username::reserved_username_check($unvalidated_owner) ) {
        $self->set_owner($unvalidated_owner);
    }
    else {
        $self->set_owner('root');
    }

    return ( $cpuser_data, $skipped_cpuser_data );
}

sub _read_and_parse_cpuser_data_from_archive {
    my ($self) = @_;

    if ( !$self->{'_archive_manager'}->archive_has_cpuser_data() ) {
        return ( 0, "The archive is missing cpuser data." );
    }

    my ( $status, $cpuser_data ) = $self->{'_archive_manager'}->get_raw_cpuser_data_from_archive();
    return ( 0, $cpuser_data ) if !$status;

    # We don’t restore worker nodes or account proxies.
    _strip_workers_and_proxies_from_cpuser_data($cpuser_data);

    my $err;
    try {
        Cpanel::Validate::FilesystemNodeName::validate_or_die( $cpuser_data->{'RS'} );
        Cpanel::Validate::LineTerminatorFree::validate_or_die( $cpuser_data->{'RS'} );
    }
    catch {
        $err = $_;
    };
    if ($err) {
        return (
            0,
            _locale()->maketext(
                "The value “[_1]” for the “[_2]” key in the [asis,cPanel] user attributes file failed to validate because of an error: [_3]",
                $cpuser_data->{'RS'}, 'RS', Cpanel::Exception::get_string($err)
            )
        );
    }

    $self->_update_locale_and_lang_in_cpuser_data($cpuser_data);

    # IP will be determined by main domain IP address. If account creation is necessary, this check will occur afterwards.
    delete $cpuser_data->{'IP'};

    # Domains will be readded via sub/addon/parked domain creation
    my $domains = delete $cpuser_data->{'DOMAINS'};

    # Accommodate FB 95241
    delete $cpuser_data->{'DBOWNER'};

    my $username = $self->local_username();
    $cpuser_data->{'USER'} = $username;

    $cpuser_data->{'DBOWNER'} = Cpanel::DB::Utils::username_to_dbowner($username);

    return ( 1, $cpuser_data, { 'DOMAINS' => $domains } );
}

sub _strip_workers_and_proxies_from_cpuser_data ($cpuser_hr) {

    my @workers = Cpanel::LinkedNode::Worker::GetAll::get_aliases_and_tokens_from_cpuser($cpuser_hr);

    for my $worker_hr (@workers) {
        Cpanel::LinkedNode::Worker::Storage::unset( $cpuser_hr, $worker_hr->{'worker_type'} );
    }

    # Remove all the account proxies. We do this in order to avoid creating
    # an account proxy on the local server if the source already has an
    # account proxy to the local server. We could make this a bit more
    # lenient if we want to have it *just* remove the proxies that point to
    # local nodes, but since for now the only known application of account
    # proxying is account transfers, we’ll do it thus for now.
    #
    # NB: We also do this in userdataBase to ensure that web vhost configs
    # don’t contain this information, either.

    for my $worker_type (Cpanel::LinkedNode::Worker::GetAll::RECOGNIZED_WORKER_TYPES) {
        Cpanel::AccountProxy::Storage::unset_worker_backend( $cpuser_hr, $worker_type );
    }

    Cpanel::AccountProxy::Storage::unset_backend($cpuser_hr);

    return;
}

sub _update_locale_and_lang_in_cpuser_data {
    my ( $self, $cpuser_data ) = @_;

    my $current_locale_setting = $cpuser_data->{'LOCALE'};
    my $legacy_name            = $cpuser_data->{'LANG'};

    my $new_locale_tag = $current_locale_setting;
    if ( !$new_locale_tag ) {
        require Cpanel::Locale::Utils::Legacy;
        $new_locale_tag = Cpanel::Locale::Utils::Legacy::get_new_langtag_of_old_style_langname($legacy_name);
    }
    my %new_values = (
        'LOCALE' => $new_locale_tag,
        'LANG'   => $legacy_name,
    );

    while ( my ( $key, $val ) = each %new_values ) {
        next if !defined $val;

        $cpuser_data->{$key} = $val;
    }

    return;
}

# Username on the remote machine
sub original_username {
    my ($self) = @_;

    if ( !$self->{'original_username'} && $self->{'_archive_manager'} ) {
        $self->{'original_username'} = $self->{'_archive_manager'}->get_username_from_extracted_archive();
    }

    if ( !$self->{'original_username'} ) {
        Carp::confess("Whostmgr::Transfers::ArchiveManager::get_username_from_extracted_archive never called before fetching original_username, and there is no _archive_manager available");
    }

    if ( $self->{'original_username'} =~ m{/} ) {
        Carp::confess("The original username may not contain a “/” character.");
    }

    return $self->{'original_username'};
}

sub local_username {

    # If they specified a username during the restore process we use that
    return $_[0]->{'flags'}->{'user'} if $_[0]->{'flags'}->{'user'};

    # If they did not specify a username then we use the one from the archive.
    return $_[0]->original_username();
}

sub main_domain {
    my ($self) = @_;

    return $self->{'domain'} || ( $self->domains() )[0] || Carp::confess("domain not set");
}

sub owner {
    my ($self) = @_;

    return $self->{'owner'} || Carp::confess("owner not set");
}

sub set_main_domain {
    my ( $self, $main_domain ) = @_;
    $self->{'domain'} = $main_domain;
    return 1;
}

sub set_owner {
    my ( $self, $owner ) = @_;
    $self->{'owner'} = $owner;
    return 1;
}

sub pwnam {
    return Cpanel::PwCache::getpwnam( $_[0]->local_username() );
}

sub homedir {
    return Cpanel::PwCache::gethomedir( $_[0]->local_username() );
}

sub domains {
    my ($self) = @_;

    my $local_user = $self->local_username();
    my $cpuser_ref = Cpanel::Config::LoadCpUserFile::load($local_user) or do {
        $self->warn( _locale()->maketext( 'The system failed to read the configuration file for the user “[_1]” because of an error: [_2]', $local_user, $! ) );
        Carp::confess("Failed to fetch domains");
    };

    return ( $cpuser_ref->{'DOMAIN'}, ( defined $cpuser_ref->{'DOMAINS'} ? @{ $cpuser_ref->{'DOMAINS'} } : () ) );
}

# for testing
sub reset_skipped_items {
    my ($self) = @_;
    $self->{'skipped_items'} = [];
    return 1;
}

#Returns two-arg format (but can't fail).
sub add_skipped_item {
    my ( $self, $item ) = @_;
    return $self->_add_item( 'skipped_items', 'skipped', $item );
}

sub get_skipped_items {
    my ($self) = @_;
    return $self->{'skipped_items'};
}

# for testing
sub reset_dangerous_items {
    my ($self) = @_;
    $self->{'dangerous_items'} = [];
    return 1;
}

#Returns two-arg format (but can't fail).
sub add_dangerous_item {
    my ( $self, $item ) = @_;
    return $self->_add_item( 'dangerous_items', 'dangerous', $item );
}

sub get_dangerous_items {
    my ($self) = @_;
    return $self->{'dangerous_items'};
}

# for testing
sub reset_altered_items {
    my ($self) = @_;
    $self->{'altered_items'} = [];
    return 1;
}

#Returns two-arg format (but can't fail).
sub add_altered_item {
    my ( $self, $item, $action_url ) = @_;
    return $self->_add_item( 'altered_items', 'altered', $item, $action_url );
}

sub get_altered_items {
    my ($self) = @_;
    return $self->{'altered_items'};
}

# for testing
sub reset_warnings {
    my ($self) = @_;
    $self->{'warnings'} = [];
    return 1;
}

#Returns two-arg format (but can't fail).
sub add_warning {
    my ( $self, $item ) = @_;
    return $self->_add_item( 'warnings', 'warn', $item );
}

sub get_warnings {
    my ($self) = @_;
    return $self->{'warnings'};
}

sub get_old_hostname {
    my ($self) = @_;

    my $extractdir    = $self->{'_archive_manager'}->trusted_archive_contents_dir();
    my $hostname_file = "$extractdir/meta/hostname";
    if ( -e $hostname_file ) {

        my ( $size_ok, $size_msg ) = $self->check_file_size( $hostname_file, ( 1024 * 1024 ) );
        return ( 0, $size_msg ) if !$size_ok;

        open( my $fh, '<', $hostname_file ) or do {
            return ( 0, _locale()->maketext( 'The system failed to open the file “[_1]” because of an error: [_2]', $hostname_file, $! ) );
        };

        my $line = <$fh>;

        close($fh);
        chomp $line;
        return $line if Cpanel::Validate::Hostname::is_valid($line);
    }
    return;
}

sub _add_item {
    my ( $self, $item_type, $func_name, $item, $action_url ) = @_;

    my $function = '__ANON__';
    my $module;
    my $package;
    my $line;
    my $count = 0;
    while ( $function eq '__ANON__' || $function =~ m{$func_name} || $package !~ m{Whostmgr::Transfers} ) {
        $package = ( caller( ++$count ) )[3];
        $line    = ( caller($count) )[2];
        my @code = split( m{::}, $package );
        $function = pop @code;
        $module   = pop @code;
    }

    if ( length $item > 2049 ) {
        $item = substr( $item, 0, 1024 ) . '…' . substr( $item, -1024, 1024 );
    }

    push @{ $self->{$item_type} }, [ [ $module, $function, $line ], $item, $action_url ];

    return 1;
}

#This needn't necessarily be considered particular to this module.
sub check_file_size {
    my ( $self, $path, $max_size ) = @_;

    my $real_size = -s $path;

    if ( $real_size > $max_size ) {
        return ( 0, _locale()->maketext( '“[_1]” is larger ([format_bytes,_2]) than the allowed size ([format_bytes,_3]).', $path, $real_size, $max_size ) );
    }

    return 1;
}

# Call this to record the worker node type as “canceled”, so we’ll
# restore all of the associated resources locally instead.
sub cancel_target_worker_node ( $self, $worker_type ) {
    $self->{'_canceled_target_worker_node'}{$worker_type} = 1;

    return;
}

sub get_source_hostname_or_ip ($self) {
    return $self->{'flags'}{'remote_host'};
}

sub is_live_transfer ($self) {
    return !!$self->{'flags'}{'live_transfer'};
}

# This returns FALSY on live transfers, even though live transfers
# are a superset of the work that express transfers do.
sub is_express_transfer ($self) {
    return !!( $self->{'flags'}{'pre_dns_restore'} && ref $self->{'flags'}{'pre_dns_restore'} eq 'CODE' && !$self->{'flags'}{'live_transfer'} );
}

# Returns a Cpanel::RemoteAPI::WHM instance for the source server
# in a transfer.
sub get_source_api_object ( $self, %opts ) {
    my $opts_hr = $self->{'flags'};

    my $obj;

    # As long as no special options were requested we can
    # cache the API object so that we reuse the HTTP connection.

    if (%opts) {

        # A special configuration was requested, so we create
        # a custom API object.
        $obj = $self->_create_new_source_api_object(%opts);
    }
    else {
        $obj = $self->{'_remote_whm_api'} ||= $self->_create_new_source_api_object();
    }

    return $obj;
}

sub _create_new_source_api_object ( $self, %opts ) {
    my $opts_hr = $self->{'flags'};

    my $peer = $opts_hr->{'remote_host'} or die 'no remote host?';

    my $api_token = $opts_hr->{'remote_api_token'} or die 'no API token?';

    my $authn_username = $opts_hr->{'remote_api_token_username'} or do {
        die 'Missing remote WHM user!';
    };

    require Cpanel::RemoteAPI::WHM;
    return Cpanel::RemoteAPI::WHM->new_from_token(
        $peer,
        $authn_username,
        $api_token,
        %opts,
    )->disable_tls_verify();
}

sub get_source_cpanel_api_object ( $self, %opts ) {

    if ( !$self->{'_remote_cpanel_api'} ) {

        my $opts_hr = $self->{'flags'};

        my $peer = $opts_hr->{'remote_hostname'} or die 'no remote host?';

        my $api_token = $opts_hr->{'remote_api_token'} or die 'no API token?';

        my $authn_username = $opts_hr->{'olduser'} or do {
            die 'Missing remote cPanel user!';
        };

        require Cpanel::RemoteAPI::cPanel;
        $self->{'_remote_cpanel_api'} = Cpanel::RemoteAPI::cPanel->new_from_token(
            $peer,
            $authn_username,
            $api_token,
            %opts,
        )->disable_tls_verify();
    }

    return $self->{'_remote_cpanel_api'};
}

# Determines the target worker alias given an account-restore
# input parameter, per this logic:
#
#   - If cancel_target_worker_node() was called for the given worker type,
#       then there’s no worker.
#
#   - If the account is in demo mode, there's no worker.
#
#   - If no value or “.existing” is given and the archive’s stored alias
#       for $worker_type matches the current system setup, then use it.
#
#   - If “.local” is given, there’s no worker.
#
#   - Otherwise, the value is interpreted as a worker alias and validated
#       as such.
#
# The return value is a Cpanel::LinkedNode::Privileged::Configuration
# instance, or undef if there is no worker node for the restored account
# of the given type.
#
sub get_target_worker_node ( $self, $worker_type ) {
    return undef if $self->{'_canceled_target_worker_node'}{$worker_type};

    return undef if $self->get_demo_mode();

    my $cap_param_name = $Whostmgr::Transfers::Utils::LinkedNodes::WORKER_TYPE_CAPABILITY_PARAMETER{$worker_type};

    my $main_extract_dir = $self->{'_archive_manager'}->trusted_archive_contents_dir();

    my $mismatch_type_why_hr = $self->{'_mismatch_type_why_hr'} ||= do {
        Whostmgr::Transfers::Utils::LinkedNodes::get_mismatch_stored_linked_nodes($main_extract_dir);
    };

    my $resp_sr = $self->{'_target_worker_node'}{$cap_param_name} ||= \do {
        my $user_given_option = $self->{'flags'}{$cap_param_name};

        my $effective_request = $user_given_option || '.existing';

        # This will eventually store either undef or a node_obj
        # but for the interim stores either under or a worker alias.
        my $worker_node;

        if ( $effective_request ne Cpanel::LinkedNode::Alias::Constants::LOCAL ) {
            if ( $effective_request eq Cpanel::LinkedNode::Alias::Constants::EXISTING ) {
                my $worker_obj = Whostmgr::Transfers::Utils::WorkerNodesObj->new($main_extract_dir);

                $worker_node = $worker_obj->get_type_alias($worker_type);

                # If we already determined that the stored worker of this
                # type is not valid, then don’t bother going further.
                if ($worker_node) {
                    if ( my $why_bad = $mismatch_type_why_hr->{$worker_type} ) {
                        $self->add_skipped_item("Unusable worker (alias “$worker_node”): $why_bad");    # TODO
                        $worker_node = undef;
                    }
                }
            }
            else {
                $worker_node = $effective_request;
            }

            if ($worker_node) {
                require Cpanel::LinkedNode;

                eval {
                    $worker_node = Cpanel::LinkedNode::verify_node_capabilities(
                        alias        => $worker_node,
                        capabilities => [$worker_type],
                    );
                } or do {
                    $self->add_skipped_item("Unusable worker (alias “$worker_node”): $@");    # TODO
                    $worker_node = undef;
                };
            }
        }

        $worker_node;
    };

    return $$resp_sr;
}

sub set_account_restoration_mutex ($self) {
    if ( $self->{'_restore_mutex'} ) {
        die 'Only call this method once!';
    }

    my $username = $self->local_username();

    $self->{'_restore_mutex'} = Whostmgr::Transfers::AccountRestoration::Mutex->new_if_not_exists($username) or do {
        die "Another process claims to be restoring $username.";
    };

    return;
}

#----------------------------------------------------------------------

my $_locale;

sub _locale {
    return $_locale ||= do {
        Cpanel::LoadModule::load_perl_module('Cpanel::Locale');
        Cpanel::Locale->get_handle();
    };
}

1;
