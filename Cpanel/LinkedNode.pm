package Cpanel::LinkedNode;

# cpanel - Cpanel/LinkedNode.pm                    Copyright 2022 cPanel, L.L.C.
#                                                           All rights reserved.
# copyright@cpanel.net                                         http://cpanel.net
# This code is subject to the cPanel license. Unauthorized copying is prohibited

use cPstrict;

use Try::Tiny;

use Cpanel::Imports;

use Cpanel::Autodie                               qw(exists mkdir_if_not_exists sysopen unlink_if_exists);
use Cpanel::Exception                             ();
use Cpanel::LinkedNode::Alias                     ();
use Cpanel::LinkedNode::User                      ();
use Cpanel::LinkedNode::Index::Read               ();
use Cpanel::LinkedNode::Privileged::Configuration ();
use Cpanel::LinkedNode::QuotaBalancer::Cron       ();
use Cpanel::LinkedNode::Worker::WHM               ();
use Cpanel::RemoteAPI::WHM                        ();
use Cpanel::Set                                   ();
use Cpanel::ServerTasks                           ();

# This might eventually make sense to split apart into separate modules,
# but for now it’s just noted here.
use constant _TWEAK_SETTINGS_TO_FETCH => {
    Mail => [
        [ 'Mail', 'globalspamassassin' ],
    ],
};

# e.g., controller/worker-type linkages:
use constant _LINKAGE_TYPES_THAT_FORBID_RECURSION => (
    'Mail',
);

=encoding utf-8

=head1 NAME

Cpanel::LinkedNode - Functions for linking and managing remote nodes

=head1 SYNOPSIS

    use Cpanel::LinkedNode ();

    Cpanel::LinkedNode::link_server_node_with_api_token( alias => $alias, username => $username, hostname => $hostname, api_token => $api_token );

    my $node_hr = Cpanel::LinkedNode::get_linked_server_node( alias => $alias );

    Cpanel::LinkedNode::update_linked_server_node( alias => $alias, hostname => $hostname, username => $username, api_token => $api_token );

    my $unlinked_node_hr = Cpanel::LinkedNode::unlink_server_node( alias => $alias );

    my $node_status_hr = Cpanel::LinkedNode::get_server_node_status( username => $username, hostname => $hostname, api_token => $api_token );

=cut

# Exposed for testing
our $_LINKED_NODES_DIR   = '/var/cpanel/linked_nodes';
our $_LINKED_NODES_FILE  = "$_LINKED_NODES_DIR/master.json";
our @_VALID_CAPABILITIES = qw(Mail);

=head2 link_server_node_with_api_token( alias => $alias, hostname => $hostname, username => $username, api_token => $api_token, capabilities => $capabilities_ar )

Links a remote server by specifying the alias, hostname, username, and API
token to use for communication with the remote server.

When linking a server as a remote node, API calls will be made to the
server to verify that it meets a minimum version requirement and that the
server is using a server profile that can support the intended usage.

=over

=item Input

Input is specified by a list of key/value pairs.

=over

=item alias - STRING

A unique alias to refer to the node.

=item hostname - STRING

The hostname of the remote node.

This must be a valid hostname, attempts to link a remote node using an
IP address will die.

=item username - STRING

The username to use when making API calls to the remote node.

This username must be for a root-level administrator on the remote node.

=item api_token - STRING

The API token to use when making API calls to the remote node

This token must be for a root-level administrator on the remote node.

=item skip_tls_verification - BOOLEAN

Whether or not TLS verification can be skipped when querying the remote node.

If falsy or not specified, then queries to the remote node will die with a
fatal error if the SSL/TLS certificate cannot be verified.

=item capabilities - ARRAYREF

An ARRAYREF of worker capabilities to link.

=back

=item Output

=over

This function returns nothing on success, dies otherwise.

=back

=item Throws

=over

=item If any of the alias, username, hostname, or api_token parameters are missing

=item If the alias is invalid as determined in L<Cpanel::LinkedNode::Alias>

=item If the hostname is not a valid domain name

=item If the alias is already in use by another linked node

=item If the hostname is already in use by another linked node

=item If the remote server fails validation due to a version conflict, lack of needed services, or an underprivileged API token

=item There may be other less common exceptions thrown.

=back

=back

=cut

sub link_server_node_with_api_token {

    my %opts = @_;

    my @missing = grep { !length $opts{$_} } qw(alias username hostname api_token capabilities);
    die Cpanel::Exception::create( 'MissingParameters', [ names => \@missing ] ) if @missing;

    my ( $alias, $username, $hostname, $api_token, $skip_tls_verification, $capabilities ) = @opts{qw(alias username hostname api_token skip_tls_verification capabilities)};

    _validate_capabilities($capabilities);

    Cpanel::LinkedNode::Alias::validate_linked_node_alias_or_die($alias);

    require Cpanel::Validate::Domain::Tiny;

    my ( $result, $reason ) = Cpanel::Validate::Domain::Tiny::validdomainname( $hostname, 1 );
    die Cpanel::Exception->create_raw($reason) if !$result;

    my $writer = _get_writer();

    my $nodes_hr = $writer->get_data();

    if ( $nodes_hr->{$alias} ) {
        die Cpanel::Exception->create( 'A node linked to the “[_1]” hostname currently uses the “[_2]” alias. You must use a different alias.', [ $nodes_hr->{$alias}->hostname(), $alias ] );
    }

    _validate_hostname_or_die( $nodes_hr, $hostname );

    _verify_linkage_is_not_duplicate( $hostname, $username, $api_token, $skip_tls_verification );

    my $ret_val = _validate_services_to_link(
        username              => $username,
        hostname              => $hostname,
        api_token             => $api_token,
        capabilities          => $capabilities,
        skip_tls_verification => $skip_tls_verification,
    );

    _validate_no_cp_recursives( $hostname, $ret_val->{'remote_status'}, $capabilities );

    require Cpanel::CommandQueue;
    my $cq = Cpanel::CommandQueue->new();

    $cq->add(
        sub {
            $writer->set(
                $alias,
                username            => $username,
                hostname            => $hostname,
                api_token           => $api_token,
                last_check          => _time(),
                worker_capabilities => $ret_val->{worker_capabilities},
                %{ $ret_val->{remote_status} },
            );
        },
        sub {
            $writer->remove($alias);
        },
    );

    $cq->add(
        sub {
            _set_remote_as_child_node( $hostname, $username, $api_token, $skip_tls_verification );
        },
    );

    $cq->run();

    $writer->save_or_die();

    _sync_node_aliases( $writer->get_data() );

    $writer->close_or_die();

    Cpanel::LinkedNode::QuotaBalancer::Cron->ensure_that_entry_exists();

    return;
}

sub _get_writer {
    require Cpanel::LinkedNode::Index::Write;
    return Cpanel::LinkedNode::Index::Write->new();
}

sub _sync_node_aliases ( $nodes_hr, $deleted = undef ) {
    my %to_sync;

    for my $alias ( keys %$nodes_hr ) {
        $to_sync{$alias} = {
            hostname     => $nodes_hr->{$alias}->hostname(),
            tls_verified => $nodes_hr->{$alias}->tls_verified(),
        };
    }

    Cpanel::LinkedNode::User::sync_node_aliases( \%to_sync, $deleted );

    return;
}

sub _set_remote_as_child_node ( $hostname, $username, $api_token, $skip_tls_verification ) {    ## no critic qw(ManyArgs) - mis-parse

    my $api_obj = Cpanel::RemoteAPI::WHM->new_from_token(
        $hostname,
        $username,
        $api_token,
    );

    $api_obj->disable_tls_verify() if $skip_tls_verification;

    $api_obj->request_whmapi1_or_die('PRIVATE_set_as_child_node');

    return;
}

sub _clean_up_former_child_node ( $child_node_obj, $handle_opt ) {

    require Cpanel::PromiseUtils;

    my $api = $child_node_obj->get_async_remote_api();

    my @parallel_reqs = (
        $api->request_whmapi1('PRIVATE_unset_as_child_node'),
    );

    if ( $handle_opt && $handle_opt eq 'expire_24h' ) {

        # We need to give a timestamp for token expiry. Let’s base that
        # on the remote’s system time rather than the local one.
        # This requests the remote time and the API token details in
        # parallel, then once those are both done sets the token’s
        # expiry.
        #
        my $remote_time_p = _get_remote_time_p($child_node_obj);

        push @parallel_reqs, $api->request_whmapi1(
            'api_token_get_details',
            { token => $child_node_obj->api_token() },
        )->then(
            sub ($token_resp) {
                my $token_hr = $token_resp->get_data();

                return $remote_time_p->then(
                    sub ($remote_time) {
                        return $api->request_whmapi1(
                            'api_token_update',
                            {
                                token_name => $token_hr->{'name'},
                                expires_at => 86400 + $remote_time,
                            },
                        );
                    }
                );
            }
        );
    }

    $_ = $_->catch( sub { warn shift } ) for @parallel_reqs;

    Cpanel::PromiseUtils::wait_anyevent(@parallel_reqs);

    return;
}

sub _get_remote_time_p ($node_obj) {

    # There’s no API to fetch the time, so we’ll get it via a command.

    my $cstream = $node_obj->get_commandstream();

    return $cstream->exec(

        # AWK is even more ubiquitous than Perl …
        command => [ '/usr/bin/awk', 'BEGIN { print systime() }' ],
    )->then(
        sub ($resp) {
            $resp->die_if_error();
            return $resp->stdout() =~ s<\s><>gr;
        }
    );
}

sub _verify_linkage_is_not_duplicate ( $hostname, $username, $api_token, $skip_tls_verification ) {    ## no critic qw(ManyArgs) - mis-parse
    my $api_obj = Cpanel::RemoteAPI::WHM->new_from_token(
        $hostname,
        $username,
        $api_token,
    );
    $api_obj->disable_tls_verify() if $skip_tls_verification;

    require Cpanel::LinkedNode::UniquenessToken;
    my $token = Cpanel::LinkedNode::UniquenessToken::create_and_write();

    my $wrote = $api_obj->request_whmapi1_or_die(
        'PRIVATE_write_uniqueness_token',
        { token => $token },
    );

    if ( !$wrote->get_data()->{'payload'} ) {
        die Cpanel::Exception->create( '“[_1]” is an alias for this server.', [$hostname] );
    }

    Cpanel::LinkedNode::Worker::WHM::do_on_all_nodes(
        remote_action => sub ($node_obj) {
            my $wrote_yn;

            try {
                $wrote_yn = Cpanel::LinkedNode::Worker::WHM::do_whmapi1_call(
                    node_obj => $node_obj,
                    function => 'PRIVATE_write_uniqueness_token',
                    api_opts => { token => $token },
                )->{'payload'};
            }
            catch {
                die Cpanel::Exception->create(
                    'The system contacted “[_1]”, but the system failed to verify that “[_2]” is not the same server as “[_1]”. The system cannot link additional nodes until it completes that verification. If “[_2]” is no longer active, unlink it in the “[_3]” interface. The failure was: [_4]',
                    [ $hostname, $node_obj->hostname(), locale()->maketext('Link Server Nodes'), Cpanel::Exception::get_string($_) ]
                );
            };

            if ( !$wrote_yn ) {
                die Cpanel::Exception->create( '“[_1]” (“[_2]”) is already one of this server’s linked nodes.', [ $hostname, $node_obj->hostname() ] );
            }
        },
    );

    return;
}

=head2 my $node_hr = get_linked_server_node( alias => $alias )

Gets the details of a linked remote node specified by
the alias of the node.

=over

=item Input

=over

=item alias - STRING

The alias of the linked node

=back

=item Output

Returns a C<Cpanel::LinkedNode::Privileged::Configuration> object with the
details for the linked node.

=item Throws

=over

=item If the alias parameter is missing.

=item If there is no linked node for the specified alias.

=item There may be other less common exceptions thrown.

=back

=back

=cut

sub get_linked_server_node {
    my %opts = @_;

    die Cpanel::Exception::create( 'MissingParameter', [ name => 'alias' ] ) if !length $opts{alias};

    my $alias = $opts{alias};

    my $nodes_hr = Cpanel::LinkedNode::Index::Read::get();

    my $node_hr = _alias_exists_or_die( $nodes_hr, $alias );

    Cpanel::LinkedNode::User::sync_node_alias( $alias, $node_hr->hostname(), $node_hr->tls_verified() );

    return $node_hr;
}

=head2 update_linked_server_node( alias => $alias, hostname => $hostname, username => $username, api_token => $api_token )

Updates a linked server node.

=over

=item Input

=over

=item alias - STRING

The alias for the remote node

=item hostname - STRING

The hostname of the remote node

=item username - STRING

The username to use when making API calls to the remote node.

This parameter is optional. If not provided the existing username will not be changed.

=item api_token - STRING

The API token to use when making API calls to the remote node

This parameter is optional. If not provided the existing API token will not be changed.

=item skip_tls_verification - BOOL

Whether or not TLS verification can be skipped when querying the remote node.

If falsy or not specified, then queries to the remote node will die with a
fatal error if the SSL/TLS certificate cannot be verified.

This parameter cannot be set to false if the remote node has already been
verified.

=item capabilities - ARRAYREF

An ARRAYREF of worker capabilities to link.

=back

=item Output

=over

This function returns nothing on success, dies otherwise.

=back

=item Throws

=over

=item If the alias is missing

=item If the specified alias does not exist

=item If tls_verified is false but the specified node has already been TLS verified

=item If the hostname is already in use by another linked node

=item If the hostname is not a valid domain name

=item If the remote server fails validation due to a version conflict, lack of needed services, or an underprivileged API token

=item There may be other less common exceptions thrown.

=back

=back

=cut

sub update_linked_server_node {
    my %opts = @_;

    die Cpanel::Exception::create( 'MissingParameter', [ name => 'alias' ] ) if !length $opts{alias};

    my ( $alias, $username, $hostname, $api_token, $skip_tls_verification, $capabilities ) = @opts{qw(alias username hostname api_token skip_tls_verification capabilities)};

    _validate_capabilities($capabilities) if $capabilities;

    require Cpanel::LinkedNode::Index::Write;
    my $writer = Cpanel::LinkedNode::Index::Write->new();

    my $nodes_hr = $writer->get_data();

    my $node_hr = _alias_exists_or_die( $nodes_hr, $alias );

    if ( $node_hr->tls_verified() && $skip_tls_verification ) {
        die Cpanel::Exception->create( 'The hostname “[_1]” is already [output,abbr,TLS,Transport Layer Security] verified. You cannot disable [output,abbr,TLS,Transport Layer Security] verification.', [ $hostname || $node_hr->hostname() ] );
    }

    my $changing_hostname = $hostname && $node_hr->hostname() ne $hostname;
    _validate_hostname_or_die( $nodes_hr, $hostname ) if $changing_hostname;

    my $old_hostname = $node_hr->hostname();

    $hostname  ||= $node_hr->hostname();
    $username  ||= $node_hr->username();
    $api_token ||= $node_hr->api_token();
    $skip_tls_verification //= !$node_hr->tls_verified();
    $capabilities ||= $node_hr->worker_capabilities();

    my @corrupt;
    push @corrupt, 'hostname'  if !length $hostname;
    push @corrupt, 'username'  if !length $username;
    push @corrupt, 'api_token' if !length $api_token;
    die Cpanel::Exception::create( 'MissingParameters', [ names => \@corrupt ] ) if @corrupt;

    if ($changing_hostname) {
        require Cpanel::Validate::Domain::Tiny;
        my ( $result, $reason ) = Cpanel::Validate::Domain::Tiny::validdomainname( $hostname, 1 );
        die Cpanel::Exception->create_raw($reason) if !$result;
    }

    my $ret_val = _validate_services_to_link(
        username              => $username,
        hostname              => $hostname,
        api_token             => $api_token,
        capabilities          => $capabilities,
        skip_tls_verification => $skip_tls_verification,
    );

    _validate_no_cp_recursives( $hostname, $ret_val->{'remote_status'}, $capabilities );

    $writer->set(
        $alias,
        hostname            => $hostname,
        username            => $username,
        api_token           => $api_token,
        worker_capabilities => $ret_val->{worker_capabilities},
        %{ $ret_val->{remote_status} },
    );

    $writer->save_or_die();

    _sync_node_aliases( $writer->get_data() );

    $writer->close_or_die();

    if ($changing_hostname) {
        Cpanel::ServerTasks::queue_task( ['LinkedNode'], "propagate_hostname_update $alias $old_hostname" );
    }

    return;
}

=head2 verify_node_capabilities( %OPTS )

Verifies that the specified node is able to function as a specific type of node.

=over

=item Input

=over

=item alias - STRING

The alias of the remote node

=item capabilities - ARRAYREF

An ARRAYREF of worker capabilities (e.g., C<Mail>) to link.

=back

=item Output

This function returns a C<Cpanel::LinkedNode::Privileged::Configuration> object
on success, dies otherwise.

=item Throws

=over

=item If the alias is missing

=item If the specified alias does not exist

=item If the remote server fails validation due to a version conflict, lack of needed services, or an underprivileged API token

=item There may be other less common exceptions thrown.

=back

=back

=cut

sub verify_node_capabilities {

    my (%opts) = @_;

    my @missing = grep { !length $opts{$_} } qw(alias capabilities);
    die Cpanel::Exception::create( 'MissingParameters', [ names => \@missing ] ) if scalar @missing;

    my ( $alias, $capabilities ) = @opts{qw(alias capabilities)};

    _validate_capabilities($capabilities);

    # TODO: This should call into Cpanel::LinkedNode::Index::Read instead.
    my $nodes_hr = Cpanel::LinkedNode::Index::Read::get();

    my $node_obj = _alias_exists_or_die( $nodes_hr, $alias );

    _validate_services_to_link(
        username              => $node_obj->username(),
        hostname              => $node_obj->hostname(),
        api_token             => $node_obj->api_token(),
        skip_tls_verification => $node_obj->allow_bad_tls(),
        capabilities          => $capabilities,
    );

    return Cpanel::LinkedNode::Privileged::Configuration->new( alias => $alias, %{ $nodes_hr->{$alias} } );
}

=head2 unlink_server_node( alias => $alias )

Unlinks (deletes) a linked server node.

=over

=item Input

=over

=item alias - STRING

The alias of the remote node

=item handle_api_token - STRING/ENUM

What to do on the (to-be-former) child node with the API token that
we’ve been using to talk to it. Must be one of:

=over

=item * C<leave> - Default. Leave the token active. Appropriate for cases
where the token was created outside the node-linkage workflow. Considered
insecure, though, as it leaves a vector open for remote privileged access
to the child node.

=item * C<expire_24h> - Set the token to expire after 24 hours.

=back

=back

=item Output

Returns a C<Cpanel::LinkedNode::Privileged::Configuration> object with the details of the
unlinked node on success, or undef if there is no linked node with the specified alias.

=item Throws

=over

=item If the alias parameter is missing

=item There may be other less common exceptions thrown.

=back

=back

=cut

sub unlink_server_node {

    my %opts = @_;

    die Cpanel::Exception::create( 'MissingParameter', [ name => 'alias' ] ) if !length $opts{alias};

    _validate_optional_enum( \%opts, 'handle_api_token', qw( leave expire_24h ) );

    my $alias = $opts{alias};

    my $writer = _get_writer();

    if ( my $count = list_accounts_distributed_to_child_node($alias) ) {
        die Cpanel::Exception->create( '[quant,_1,account uses,accounts use] this linkage. The system cannot delete a linkage that is in use.', [$count] );
    }

    my $removed = $writer->remove($alias);

    if ($removed) {

        my $remaining = keys %{ $writer->get_data() };

        $writer->save_or_die();
        _sync_node_aliases( $writer->get_data(), $alias );
        $writer->close_or_die();

        if ( $remaining == 0 ) {
            Cpanel::LinkedNode::QuotaBalancer::Cron->delete_entry();
        }

        _clean_up_former_child_node( $removed, $opts{'handle_api_token'} );
    }

    return $removed;
}

# This may be generally reusable. Type::Tiny::Enum implements
# stuff like this but seems a bit “overkill”-ish.
#
sub _validate_optional_enum ( $opts_hr, $key, @allowed ) {
    my $val = $opts_hr->{$key};

    if ( defined $val ) {
        if ( !grep { $_ eq $val } @allowed ) {
            die Cpanel::Exception::create_raw( 'InvalidParameter', "Bad “$key”: $val" );
        }
    }

    return;
}

# mocked in tests
sub _getcpusers {
    require Cpanel::Config::Users;
    return Cpanel::Config::Users::getcpusers();
}

# mocked in tests
sub _load_cpuser_file ($username) {
    require Cpanel::Config::LoadCpUserFile;
    return Cpanel::Config::LoadCpUserFile::load_or_die($username);
}

=head2 @usernames = list_accounts_distributed_to_child_node($ALIAS)

Returns a list of usernames that use the child node whose alias
is $ALIAS. In scalar context this returns the count of such usernames.

=cut

sub list_accounts_distributed_to_child_node ($alias) {
    my @usernames;

    my @cpusernames = _getcpusers();

    require Cpanel::LinkedNode::Worker::GetAll;

    for my $username (@cpusernames) {
        my $cpuser_hr = _load_cpuser_file($username);
        my @all       = Cpanel::LinkedNode::Worker::GetAll::get_aliases_and_tokens_from_cpuser($cpuser_hr);

        if ( grep { $_->{'alias'} eq $alias } @all ) {
            push @usernames, $username;
        }
    }

    return @usernames;
}

=head2 $server_status = get_server_node_status( hostname => $hostname, username => $username, api_token => $token )

Queries a remote server using WHM API for its status by calling
the C<version> and C<get_current_profile> API methods.

The remote server B<must> be running cPanel & WHM version 11.76
or greater.

=over

=item Input

=item hostname - STRING

The hostname of the remote node

=item username - STRING

The username to use when making API calls to the remote node

=item api_token - STRING

The API token to use when making API calls to the remote node

=item skip_tls_verification - STRING

Whether or not TLS verification can be skipped when querying the remote node.

If falsy or not specified, then queries to the remote node will die with a
fatal error if the SSL/TLS certificate cannot be verified.

=back

=over

=item Output

=over

Returns a HASHREF with details about the server’s status

The hash keys are:

=over

=item version

The cPanel & WHM version installed on the remote server

=item enabled_services

An ARRAYREF of strings representing the enabled services on the remote server

These services should correspond to the service names returned by the
C<get_service_list> method in the L<Cpanel::Services::List> module.

=item tls_verified

Whether or not the SSL/TLS certificate for the remote node could be verified.

=back

=back

=item Throws

=over

=item If any of the username, hostname, or api_token parameters are missing

=item If any of the calls to the remote node fails

=item There may be other less common exceptions thrown.

=back

=back

=cut

sub get_server_node_status {

    my (%opts) = @_;

    my @missing = grep { !length $opts{$_} } qw(username hostname api_token);
    die Cpanel::Exception::create( 'MissingParameters', [ names => \@missing ] ) if @missing;

    my ( $username, $hostname, $api_token, $skip_tls_verification ) = @opts{qw(username hostname api_token skip_tls_verification)};

    # cPanel::PublicAPI (and consequently Cpanel::RemoteAPI) writes to STDERR on error.
    # Redirect here so there's no spewage to STDERR if something fails.
    my $error_fh;

    require Cpanel::RemoteAPI::WHM;
    my $api = Cpanel::RemoteAPI::WHM->new_from_token( $hostname, $username, $api_token, error_log => \$error_fh );

    my @funcs = (
        ['version'],
        ['myprivs'],
        ['servicestatus'],
        ['list_linked_server_nodes'],
    );

    for my $settings_ar ( values %{ _TWEAK_SETTINGS_TO_FETCH() } ) {
        for my $ts_ar (@$settings_ar) {
            my %ts_arg;
            @ts_arg{ 'module', 'key' } = @$ts_ar;

            push @funcs, [ get_tweaksetting => \%ts_arg ];
        }
    }

    require Whostmgr::API::1::Utils::Batch;
    my $batch = Whostmgr::API::1::Utils::Batch::assemble_batch(@funcs);

    local $@;
    my $batch_result = eval { $api->request_whmapi1( batch => $batch ) };

    my $tls_verified = 0;
    if ($@) {
        if ( !_looks_like_tls_error($@) || !$skip_tls_verification ) {
            die Cpanel::Exception->create_raw($@);
        }
        else {
            $api = Cpanel::RemoteAPI::WHM->new_from_token( $hostname, $username, $api_token, error_log => \$error_fh );
            $api->disable_tls_verify();
            $batch_result = $api->request_whmapi1( batch => $batch );
        }
    }
    else {
        $tls_verified = 1;
    }

    if ( my $err = $batch_result->get_error() ) {
        if ( $batch_result->get_data() ) {
            my @results = $batch_result->parse_batch();

            my @errors;

            for my $r ( 0 .. $#results ) {
                my $result = $results[$r];
                next if !$result->get_error();

                push @errors, "$funcs[$r][0]: " . $result->get_error();

                die Cpanel::Exception->create_raw("@errors");
            }
        }
        else {
            die Cpanel::Exception->create_raw($err);
        }
    }

    my @results = $batch_result->parse_batch();

    my $version = $results[0]->get_data()->{version};

    my $my_privs_result = $results[1];

    my $privs = $my_privs_result->get_data()->[0];
    die Cpanel::Exception->create( 'You must specify an API token that possesses the “[_1]” [asis,ACL].', ['all'] ) if !$privs->{all};

    my $service_result = $results[2];
    my $services       = $service_result->get_data();

    my @enabled_services = map { $_->{name} } grep { $_->{enabled} } @{$services};

    my $linked_nodes_result = $results[3];

    my $ts_result_index = 4;

    my %system_settings;

    for my $settings_ar ( values %{ _TWEAK_SETTINGS_TO_FETCH() } ) {
        for my $ts_ar (@$settings_ar) {
            my $ts_result = $results[$ts_result_index];
            $system_settings{ $ts_ar->[0] }{ $ts_ar->[1] } = $ts_result->get_data()->{'tweaksetting'}{'value'};
            $ts_result_index++;
        }
    }

    return {
        version              => $version,
        enabled_services     => \@enabled_services,
        tls_verified         => $tls_verified,
        system_settings      => \%system_settings,
        remote_node_linkages => $linked_nodes_result->get_data(),
    };
}

sub get_installed_server_node_status ($alias) {
    my $node_obj = get_linked_server_node( alias => $alias );

    return get_server_node_status(
        ( map { $_ => $node_obj->$_() } qw( hostname username api_token ) ),
        skip_tls_verification => $node_obj->allow_bad_tls(),
    );
}

sub _looks_like_tls_error {
    my ($error) = @_;

    # Dear future self:
    # This is written to very loosely match a certificate verification error which currently shows up as:
    # Could not connect to https://host.tld:2087/json-api/version: SSL connection failed for host.tld: SSL connect attempt failed error:14090086:SSL routines:ssl3_get_server_certificate:certificate verify failed

    return index( $error, 'SSL' ) != -1 || index( $error, 'TLS' ) != -1;
}

sub _validate_no_cp_recursives ( $remote_hostname, $remote_status_hr, $capabilities_ar ) {    ## no critic qw(ManyArgs) - mis-parse
    my $remote_node_linkages_ar = $remote_status_hr->{'remote_node_linkages'};

    my @recursive_forbidden_capabilities = Cpanel::Set::intersection(
        $capabilities_ar,
        [ _LINKAGE_TYPES_THAT_FORBID_RECURSION() ],
    );

    # If there is no “remote_node_linkages” array, then the node in question
    # isn’t a cPanel & WHM server.
    if ($remote_node_linkages_ar) {
        foreach my $node_type (@recursive_forbidden_capabilities) {
            for my $linked_node (@$remote_node_linkages_ar) {
                next if !$linked_node->{'worker_capabilities'}{$node_type};

                my $linked_hostname = $linked_node->{'hostname'};

                require Cpanel::Domain::Local;
                if ( Cpanel::Domain::Local::domain_or_ip_is_on_local_server($linked_hostname) ) {
                    die Cpanel::Exception->create( 'This server cannot use “[_1]” as a “[_2]” linked node because “[_1]” already uses this server ([_3]) as a “[_2]” linked node.', [ $remote_hostname, $node_type, $linked_hostname ] );
                }
            }
        }
    }

    return;
}

sub _validate_services_to_link {

    my %opts = @_;

    my ( $username, $hostname, $api_token, $capabilities, $skip_tls_verification ) = @opts{qw(username hostname api_token capabilities skip_tls_verification)};

    my ( $remote_node_status, %remote_enabled_services, %linked_worker_capabilities );

    foreach my $node_type (@$capabilities) {

        my $module_name = "Cpanel::LinkedNode::Type::${node_type}";

        require Cpanel::LoadModule;
        Cpanel::LoadModule::load_perl_module($module_name);

        my $type_obj = $module_name->new();

        my %extended_opts     = $type_obj->get_and_validate_options_for_type(%opts);
        my $min_version       = $type_obj->get_minimum_supported_version();
        my @required_services = $type_obj->get_required_services();

        if ( !$min_version && scalar @required_services ) {
            die Cpanel::Exception->create( 'The “[_1]” node type has required services. However, it does not have a required minimum [asis,cPanel] version.', $type_obj->get_type_name() );
        }
        elsif ($min_version) {

            if ( !$remote_node_status ) {

                $remote_node_status = get_server_node_status(
                    username              => $username,
                    hostname              => $hostname,
                    api_token             => $api_token,
                    skip_tls_verification => $skip_tls_verification
                );

                @remote_enabled_services{ @{ $remote_node_status->{enabled_services} } } = ();
            }

            require Cpanel::Version::Compare;

            if ( !Cpanel::Version::Compare::compare( $remote_node_status->{version}, '>=', $min_version ) ) {
                die Cpanel::Exception->create( 'The remote server “[_1]” uses [asis,cPanel amp() WHM] version “[_2]”. The minimum version that the system supports for “[_3]” nodes is [asis,cPanel amp() WHM] version “[_4]”.', [ $hostname, $remote_node_status->{version}, $type_obj->get_type_name(), $min_version ] );
            }

            if ( scalar @required_services ) {

                my @missing_services = grep { !exists $remote_enabled_services{$_} } @required_services;

                if ( scalar @missing_services ) {
                    die Cpanel::Exception->create(
                        'The remote server “[_1]” does not possess the required services for a “[_2]” node. To link a server as a “[_2]” node, the server must support the [list_and_quoted,_3] [numerate,_4,service,services]. The remote server is missing the [list_and_quoted,_5] [numerate,_6,service,services].',
                        [ $hostname, $type_obj->get_type_name(), \@required_services, scalar @required_services, \@missing_services, scalar @missing_services ]
                    );
                }

            }

        }

        $type_obj->do_extended_validation( username => $username, hostname => $hostname, api_token => $api_token, %extended_opts );

        $linked_worker_capabilities{$node_type} = \%extended_opts;
    }

    # None of the types required a version or service check, so we have no status.
    # This may happen if the remote node being linked is not required to be running cPanel.
    # For example, if linking to a SoftLayer DNS node.
    $remote_node_status ||= {};

    return { remote_status => $remote_node_status, worker_capabilities => \%linked_worker_capabilities };
}

sub _time {
    return time();
}

sub _validate_hostname_or_die {
    my ( $nodes_hr, $hostname ) = @_;

    local ( $@, $! );
    require Cpanel::Validate::Hostname;
    if ( !Cpanel::Validate::Hostname::is_minimally_valid($hostname) ) {
        die Cpanel::Exception::create( 'InvalidParameter', '“[_1]” is not a valid hostname.', [$hostname] );
    }

    my ($existing_alias) = grep { $nodes_hr->{$_}->hostname() eq $hostname } keys %$nodes_hr;
    die Cpanel::Exception->create( 'The system already possesses a node linkage with alias “[_2]” to the server with hostname “[_1]”.', [ $hostname, $existing_alias ] ) if $existing_alias;
    return;
}

sub _alias_exists_or_die {
    my ( $nodes_hr, $alias ) = @_;
    die Cpanel::Exception->create( 'No node link with alias “[_1]” exists on this system.', [$alias] ) if !$nodes_hr->{$alias};
    return $nodes_hr->{$alias};
}

sub _validate_capabilities {
    my ($capabilities_ar) = @_;
    require Cpanel::Set;
    my @invalid = Cpanel::Set::difference( $capabilities_ar, \@_VALID_CAPABILITIES );
    die Cpanel::Exception->create( "The system does not support the [list_and_quoted,_1] [numerate,_2,capability,capabilities].", [ \@invalid, scalar @invalid ] ) if scalar @invalid;
    return;
}

1;
