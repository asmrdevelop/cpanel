package Whostmgr::DNS::Cluster;

# cpanel - Whostmgr/DNS/Cluster.pm                 Copyright 2022 cPanel, L.L.C.
#                                                           All rights reserved.
# copyright@cpanel.net                                         http://cpanel.net
# This code is subject to the cPanel license. Unauthorized copying is prohibited

use cPstrict;

use Cpanel::DnsUtils::Cluster            ();
use Cpanel::Exception                    ();
use Cpanel::Reseller                     ();
use Cpanel::Validate::FilesystemNodeName ();
use Cpanel::Locale ('lh');

use Whostmgr::DNS::Cluster::UI ();
use Whostmgr::ACLS             ();

=encoding utf-8

=head1 NAME

Whostmgr::DNS::Cluster - Utility functions for clustered DNS

=head1 SYNOPSIS

    use Whostmgr::DNS::Cluster;

    Whostmgr::DNS::Cluster::is_enabled();
    Whostmgr::DNS::Cluster::enable();
    Whostmgr::DNS::Cluster::disable();

=head1 DESCRIPTION

This module contains utility functions related to clustered DNS.

=head1 FUNCTIONS

=head2 is_enabled()

Determines whether or not DNS clustering is enabled on the server.

=cut

sub is_enabled() {
    return Cpanel::DnsUtils::Cluster::is_clustering_enabled();
}

=head2 enable()

Enable dnscluster for this server.

=cut

sub enable() {

    require Cpanel::FileUtils::TouchFile;
    Cpanel::FileUtils::TouchFile::touchfile(Cpanel::DnsUtils::Cluster::USING_CLUSTERED_DNS_TOUCHFILE);

    return;
}

=head2 disable()

Disable dnscluster for this server.

Note: dies on failure.

=cut

sub disable() {

    require Cpanel::Autodie;
    Cpanel::Autodie::unlink_if_exists(Cpanel::DnsUtils::Cluster::USING_CLUSTERED_DNS_TOUCHFILE);

    return;
}

sub configure_provider (%config) {

    my $cluster_user = $config{'cluster_user'}
      or die Cpanel::Exception::create( 'MissingParameter', 'The required parameter “[_1]” is not set.', ['cluster_user'] );

    my $dnsrole = $config{'dnsrole'}
      or die Cpanel::Exception::create( 'MissingParameter', 'The required parameter “[_1]” is not set.', ['dnsrole'] );

    my $module = $config{'module'}
      or die Cpanel::Exception::create( 'MissingParameter', 'The required parameter “[_1]” is not set.', ['module'] );

    my $pkg = "Cpanel::NameServer::Setup::Remote::$module";
    require Cpanel::LoadModule;
    Cpanel::LoadModule::load_perl_module($pkg);

    my ( $status, $statusmsg, $notices, $servername ) = eval { $pkg->can('setup')->( $pkg, %config ) };
    if ( !$status ) {
        return ( 0, lh()->maketext( "Failed to set up DNS cluster for module “[_1]”.", $module ), $notices );
    }

    require Cpanel::DNSLib::PeerConfig;
    my $change_role_msg;
    ( $status, $change_role_msg ) = Cpanel::DNSLib::PeerConfig::change_dns_role( $servername, $dnsrole, $cluster_user );

    if ( length $change_role_msg ) {
        $statusmsg //= '';
        $statusmsg .= "\n" if length $statusmsg;
        $statusmsg .= $change_role_msg;
    }

    # Invalidate cache for cluster member
    require Cpanel::DNSLib::PeerStatus;
    Cpanel::DNSLib::PeerStatus::invalidate_and_refresh_cache( $cluster_user, $servername );

    return ( $status, $statusmsg, $notices );
}

#This fairly specialized logic accepts two usernames and,
#if the first is a reseller *and* WHM is running as root,
#will return the first username; otherwise, return the second.
#
#Before returning, it verifies that the username is a valid filesystem node.
#
sub get_validated_cluster_user_from_formenv {
    my ( $form_cluster_user, $env_remote_user ) = @_;

    my $has_root = Whostmgr::ACLS::hasroot();
    my $cluster_user;

    if ($has_root) {
        if ( $form_cluster_user && Cpanel::Reseller::isreseller($form_cluster_user) ) {
            $cluster_user = $form_cluster_user;
        }
        elsif ( $env_remote_user =~ m{^cp[0-9]+[a-zA-Z]+} ) {
            $cluster_user = 'root';
        }
    }

    $cluster_user ||= $env_remote_user;

    if ( !Cpanel::Validate::FilesystemNodeName::is_valid($cluster_user) ) {
        Whostmgr::DNS::Cluster::UI::fatal_error_and_exit( lh()->maketext( "“[_1]” is not a valid username.", $cluster_user ) );
    }

    return $cluster_user;
}

#This returns an array ref of names of all resellers that can do clustering
#--i.e., either the "clustering" ACL or root privs.
#
sub get_users_with_clustering {
    my $resellers_acls_hash = Cpanel::Reseller::getresellersaclhash();

    #Don't alter the global state of the hashref, "in case" C::Reseller
    #just gave us something that's its own internal state.
    #XXX: As of 11.48, this is indeed the case, so the "local" here is
    #necessary to avoid altering C::Reseller's internal state.
    local $resellers_acls_hash->{'root'} = { 'all' => 1 };

    return [
        map {    #
            {    #
                'user' => $_,                           #
                'acls' => $resellers_acls_hash->{$_}    #
            }    #
          }    #
          grep { $_ eq 'root' || $resellers_acls_hash->{$_}{'all'} || $resellers_acls_hash->{$_}{'clustering'} }
          keys %{$resellers_acls_hash}
    ];
}

1;
