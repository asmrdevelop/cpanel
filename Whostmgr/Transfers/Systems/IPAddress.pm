package Whostmgr::Transfers::Systems::IPAddress;

# cpanel - Whostmgr/Transfers/Systems/IPAddress.pm Copyright 2022 cPanel, L.L.C.
#                                                           All rights reserved.
# copyright@cpanel.net                                         http://cpanel.net
# This code is subject to the cPanel license. Unauthorized copying is prohibited

use strict;

# RR Audit: JNK

use base qw(
  Whostmgr::Transfers::Systems
);

use Try::Tiny;

use AcctLock                   ();
use Cpanel::DIp                ();
use Cpanel::DIp::Group         ();
use Cpanel::DomainIp           ();
use Whostmgr::Accounts::SiteIP ();

sub get_prereq {
    return ['Account'];
}

sub get_phase {
    return 10;
}

sub get_summary {
    my ($self) = @_;
    return [ $self->_locale()->maketext('This sets up a dedicated IP address.') ];
}

sub get_restricted_available {
    return 1;
}

*unrestricted_restore = \&restricted_restore;

sub restricted_restore {
    my ($self) = @_;

    # This module is only useful for dedicated IP addresses.
    return 1 if !$self->{'_utils'}{'flags'}{'ip'};

    # Always run this module as the Account module may not
    # be able to assign a dedicated IP if its restoring
    # to a reseller that does not have the priv

    my $user = $self->newuser();

    my $domain = $self->{'_utils'}->main_domain();

    # Test if the domain already has a dedicated ip
    my ( $is_already_dedicated, $old_ip ) = _does_domain_already_have_dedicated_ip($domain);

    # Only proceed if the ip is not already dedicated
    if ($is_already_dedicated) {
        $self->out( $self->_locale()->maketext( 'The account “[_1]” already has a dedicated IP address.', $user ) );

        return 1;
    }

    AcctLock::acctlock();

    my @return;

    try {
        # Get the whatever dedicated ips we have left
        my @available_ips = Cpanel::DIp::Group::get_available_ips( $self->new_owner() );

        # If there is one left, assign it
        if (@available_ips) {
            my $new_ip;
            my $custom_ip = $self->{'_utils'}->{'flags'}->{'customip'};
            if ($custom_ip) {

                # No need to validate the IP because we are checking it against the list of
                # valid available ips.
                if ( grep { $_ eq $custom_ip } @available_ips ) {
                    $new_ip = $custom_ip;
                }
                else {
                    $self->warn( $self->_locale()->maketext( 'The IP address that you requested, “[_1]”, is not available. The system will use one of your available unused IP addresses instead.', $custom_ip ) );
                }
            }

            if ( !$new_ip ) {
                my $original_ip = $self->{'_utils'}->get_ip_address_from_cpuser_data();
                if ($original_ip) {

                    # No need to validate the IP because we are checking it against the list of
                    # valid available ips.
                    if ( grep { $_ eq $original_ip } @available_ips ) {
                        $new_ip = $original_ip;
                    }
                    else {
                        $self->warn( $self->_locale()->maketext( 'The original [asis,IP] address, “[_1]”, is not available. The system will use one of your available unused [asis,IP] addresses instead.', $original_ip ) );
                    }
                }
            }

            $new_ip ||= $available_ips[0];

            $self->out("Assigning IP address $new_ip to account $user …");
            @return = Whostmgr::Accounts::SiteIP::set( $user, undef, $new_ip, 1 );
        }
        else {
            @return = ( 0, $self->_locale()->maketext('There are no IP addresses on this system that are available to assign to the account.') );
        }
    }
    catch {
        AcctLock::unacctlock();
        die $_;
    };

    AcctLock::unacctlock();

    return @return ? @return : 1;
}

#
# Test if a domain already has a dedicated IP address
# NOTE: This function's two-arg return does NOT match the usual pattern;
# the 2nd value is always the old IP address, never an error message.
#
sub _does_domain_already_have_dedicated_ip {
    my ($domain) = @_;

    Cpanel::DomainIp::clear_domain_ip_cache();

    my $old_ip = Cpanel::DomainIp::getdomainip($domain);

    my $ip_info_hr = Cpanel::DIp::get_ip_info();

    # If the ip doesn't appear in the list and an info hash, then it is not dedicated to the domain
    my $is_dedicated = ( ref $ip_info_hr->{$old_ip} eq 'HASH' ) && $ip_info_hr->{$old_ip}{'dedicated'} && $ip_info_hr->{$old_ip}{'dedicated'} eq $domain;

    # The ip is not dedicated to the domain
    return ( ( $is_dedicated ? 1 : 0 ), $old_ip );
}

1;
