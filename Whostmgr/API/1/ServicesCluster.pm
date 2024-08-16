package Whostmgr::API::1::ServicesCluster;

# cpanel - Whostmgr/API/1/ServicesCluster.pm       Copyright 2022 cPanel, L.L.C.
#                                                           All rights reserved.
# copyright@cpanel.net                                         http://cpanel.net
# This code is subject to the cPanel license. Unauthorized copying is prohibited

use cPstrict;
use Module::Want ();

use Cpanel::Imports;

use Cpanel::JSON                          ();
use Cpanel::Transaction::File::JSON       ();
use Cpanel::Transaction::File::JSONReader ();
use Cpanel::Validate::IP::v4              ();
use Cpanel::Validate::UserNote            ();
use Cpanel::PwCache                       ();
use Cpanel::SSH                           ();

use Whostmgr::API::1::Utils ();

use Try::Tiny;

use constant NEEDS_ROLE => {
    has_services_cluster_configured    => 'CloudController',
    add_services_cluster_node          => 'CloudController',
    delete_services_cluster_node       => 'CloudController',
    list_services_cluster_nodes        => 'CloudController',
    stage_services_cluster_node        => 'CloudController',
    unstage_services_cluster_node      => 'CloudController',
    list_staged_services_cluster_nodes => 'CloudController',
    commit_services_cluster_inventory  => 'CloudController',
};

use constant LABEL_AND_COMMENT_PREFIX => 'cpsc.cpanel.com';
use constant COMMENT_KEY              => LABEL_AND_COMMENT_PREFIX . '/comment';

# Exposed for testing.
our $_DEBUG                  = 0;
our $INVENTORY_TEMPLATE_PATH = '/usr/local/cpanel/whostmgr/docroot/templates/ansible_inventory.tmpl';

sub stage_services_cluster_node ( $args, $metadata, $ ) {
    my $name       = Whostmgr::API::1::Utils::get_length_required_argument( $args, 'name' );
    my $role       = Whostmgr::API::1::Utils::get_length_required_argument( $args, 'role' );
    my $ip_address = Whostmgr::API::1::Utils::get_length_required_argument( $args, 'ip_address' );
    my $ssh_key    = Whostmgr::API::1::Utils::get_length_required_argument( $args, 'ssh_key' );

    if ( $name !~ m/^[a-z][a-z0-9]*$/ ) {
        $metadata->set_not_ok( locale()->maketext("You must provide a valid lowercase alphanumeric name that starts with a letter for the new node.") );
        return;
    }

    my ( $ssh_keys, $warnings ) = Cpanel::SSH::_listkeys( public => 0, private => 1, );
    if ( !scalar( grep { $_->{file} eq $ssh_key } $ssh_keys->@* ) ) {
        $metadata->set_not_ok( locale()->maketext( "SSH key \`[_1]\` is not valid or does not exist.", $ssh_key ) );
        return;
    }

    if ( !Cpanel::Validate::IP::v4::is_valid_ipv4($ip_address) ) {
        $metadata->set_not_ok( locale()->maketext("You must provide a valid [asis,IPv4] address for the new node.") );
        return;
    }

    if ( $role !~ m/^server|agent$/ ) {
        $metadata->set_not_ok( locale()->maketext("You must indicate whether the new node is either an agent or a server.") );
        return;
    }

    # Open or initialize staging file.
    my $txn    = _open_rw_transaction($_DEBUG);
    my $staged = $txn->get_data();

    if ( scalar( grep { $_->{name} eq $name } $staged->{nodes}->@* ) ) {
        $metadata->set_not_ok( locale()->maketext( "A node named [_1] already exists.", $name ) );
        return;
    }

    if ( scalar( grep { $_->{ip_address} eq $ip_address } $staged->{nodes}->@* ) ) {
        $metadata->set_not_ok( locale()->maketext( "A node with IP address [_1] already exists.", $ip_address ) );
        return;
    }

    if ( !scalar( grep { $_->{role} eq 'server' } $staged->{nodes}->@* ) && $role ne 'server' ) {
        $metadata->set_not_ok( locale()->maketext("You must provide at least one server node before adding any agent nodes.") );
        return;
    }

    push(
        $staged->{nodes}->@*,
        {
            name       => $name,
            role       => $role,
            ip_address => $ip_address,
            ssh_key    => $ssh_key,
        }
    );
    $txn->set_data($staged);
    $txn->save_and_close_or_die();

    $metadata->set_ok();

    return $staged;
}

sub unstage_services_cluster_node ( $args, $metadata, $ ) {
    local @INC = _get_cpsc_inc();
    require CPSC::Util;

    my $name = Whostmgr::API::1::Utils::get_length_required_argument( $args, 'name' );

    if ( _staging_file_is_unpopulated() ) {
        $metadata->set_not_ok( locale()->maketext("There are currently no staged nodes.") );
        return;
    }

    # Open or initialize staging file.
    my $txn    = _open_rw_transaction($_DEBUG);
    my $staged = $txn->get_data();

    if ( !scalar( $staged->{nodes}->@* ) ) {
        $metadata->set_not_ok( locale()->maketext("There are currently no staged nodes.") );
        return;
    }

    if ( !scalar( grep { $_->{name} eq $name } $staged->{nodes}->@* ) ) {
        $metadata->set_not_ok( locale()->maketext("You must provide a valid node name.") );
        return;
    }

    $staged->{nodes} = [ grep { $_->{name} ne $name } $staged->{nodes}->@* ];
    $txn->set_data($staged);
    $txn->save_and_close_or_die();

    $metadata->set_ok();
    return $staged;
}

sub list_staged_services_cluster_nodes ( $args, $metadata, $ ) {
    local @INC = _get_cpsc_inc();
    require CPSC::Util;

    if ( _staging_file_is_unpopulated() ) {
        $metadata->set_not_ok( locale()->maketext("There are currently no staged nodes.") );
        return;
    }

    # Open or initialize staging file.
    my $txn    = _open_ro_transaction();
    my $staged = $txn->get_data();

    $metadata->set_ok();
    return $staged;
}

sub commit_services_cluster_inventory ( $args, $metadata, $ ) {
    local @INC = _get_cpsc_inc();
    require CPSC::Util;

    if ( _staging_file_is_unpopulated() ) {
        $metadata->set_not_ok( locale()->maketext("There are currently no staged nodes.") );
        return;
    }

    # Open or initialize staging file.
    my $txn    = _open_ro_transaction();
    my $staged = $txn->get_data();

    if ( !scalar( $staged->{nodes}->@* ) ) {
        $metadata->set_not_ok( locale()->maketext("There are currently no staged nodes.") );
        return;
    }

    require Template;
    my $tt = Template->new( ABSOLUTE => 1 );
    if ( $tt->process( $INVENTORY_TEMPLATE_PATH, $staged, $CPSC::Util::INVENTORY_PATH, ) ) {
        $metadata->set_ok();
    }
    else {
        $metadata->set_not_ok( $tt->error() );
    }

    return { inventory => $CPSC::Util::INVENTORY_PATH };
}

sub has_services_cluster_configured ( $args, $metadata, $ ) {

    # TODO?: Cpanel::LoadModule::Custom::load_perl_module (used in xml-api.pl to load the API modules) prevents
    #        loaded modules from modifying @INC when they're loaded, so no use lib for this yet.
    local @INC = _get_cpsc_inc();
    require CPSC;

    my $has_cpsc = CPSC->instance->orch->has_services_cluster_configured;

    $metadata->set_ok();

    return { has_cpsc => $has_cpsc };
}

sub add_services_cluster_node ( $args, $metadata, $ ) {

    # TODO?: Cpanel::LoadModule::Custom::load_perl_module (used in xml-api.pl to load the API modules) prevents
    #        loaded modules from modifying @INC when they're loaded, so no use lib for this yet.
    local @INC = _get_cpsc_inc();
    require CPSC;

    my $host      = $args->{'host'};
    my $is_agent  = $args->{'is_agent'};
    my $is_server = $args->{'is_server'};
    my $comment   = $args->{'comment'};

    my $labels_hr = Whostmgr::API::1::Utils::map_length_multiple_to_key_values( $args, 'label-key', 'label-value' );

    if ( !length $host ) {
        $metadata->set_not_ok( locale()->maketext("You must provide a hostname or IP address for the new node.") );
        return;
    }

    if ( !$is_agent && !$is_server ) {
        $metadata->set_not_ok( locale()->maketext("You must indicate whether the new node is an agent or server.") );
        return;
    }

    if ( $is_agent && $is_server ) {
        $metadata->set_not_ok( locale()->maketext("A node cannot be both an agent and a server.") );
        return;
    }

    my $prefixed_labels      = {};
    my $prefixed_annotations = {};

    if ( %$labels_hr || length $comment ) {

        for my $key ( keys %$labels_hr ) {
            my $prefixed_key = join '/', LABEL_AND_COMMENT_PREFIX, $key;
            $prefixed_labels->{$prefixed_key} = $labels_hr->{$key};
        }

        if ( length $comment ) {

            my $err = Cpanel::Validate::UserNote::why_invalid($comment);
            if ($err) {
                $metadata->set_not_ok($err);
                return;
            }

            $prefixed_annotations->{ COMMENT_KEY() } = $comment;
        }

        CPSC->instance->orch->validate_node_metadata( $prefixed_labels, $prefixed_annotations );
    }

    my $agent_ips  = [];
    my $server_ips = [];

    push @$agent_ips,  $host if $is_agent;
    push @$server_ips, $host if $is_server;

    my $orch = CPSC->instance->orch;

    # TODO: CPSC currently just dumps the full output from Ansible as part of
    # the error message thrown. Setting this ENV var here will put that output
    # into a machine-parseable format in a best effort to get a friendly error
    # message from the output.
    #
    # This module, though, shouldn’t know or care about Ansible or its output
    # format; those are the CPSC library’s implementation details.
    #
    # CPANEL-42059 documents giving CPSC an interface that exposes
    # structured errors, and replacing the below with a call to that interface
    # in lieu of the status quo.
    #
    local $ENV{'ANSIBLE_STDOUT_CALLBACK'} = 'json';

    try {
        $orch->add_nodes( $agent_ips, $server_ips );
    }
    catch {
        die locale()->maketext( "Failed to add “[_1]” to the services cluster. Installation failed with: [_2]", $host, _get_ansible_error($_) );
    };

    if ( %$prefixed_annotations || %$prefixed_labels ) {

        my $node_name = _identify_node_for_host($host);

        if ( !$node_name ) {
            $metadata->set_not_ok( locale()->maketext("Failed to identify node after installation; could not add labels or annotations.") );
            return;
        }

        try {
            $orch->set_node_metadata( $node_name, $prefixed_labels, $prefixed_annotations );
            $metadata->set_ok();
        }
        catch {
            die locale()->maketext( "Failed to apply labels and annotations to “[_1]”: [_2]", $host, _get_ansible_error($_) );
        };

    }
    else {
        $metadata->set_ok();
    }

    return;
}

sub delete_services_cluster_node ( $args, $metadata, $ ) {

    # TODO?: Cpanel::LoadModule::Custom::load_perl_module (used in xml-api.pl to load the API modules) prevents
    #        loaded modules from modifying @INC when they're loaded, so no use lib for this yet.
    local @INC = _get_cpsc_inc();
    require CPSC;

    if ( !$args->{host} ) {
        $metadata->set_not_ok( locale()->maketext("You must provide the hostname or IP address of the node to delete.") );
        return;
    }

    if ( !_identify_node_for_host( $args->{host} ) ) {
        $metadata->set_not_ok( locale()->maketext( "Could not identify a node in the cluster for “[_1]”.", $args->{host} ) );
        return;
    }

    # TODO: CPSC currently just dumps the full output from Ansible as part of the error message thrown.
    # Setting this ENV var here will put that output into a machine-parseable format in a best effort to
    # get a friendly error message from the output.
    local $ENV{'ANSIBLE_STDOUT_CALLBACK'} = 'json';

    try {
        CPSC->instance->orch->del_nodes( [ $args->{host} ] );
        $metadata->set_ok();
    }
    catch {
        die locale()->maketext( "Failed to delete node “[_1]”. Deletion failed with: [_2]", $args->{host}, _get_ansible_error($_) );
    };

    return;
}

sub list_services_cluster_nodes ( $args, $metadata, $ ) {

    # TODO?: Cpanel::LoadModule::Custom::load_perl_module (used in xml-api.pl to load the API modules) prevents
    #        loaded modules from modifying @INC when they're loaded, so no use lib for this yet.
    local @INC = _get_cpsc_inc();
    require CPSC;

    my $nodes_hr = CPSC->instance->orch->get_node_metadata();

    my $nodes_ar = [];

    # Flatten the nodes list so the WHM API extras like filters work
    for my $hostname ( keys %$nodes_hr ) {
        push @$nodes_ar, { hostname => $hostname, %{ $nodes_hr->{$hostname} } };
    }

    $metadata->set_ok();

    return { payload => $nodes_ar };
}

##############################
#### non-API-call util func ##
##############################

my $cpsc;

sub get_cpsc_obj_if_possible() {
    return $cpsc if $cpsc;

    require Cpanel::Server::Type::Role::CloudController;
    return if !Cpanel::Server::Type::Role::CloudController->is_enabled();

    $cpsc = eval {
        local @INC = _get_cpsc_inc();
        require CPSC;
        return CPSC->instance;
    };

    if ($cpsc) {
        @INC = _get_cpsc_inc();    # keep @INC set for further modules to be loaded
        return $cpsc;
    }

    return;
}

###############
#### helpers ##
###############

sub _get_cpsc_inc() {
    return ( "/opt/cpanel/services-cluster/lib", @INC );
}

sub _staging_file_is_unpopulated () {
    if ( !-e $CPSC::Util::INVENTORY_STAGING_PATH || -z $CPSC::Util::INVENTORY_STAGING_PATH ) {
        return 1;
    }
    return;
}

sub _identify_node_for_host ($host) {

    my $node_ip_info = CPSC->instance->orch->get_node_ip_info();

    for my $hostname ( keys %$node_ip_info ) {

        if ( $hostname eq $host ) {
            return $hostname;
        }
        else {
            for my $type (qw(external internal)) {
                if ( grep { $_ eq $host } @{ $node_ip_info->{$hostname}{$type} } ) {
                    return $hostname;
                }
            }
        }
    }

    return;
}

sub _get_ansible_error ($output_text) {

    my ($raw_output) = $output_text =~ m{\[OUTPUT\](.+?)\[/OUTPUT\]}s;

    my $data = eval { Cpanel::JSON::Load($raw_output) };
    return $raw_output if $@;

    my $last_play = ${ $data->{plays} }[-1];
    my $last_task = ${ $last_play->{tasks} }[-1];
    my $host_key  = ( keys %{ $last_task->{hosts} } )[0];
    my $msg       = $last_task->{hosts}{$host_key}{msg};

    return $msg;
}

sub _open_rw_transaction ( $debug = 0 ) {
    local @INC = _get_cpsc_inc();
    require CPSC::Util;

    my $txn;

    if ($debug) {
        $txn = Cpanel::Transaction::File::JSON->new(
            path => $CPSC::Util::INVENTORY_STAGING_PATH,
        );
    }
    else {
        my $gid = ( Cpanel::PwCache::getpwnam_noshadow('root') )[3];

        $txn = Cpanel::Transaction::File::JSON->new(
            path        => $CPSC::Util::INVENTORY_STAGING_PATH,
            permissions => 0600,
            ownership   => [ 0, $gid ],
        );
    }

    # Initialize empty/nonexistent file.
    if ( -z $CPSC::Util::INVENTORY_STAGING_PATH ) {
        $txn->set_data( { nodes => [] } );
        $txn->save_or_die();
    }

    return $txn;
}

sub _open_ro_transaction () {
    local @INC = _get_cpsc_inc();
    require CPSC::Util;

    my $txn = Cpanel::Transaction::File::JSONReader->new( path => $CPSC::Util::INVENTORY_STAGING_PATH );
    return $txn;
}

1;

__END__

=encoding utf-8

=head1 get_cpsc_obj_if_possible()

Function (not API call) that takes no arguments.

Returns CPSC object if possible (licensed and loadable), false otherwise.

    require Whostmgr::API::1::ServicesCluster;
    if ( my $cpsc = Whostmgr::API::1::ServicesCluster::get_cpsc_obj_if_possible() ) {
        # Do something w/ $cpsc object or do something based on the fact that the cloud code is available
    }

If it returns an object C<@INC> will also be set for further CPSC module loading (which happens lazily).
