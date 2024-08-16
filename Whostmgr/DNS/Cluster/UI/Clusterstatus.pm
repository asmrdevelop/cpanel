
# cpanel - Whostmgr/DNS/Cluster/UI/Clusterstatus.pm
#                                                  Copyright 2022 cPanel, L.L.C.
#                                                           All rights reserved.
# copyright@cpanel.net                                         http://cpanel.net
# This code is subject to the cPanel license. Unauthorized copying is prohibited

package Whostmgr::DNS::Cluster::UI::Clusterstatus;

use strict;
use warnings;

use Cpanel::Form               ();
use Cpanel::Template           ();
use Cpanel::ServerTasks        ();
use Whostmgr::HTMLInterface    ();
use Whostmgr::ACLS             ();
use Whostmgr::DNS::Trace       ();
use Cpanel::DNSLib::Config     ();
use Cpanel::Config::LoadCpConf ();
use Cpanel::License::CompanyID ();
use Symbol                     ();
use Whostmgr::DNS::Cluster     ();
use Whostmgr::DNS::Cluster::UI ();

use Cpanel::DNSLib::PeerStatus ();

our $VERSION            = '2.3';
our $CLUSTER_CONFIG_DIR = '/var/cpanel/cluster';
our @WRITE_DNS_ROLES    = qw(sync write-only);
our @VALID_DNS_ROLES    = ( 'standalone', @WRITE_DNS_ROLES );

sub render {
    Whostmgr::ACLS::init_acls();

    if ( !Whostmgr::ACLS::checkacl('clustering') ) {
        Whostmgr::HTMLInterface::defheader( '', '', '/scripts7/clusterstatus' );
        return Whostmgr::DNS::Cluster::UI::fatal_error_and_exit('Permission denied');
    }

    my %FORM = Cpanel::Form::parseform();

    my %TEMPLATE_DATA;

    my $cluster_user = Whostmgr::DNS::Cluster::get_validated_cluster_user_from_formenv( $FORM{'cluster_user'}, $ENV{'REMOTE_USER'} );

    if ( Whostmgr::ACLS::hasroot() ) {
        $TEMPLATE_DATA{'users_with_clustering'} = Whostmgr::DNS::Cluster::get_users_with_clustering();
    }

    my $clustering_is_enabled = ( -e '/var/cpanel/useclusteringdns' ? 1 : 0 );
    $TEMPLATE_DATA{'cluster_user'}  = $cluster_user;
    $TEMPLATE_DATA{'dnsclustering'} = $clustering_is_enabled;
    $TEMPLATE_DATA{'uniquedns'}     = 0;
    if ( -e "/var/cpanel/cluster/$cluster_user/uniquedns" && $TEMPLATE_DATA{'dnsclustering'} ) {
        $TEMPLATE_DATA{'uniquedns'} = 1;
    }
    $TEMPLATE_DATA{'hasroot'} = Whostmgr::ACLS::hasroot();

    if ( !$TEMPLATE_DATA{'hasroot'} && !$TEMPLATE_DATA{'dnsclustering'} ) {
        Whostmgr::HTMLInterface::defheader( '', '', '/scripts7/clusterstatus' );
        return Whostmgr::DNS::Cluster::UI::fatal_error_and_exit(q{DNS clustering is not enabled on this system. Please contact your administrator to enable it.});
    }

    if ($clustering_is_enabled) {
        my %status     = Cpanel::DNSLib::PeerStatus::getclusterstatus();
        my @dnsservers = ( @{ $status{sync} }, @{ $status{'write-only'} }, @{ $status{standalone} } );
        my @dnspeers   = map { $_->{host} } @dnsservers;

        $TEMPLATE_DATA{'dnsservers'}  = [ sort { $a->{'host'} cmp $b->{'host'} } @dnsservers ];
        $TEMPLATE_DATA{'dnspeers'}    = \@dnspeers;
        $TEMPLATE_DATA{'coordinator'} = $status{coordinator};
    }

    my $cpconf = Cpanel::Config::LoadCpConf::loadcpconf_not_copy();
    $TEMPLATE_DATA{'globaloptions'}{'autodisablethreshold'} = exists $cpconf->{'cluster_autodisable_threshold'} ? int( $cpconf->{'cluster_autodisable_threshold'} ) : 10;
    $TEMPLATE_DATA{'cluster_failure_notifications'} = exists $cpconf->{'cluster_failure_notifications'} ? int( $cpconf->{'cluster_failure_notifications'} ) : 1;

    my $ns_type_check = 1;
    if ( defined $FORM{'skip_companyid_check'} && $FORM{'skip_companyid_check'} ) {
        $ns_type_check = 0;
    }

    my $companyid = Cpanel::License::CompanyID::get_company_id();
    my @remotemodules;
    my %module_name_map;
    if ( opendir( my $module_setup_dir, '/usr/local/cpanel/Cpanel/NameServer/Setup/Remote' ) ) {
        foreach my $module ( sort { $b eq 'cPanel.pm' ? 999999 : ( $a eq 'cPanel.pm' ? -999999 : ( $a cmp $b ) ) } grep( /\.pm$/, readdir($module_setup_dir) ) ) {
            $module =~ s/\.pm//;
            my $module_name = 'cPanel';
            if ( $module ne 'cPanel' ) {
                eval " require Cpanel::NameServer::Setup::Remote::$module;";    ## no critic (ProhibitStringyEval)
                if ($@) {
                    print STDERR "Could not load Cpanel::Nameserver::Setup::Remote::$module;";
                    print STDERR $@;
                    next;
                }
                my $mod_obj    = Symbol::qualify( 'Cpanel::NameServer::Setup::Remote::' . $module );
                my $mod_config = $mod_obj->get_config();
                $module_name = $mod_config->{'name'};
                if ( defined $mod_config->{'companyids'} && $ns_type_check ) {
                    my @idlist = grep { $_ eq $companyid } @{ $mod_config->{'companyids'} };
                    next if scalar @idlist == 0;
                }
            }
            push @remotemodules, { 'name' => $module_name, 'value' => $module };
            $module_name_map{$module} = $module_name;
        }
    }
    $TEMPLATE_DATA{'module_name_map'} = \%module_name_map;
    $TEMPLATE_DATA{'remotemodules'}   = \@remotemodules;

    my $dns_trace = Whostmgr::DNS::Trace::get_peer_tree($cluster_user);

    $TEMPLATE_DATA{'dns_peer_tree'}                 = _proc_tree_node( $dns_trace->{'tree'}{'top'} );
    $TEMPLATE_DATA{'default_autodisable_threshold'} = $Cpanel::DNSLib::Config::DEFAULT_AUTODISABLE_THRESHOLD;

    #Refresh the cache before we load the page again.  Time to cheat.
    eval { Cpanel::ServerTasks::schedule_task( ['DNSAdminTasks'], 5, "clustercache $cluster_user" ) };

    return Cpanel::Template::process_template(
        'whostmgr',
        {
            'print'         => 1,
            'template_file' => 'clusterstatus.tmpl',
            'breadcrumburl' => '/scripts7/clusterstatus',
            'data'          => \%TEMPLATE_DATA,
        },
    );

}

sub _proc_tree_node {
    my $cur_handle_node = shift;
    my %cur_tree_node   = ( name => $cur_handle_node->{'key'} );
    if ( ref $cur_handle_node->{'children'} eq 'ARRAY' && scalar @{ $cur_handle_node->{'children'} } ) {
        my @children = map { _proc_tree_node($_) } @{ $cur_handle_node->{'children'} };
        $cur_tree_node{'children'} = \@children;
    }

    return \%cur_tree_node;
}

1;

__END__

=head1 NAME

Whostmgr::DNS::Cluster::UI::Clusterstatus

=head1 DESCRIPTION

Controller for the view clusterstatus.tmpl

=head1 SYNOPSIS

    require Whostmgr::DNS::Cluster::UI::Clusterstatus;
    Whostmgr::DNS::Cluster::UI::Clusterstatus::render();

=head1 SUBROUTINES

=head2 render()

Print everything needed to render the page aside from headers.
