package Cpanel::SSL::Auto::Run::Notify;

# cpanel - Cpanel/SSL/Auto/Run/Notify.pm           Copyright 2022 cPanel, L.L.C.
#                                                           All rights reserved.
# copyright@cpanel.net                                         http://cpanel.net
# This code is subject to the cPanel license. Unauthorized copying is prohibited

use strict;
use warnings;

=encoding utf-8

=head1 NAME

Cpanel::SSL::Auto::Run::Notify

=head1 SYNOPSIS

    handle_TOTAL_DCV_FAILURE( $vhost_obj );

    handle_SECURED_DOMAIN_DCV_FAILURE( $vhost_obj );

    handle_NO_UNSECURED_DOMAIN_PASSED_DCV( $vhost_obj );

=head1 DESCRIPTION

This module handles the “notification-worthy” impediments on
a vhost insofar as notification is concerned. It sends notifications
to admin and/or the user as system configuration dictates.

See L<Cpanel::SSL::Auto::Run::HandleVhost> for more information
on the different impediments.

=cut

use Try::Tiny;

use Cpanel::ContactInfo             ();
use Cpanel::SSL::Auto::Config::Read ();
use Cpanel::SSL::VhostCheck         ();

my %NOTIFICATION_METADATA = (
    CertificateExpiringCoverage => 'notify_autossl_expiry_coverage',
    CertificateRenewalCoverage  => 'notify_autossl_renewal_coverage',
    CertificateExpiring         => 'notify_autossl_expiry',
);

my %SECURED_DOMAIN_DCV_FAILURE_status_notify_type = (
    renewal    => 'CertificateExpiringCoverage',
    incomplete => 'CertificateRenewalCoverage',
);

=head1 HANDLER FUNCTIONS

None of these returns anything, and they each accept an
instance of L<Cpanel::SSL::Auto::Run::Vhost>.

=head2 handle_TOTAL_DCV_FAILURE( VHOST_OBJ )

This sends an C<AutoSSL::CertificateExpiring> notification, but
only during the notify period.

=cut

#CertificateExpiring
sub handle_TOTAL_DCV_FAILURE {
    my ($vh_report) = @_;

    if ( $vh_report->get_certificate_object() && $vh_report->certificate_is_in_notify_period() ) {
        _notify_about_autossl_problem( 'CertificateExpiring', $vh_report );
    }

    return;
}

=head2 handle_SECURED_DOMAIN_DCV_FAILURE( VHOST_OBJ )

This sends an C<AutoSSL::CertificateExpiringCoverage> notification for
C<renewal>-state virtual hosts and C<AutoSSL::CertificateRenewalCoverage>
for C<incomplete>-state virtual hosts, but only during the notify period.

=cut

#CertificateExpiringCoverage
sub handle_SECURED_DOMAIN_DCV_FAILURE {
    my ($vh_report) = @_;

    if ( $vh_report->certificate_is_in_notify_period() ) {
        my $status      = $vh_report->determine_tls_state();
        my $notify_type = $SECURED_DOMAIN_DCV_FAILURE_status_notify_type{$status};

        if ($notify_type) {
            _notify_about_autossl_problem( $notify_type, $vh_report );
        }
        else {

            #shouldn’t happen
            warn "SECURED_DOMAIN_DCV_FAILURE: no notify type for status $status!";
        }
    }

    return;
}

#NB: There is currently no handler for NO_UNSECURED_DOMAIN_PASSED_DCV
#because that state as an impediment simply means that a valid certificate
#is incomplete and “has room” for more domains, but no unsecured domain
#passed DCV.

#----------------------------------------------------------------------

our $_autossl_config_metadata;

#mocked in tests
sub _get_autossl_config_metadata {
    return ( $_autossl_config_metadata ||= Cpanel::SSL::Auto::Config::Read->new()->get_metadata() );
}

my $_last_contact_info;
my $_last_username;

#mocked in tests
sub _get_contact_info_for_username {
    my ($username) = @_;

    if ( !$_last_username || $username ne $_last_username ) {
        $_last_contact_info = Cpanel::ContactInfo::get_contactinfo_for_user($username);
        $_last_username     = $username;
    }

    return $_last_contact_info;
}

sub _notify_about_autossl_problem {
    my ( $type, $vh_report ) = @_;

    my $vhost_name;

    my $full_type = "AutoSSL::$type";

    try {
        my $username     = $vh_report->get_username();
        my $contact_info = _get_contact_info_for_username($username);

        $vhost_name = $vh_report->name();

        my $metadata_key = $NOTIFICATION_METADATA{$type} or do {
            die "No metadata key for notification type “$type”!";
        };

        foreach my $target (qw(admin user)) {

            my $notification_type_is_enabled;

            #The user can opt out of the notification, an admin can also prevent the user from receiving them
            if ( $target eq 'user' ) {
                $notification_type_is_enabled = !!_get_autossl_config_metadata()->{"${metadata_key}_user"} && !!$contact_info->{$metadata_key};
            }
            else {
                $notification_type_is_enabled = !!_get_autossl_config_metadata()->{$metadata_key};
            }

            if ($notification_type_is_enabled) {
                _send_one_notification(
                    'vhost_name'  => $vhost_name,
                    'user'        => $username,
                    'certificate' => $vh_report->get_certificate_object(),
                    'target'      => $target,

                    # AutoSSL::CertificateExpiring is a child class of SSL::CertificateExpiring
                    # that will add the problems/queue info for the domain/vhost
                    # AutoSSL::CertificateRenewalCoverage is a child class of AutoSSL::CertificateExpiring as well.
                    'type' => $full_type,
                );
            }
        }

    }
    catch {
        warn "Failed to send $full_type notification for “$vhost_name”: $_";
    };

    return;
}

sub _send_one_notification {
    my (%opts) = @_;

    my ( $type, $vhost_name, $user, $certificate, $target ) = @opts{ 'type', 'vhost_name', 'user', 'certificate', 'target' };

    require Cpanel::Notify::Deferred;
    require Cpanel::IP::Remote;

    Cpanel::Notify::Deferred::notify(
        'class'            => $type,
        'application'      => $type,
        'constructor_args' => [
            _get_icontact_args_for_target( $target, $user ),
            notification_targets_user_account => 1,
            vhost_name                        => $vhost_name,
            origin                            => 'autossl_check',
            replace_after_time                => _must_replace_after($certificate),
            source_ip_address                 => Cpanel::IP::Remote::get_current_remote_ip(),
        ]
    );

    return;
}

# copied from scripts/notify_expiring_certificates
#XXX UGLY refactor/normalize
sub _get_icontact_args_for_target {
    my ( $target, $user ) = @_;

    my @args = ( username => $user );

    if ( $target eq 'user' ) {

        #It sucks that “username” and “user” are both here.
        #TODO: Find out if we can eliminate one of them.
        push @args, (
            user => $user,
            to   => $user,
        );
    }

    return @args;
}

# We now defer renewal of certificates that will have a reduction in coverage until
# we are within T-3 days of expiration. We now send a notification starting at
# T-DAYS_TO_REPLACE days if there would be a reduction in coverage
sub _must_replace_after {
    my ($certificate) = @_;

    die 'No certificate!' if !$certificate;

    #i.e., first second where it’s invalid
    my $expiry = 1 + $certificate->not_after();

    return $expiry - 86400 * $Cpanel::SSL::VhostCheck::MIN_VALIDITY_DAYS_LEFT_BEFORE_CONSIDERED_ALMOST_EXPIRED;
}

1;
