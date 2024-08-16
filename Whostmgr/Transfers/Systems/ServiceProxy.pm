package Whostmgr::Transfers::Systems::ServiceProxy;

# cpanel - Whostmgr/Transfers/Systems/ServiceProxy.pm
#                                                  Copyright 2022 cPanel, L.L.C.
#                                                           All rights reserved.
# copyright@cpanel.net                                         http://cpanel.net
# This code is subject to the cPanel license. Unauthorized copying is prohibited

use cPstrict;

=encoding utf-8

=head1 NAME

Whostmgr::Transfers::Systems::ServiceProxy

=head1 DESCRIPTION

This module is part of the account restoration system.
It subclasses L<Whostmgr::Transfers::Systems>; see that module
for more details.

=cut

#----------------------------------------------------------------------

use parent 'Whostmgr::Transfers::Systems';

use Cpanel::Imports;

use Cpanel::Config::LoadCpUserFile ();
use Cpanel::Domain::Local          ();
use Cpanel::IP::CpRapid            ();
use Cpanel::NAT                    ();
use Cpanel::Sys::Hostname          ();

use constant {
    get_restricted_available        => 1,
    minimum_transfer_source_version => 90,

    # v96 introduced the cPanel endpoint for ServiceProxy
    minimum_transfer_source_version_for_user => 96,

    get_phase => 99,
};

#----------------------------------------------------------------------

=head1 METHODS

=head2 I<OBJ>->get_summary()

POD for cplint. Don’t call this directly.

=cut

sub get_summary ($self) {
    return [ locale()->maketext('This module sets up applicable service proxying to the destination servers.') ];
}

=head2 I<OBJ>->restricted_restore( %OPTS )

POD for cplint. Don’t call this directly.

=cut

sub restricted_restore ($self) {

    my $utils = $self->utils();

    if ( !$utils->is_live_transfer() ) {
        $self->out( locale()->maketext('This module pertains to the [asis,Live Transfer] setting only.') );

        return 1;
    }

    my $source_host = $utils->get_source_hostname_or_ip();

    # In production we shouldn’t get this far, but on development/test
    # builds we might.
    if ( Cpanel::Domain::Local::domain_or_ip_is_on_local_server($source_host) ) {
        $self->out( locale()->maketext( 'The source server ([_1]) appears to be the local server. Skipping service proxy setup …', $source_host ) );
    }
    else {
        my $general_proxy_backend = $self->_get_general_proxy_backend();

        my @proxy_setup_args = (
            general => $general_proxy_backend,
        );

        my %service_backend;
        for my $svcgroup ( $self->_get_source_service_groups() ) {
            my $worker = $utils->get_target_worker_node($svcgroup);

            my $remote_hostname = $worker && $worker->hostname();
            $remote_hostname ||= Cpanel::Sys::Hostname::gethostname();

            $service_backend{$svcgroup} = $remote_hostname;
        }

        if (%service_backend) {
            push @proxy_setup_args, (
                service_group         => [ keys %service_backend ],
                service_group_backend => [ values %service_backend ],
            );
        }

        $self->out( locale()->maketext( 'Configuring the source server ([_1]) to proxy services to the new account …', $source_host ) );

        if ( $utils->{'flags'}{'restore_type'} eq 'root' ) {

            my $api = $utils->get_source_api_object(

                # On very large accounts it can take a while to
                # set up service proxying for httpd.
                timeout => 600,
            );

            push @proxy_setup_args, ( username => $self->olduser() );

            $api->request_whmapi1_or_die(
                'set_service_proxy_backends',
                {@proxy_setup_args},
            );

            $self->_log_mailbox_session_termination($source_host);

            $api->request_whmapi1_or_die(
                'terminate_cpuser_mailbox_sessions',
                { username => $self->olduser() },
            );

        }
        elsif ( $utils->{'flags'}{'restore_type'} eq 'user' ) {

            my $api = $utils->get_source_cpanel_api_object(

                # On very large accounts it can take a while to
                # set up service proxying for httpd.
                timeout => 600,
            );

            my $result = $api->request_uapi(
                'ServiceProxy',
                'set_service_proxy_backends',
                {@proxy_setup_args},
            );

            $self->_log_mailbox_session_termination($source_host);

            $api->request_uapi( 'Email', 'terminate_mailbox_sessions' );

        }
        else {
            Carp::confess "Invalid restore type: $utils->{'flags'}{'restore_type'}";
        }

    }

    return 1;
}

sub _log_mailbox_session_termination ( $self, $source_host ) {
    $self->out( locale()->maketext( 'Terminating “[_1]”’s mailbox sessions on “[_2]” …', $self->olduser(), $source_host ) );
    return;
}

# accessed in tests
sub _get_source_service_groups ($self) {

    # NOTE: Whenever we add another service group (aka worker),
    # we’ll need to ensure we don’t try to set a proxy backend for that
    # service group on the remote if the source doesn’t support it.
    # We’ll need to track that via the source cP & WHM version.
    return 'Mail';
}

sub _get_general_proxy_backend ($self) {
    my ($cpuser_obj) = Cpanel::Config::LoadCpUserFile::load_or_die( $self->newuser() );
    my $acct_ipv4 = $cpuser_obj->{'IP'};

    # sanity check:
    die "No IP in cpuser?!?" if !$acct_ipv4;

    $acct_ipv4 = Cpanel::NAT::get_public_ip($acct_ipv4);

    return Cpanel::IP::CpRapid::ipv4_to_name($acct_ipv4);
}

*unrestricted_restore = *restricted_restore;

#----------------------------------------------------------------------

1;
