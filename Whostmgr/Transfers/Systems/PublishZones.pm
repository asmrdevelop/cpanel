package Whostmgr::Transfers::Systems::PublishZones;

# cpanel - Whostmgr/Transfers/Systems/PublishZones.pm
#                                                  Copyright 2022 cPanel, L.L.C.
#                                                           All rights reserved.
# copyright@cpanel.net                                         http://cpanel.net
# This code is subject to the cPanel license. Unauthorized copying is prohibited

use cPstrict;

use Cpanel::Config::userdata::Load ();
use Cpanel::DnsUtils::Fetch        ();
use Whostmgr::Transfers::State     ();
use Cpanel::DnsUtils::AskDnsAdmin  ();

use base qw(
  Whostmgr::Transfers::Systems
);

=encoding utf-8

=head1 NAME

Whostmgr::Transfers::Systems::PublishZones - Publish Zones to the DNS Cluster

=head1 SYNOPSIS

    use Whostmgr::Transfers::Systems::PublishZones;

=head1 DESCRIPTION

The system will only do the dns operations on the local machine when an account is being
transfered from a remote server in order to prevent the intermediate changes from being
sent out to the cluster before the server is ready to service the account.  This is
done to avoid making the account live on the new system before the restore is complete
where an account is being moved around between systems that are
in the same DNS cluster.

If the system is not doing a transfer this module will only reload the zones that
have been changed by the modules that have come before it.

=cut

=head2 get_phase()

Phase 95 is done right before PostRestoreActions

=cut

sub get_phase {
    return 95;
}

=head2 get_summary()

Provide a summary to display in the UI

=cut

sub get_summary {
    my ($self) = @_;
    return [ $self->_locale()->maketext('This module ensures all zones have been synced out and reloaded across the [output,abbr,DNS,Domain Name System] cluster.') ];
}

=head2 get_restricted_available()

Determines if restricted restore mode is available

=cut

sub get_restricted_available {
    return 1;
}

*restricted_restore = \&unrestricted_restore;

=head2 unrestricted_restore()

Only intended to be called by the transfer restore system.

=cut

sub _do_remote_xferpoint_if_needed ($self) {

    my $utils_obj = $self->utils();

    my $pre_dns_restore_cr = $utils_obj->{'flags'}{'pre_dns_restore'};

    if ( 'CODE' eq ref $pre_dns_restore_cr ) {
        my $old_username = $self->olduser();
        my $new_username = $self->newuser();

        my $source = $utils_obj->get_source_hostname_or_ip();

        $self->start_action("Altering $source’s “$old_username” account …");

        my $parked_ar = Cpanel::Config::userdata::Load::get_parked_domains($new_username);
        my $addons_ar = Cpanel::Config::userdata::Load::get_addon_domains($new_username);

        $pre_dns_restore_cr->( @$parked_ar, @$addons_ar );
    }

    return;
}

sub unrestricted_restore {
    my ($self) = @_;

    $self->_do_remote_xferpoint_if_needed();

    my @domains          = $self->{'_utils'}->domains();
    my %restored_domains = map { $_ => 1 } @domains;
    my $zone_map_ref     = Cpanel::DnsUtils::Fetch::fetch_zones( 'zones' => [ keys %restored_domains ], 'flags' => $Cpanel::DnsUtils::AskDnsAdmin::LOCAL_ONLY );

    if ( Whostmgr::Transfers::State::is_transfer() ) {
        $self->start_action('Syncing zones to the dns cluster');

        # case CPANEL-20669: we always need to reload zones at this point
        # since when we do transfers we use LOCAL_ONLY until we have updated
        # the ip addresses.  This ensures that the slaves in the dns cluster are
        # updated with the correct IPs module before we reload
        # the zones.
        # Account Transfer do local only and we do the DNS cluster sync
        # here at the end of the restoration.
        if ( scalar keys %$zone_map_ref ) {
            $self->start_action( $self->_locale()->maketext( "Cluster Zone Updates: [list_and_quoted,_1]", [ sort keys %$zone_map_ref ] ) );
            my %http_query;
            @http_query{ map { "cpdnszone-$_" } keys %$zone_map_ref } = values %$zone_map_ref;
            Cpanel::DnsUtils::AskDnsAdmin::askdnsadmin(
                'SYNCZONES',
                $Cpanel::DnsUtils::AskDnsAdmin::REMOTE_AND_LOCAL, q{}, q{}, q{},
                \%http_query,
            );
        }

    }

    # This is the only place that the zones get reloaded during a restore
    $self->start_action('Reloading zones');
    if ( scalar keys %$zone_map_ref ) {
        Cpanel::DnsUtils::AskDnsAdmin::askdnsadmin( 'RELOADZONES', $Cpanel::DnsUtils::AskDnsAdmin::REMOTE_AND_LOCAL, join( ',', sort keys %$zone_map_ref ) );
    }

    return 1;
}

1;
