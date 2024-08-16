package Whostmgr::Transfers::Systems::MailRouting;

# cpanel - Whostmgr/Transfers/Systems/MailRouting.pm
#                                                  Copyright 2022 cPanel, L.L.C.
#                                                           All rights reserved.
# copyright@cpanel.net                                         http://cpanel.net
# This code is subject to the cPanel license. Unauthorized copying is prohibited

use strict;
## no critic qw(TestingAndDebugging::RequireUseWarnings) -- not yet warnings safe
#
# RR Audit: JNK

use Cpanel::Email::MX            ();
use Cpanel::Locale               ();
use Cpanel::Domain::Zone         ();
use Cpanel::MailTools::DBS       ();
use Cpanel::ZoneFile::Collection ();
use Whostmgr::DNS::MX            ();

our @VALID_CHECKMX_VALUES = qw( 0 1 2 remote secondary local auto );

use base qw(
  Whostmgr::Transfers::Systems
);

sub get_phase { return 75; }

sub get_prereq {
    return ['ZoneFile'];
}

sub get_summary {
    my ($self) = @_;
    return [ $self->_locale()->maketext('This updates [output,abbr,MX,Mail eXchange] records.') ];
}

sub get_restricted_available {
    return 1;
}

sub unrestricted_restore {
    my ($self) = @_;

    $self->start_action('Update mail routing');

    my @domains = $self->{'_utils'}->domains();

    my $mxchecks_ref = $self->_get_mxchecks_from_cpusers();
    my ($cpuser_ref) = $self->{'_utils'}->get_cpuser_data();

    my $domain_zone_obj                      = Cpanel::Domain::Zone->new();
    my $zones_hr                             = ( $domain_zone_obj->get_zones_for_domains( \@domains ) )[1];
    my $zone_file_objs_hr                    = Cpanel::ZoneFile::Collection::create_zone_file_objs($zones_hr);
    my $zone_file_ipdbs_hr                   = Whostmgr::DNS::MX::create_ipdbs_for_zonefile_objs($zone_file_objs_hr);
    my $system_mail_routing_config_by_domain = Cpanel::MailTools::DBS::fetch_system_mail_routing_config_by_domain();
    my %possible_zones_by_domain             = map { $_ => [ $domain_zone_obj->get_possible_zones_for_domain($_) ] } @domains;
    my @setup;

    foreach my $domain (@domains) {
        my $entries_ref = Whostmgr::DNS::MX::fetchmx_ref_nodetect(
            $domain,
            $zones_hr,
            $system_mail_routing_config_by_domain,
            $cpuser_ref,
            $zone_file_objs_hr,
            $zone_file_ipdbs_hr,
            $possible_zones_by_domain{$domain}
        );

        #
        # service (formerly proxy) subdomains need to disabled for autodiscover and autoconfig if the domain is remote
        # checkmx also takes care of updating /etc/remotedomains and /etc/localdomains and /etc/secondarymx
        #
        my $checkmx = Whostmgr::DNS::MX::checkmx(
            $domain,
            $entries_ref->{'entries'},
            ( $mxchecks_ref->{$domain} || $entries_ref->{'alwaysaccept'} ),
            $Whostmgr::DNS::MX::NO_UPDATEUSERDOMAINS,
            $Whostmgr::DNS::MX::NO_UPDATE_PROXY_SUBDOMAINS,    # service (formerly proxy) Subdomains will do this
            $system_mail_routing_config_by_domain,
            $cpuser_ref,
            $Whostmgr::DNS::MX::NO_MODIFY_MAIL_ROUTING
        );

        my $detected = $checkmx->{'detected'};
        push @setup, [
            $domain,
            'localdomains', $detected eq 'local' ? 1 : 0,
            'remotedomains', ( $detected eq 'remote' || $detected eq 'secondary' ) ? 1 : 0,
            'secondarymx', $detected eq 'secondary' ? 1 : 0,
        ];

        my ( $set, $status, $method, $warnings ) = Cpanel::Email::MX::get_mxcheck_messages( $domain, $checkmx );

        $self->out("$status$method");

        if ( $warnings && ref @$warnings ) {
            foreach (@$warnings) {
                $self->warn($_);
            }
        }
    }

    if (@setup) {
        Cpanel::MailTools::DBS::setup_mail_routing_for_domains( \@setup );
    }

    require Cpanel::SMTP::GetMX::Cache;
    Cpanel::SMTP::GetMX::Cache::delete_cache_for_domains( \@domains );

    # Give the MX changes a bit of time to propagate …
    require Cpanel::ServerTasks;
    Cpanel::ServerTasks::schedule_task( ['EximTasks'], 60, "build_remote_mx_cache" );

    return 1;
}

*restricted_restore = \&unrestricted_restore;

sub _get_mxchecks_from_cpusers {
    my ($self) = @_;

    my @domains = $self->{'_utils'}->domains();

    my %domain_list = map { $_ => 1 } @domains;

    my ( $ok, $original_cpuser_data ) = $self->{'_archive_manager'}->get_raw_cpuser_data_from_archive();
    $self->warn($original_cpuser_data) if !$ok;

    my %mxchecks;

    foreach my $key ( keys %{$original_cpuser_data} ) {
        if ( $key =~ m/^MXCHECK-(\S+)$/ ) {
            my $domain = $1;
            my $value  = $original_cpuser_data->{$key};

            if ( $domain_list{$domain} ) {
                if ( grep { $_ eq $value } @VALID_CHECKMX_VALUES ) {
                    $mxchecks{$domain} = Cpanel::Email::MX::cpuser_key_to_mx_compat($value);
                }
                else {
                    $self->warn( $self->_locale()->maketext( "The system ignored the [asis,MXCHECK] value “[_1]” for the domain “[_2]” because this [asis,MXCHECK] value is not valid.", $value, $domain ) );
                }
            }
            else {
                $self->warn( $self->_locale()->maketext( "The system ignored the [asis,MXCHECK] value “[_1]” for the domain “[_2]” because the system did not restore that domain.", $value, $domain ) );
            }
        }
    }
    return \%mxchecks;
}

1;
