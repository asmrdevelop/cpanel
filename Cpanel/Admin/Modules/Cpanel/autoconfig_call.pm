#!/usr/local/cpanel/3rdparty/bin/perl

# cpanel - Cpanel/Admin/Modules/Cpanel/autoconfig_call.pm
#                                                  Copyright 2022 cPanel, L.L.C.
#                                                           All rights reserved.
# copyright@cpanel.net                                         http://cpanel.net
# This code is subject to the cPanel license. Unauthorized copying is prohibited

package Cpanel::Admin::Modules::Cpanel::autoconfig_call;

use strict;
use warnings;

use base qw( Cpanel::Admin::Base );

use constant _actions__pass_exception => (
    'GENERATE_MOBILECONFIG',
    'DISPATCH_CLIENT_CONFIG'
);

# called via emailsetup-ios.cgi
use constant _allowed_parents => '*';

use constant _actions => (
    _actions__pass_exception(),
);

sub _demo_actions {
    return ();
}

sub DISPATCH_CLIENT_CONFIG {
    my ( $self, $ref ) = @_;

    require Cpanel::IP::Remote;
    require Cpanel::Validate::EmailRFC;
    require Cpanel::AccessControl;
    my $caller_username = $self->get_caller_username();
    if ( !Cpanel::AccessControl::user_has_access_to_account( $caller_username, $ref->{'account'} ) ) {
        die "The user “$caller_username” does not have access to an account named “$ref->{'account'}”.";
    }

    my $account = $ref->{'account'};
    if ( $account eq $caller_username ) {
        $account = "_mainaccount@" . $self->get_cpuser_domain();
    }
    $ref->{'to'} ||= $account;
    foreach my $param (qw{to cc}) {
        next if !length $ref->{$param};    # Will always be true for 'to'.
        Cpanel::Validate::EmailRFC::is_valid( $ref->{$param} ) or die "Invalid $param: $ref->{$param}";
    }

    if ( ( defined $ref->{'selected_account_services'} && !$ref->{'selected_account_services'} ) || !defined $ref->{'selected_account_services'} ) {
        $ref->{'selected_account_services'} = 'email,caldav,carddav';
    }
    my %account_services = map { $_ => 1 } split( /,/, $ref->{'selected_account_services'} );

    # Get the client_ref for the relevant service
    my $client_ref = {};
    if ( exists $account_services{'email'} ) {

        # We used to be checking to see if we needed to tack on _mainacct here,
        # but we already do this above, so there's no point in checking it again
        require Cpanel::Email::AutoConfig::Settings;
        $client_ref = Cpanel::Email::AutoConfig::Settings::client_settings($account);
    }
    if ( exists $account_services{'caldav'} || exists $account_services{'carddav'} ) {

        # XXX Also, to get these settings, you have to priv drop back
        # to the user, as it assumes we will be running as the effective user
        # ID of the webmail user's owning cpuser.
        require Cpanel::DAV::Config;
        require Cpanel::DAV::Provider;
        if ( Cpanel::DAV::Provider::installed() ) {
            $client_ref->{'cal_contacts_config'} = Cpanel::DAV::Config::get_calendar_contacts_config( $ref->{account} );
        }
        else {
            delete $account_services{'caldav'};
            delete $account_services{'carddav'};
        }
    }

    my @attachments;
    my $device = $ref->{'selected_device'} || 'apple';
    if ( $device eq 'apple' ) {

        require Cpanel::Email::Setup::MobileConfig;

        # get payloads for each attachment
        foreach my $service ( keys(%account_services) ) {
            my $payload = Cpanel::Email::Setup::MobileConfig::generate(
                'account'                   => $ref->{'account'},
                'use_ssl'                   => $ref->{'use_ssl'},
                'selected_account_services' => $service
            );
            push( @attachments, { name => $service . '-' . $ref->{'account'} . '.mobileconfig', content => \$payload, content_type => 'application/octet-stream' } );
        }
    }

    require Cpanel::Notify;
    Cpanel::Notify::notification_class(
        'class'            => 'Mail::ClientConfig',
        'application'      => 'Mail::ClientConfig',
        'constructor_args' => [
            %$client_ref,
            username                          => $caller_username,
            to                                => $ref->{'to'},
            account                           => $ref->{'account'},
            source_ip_address                 => Cpanel::IP::Remote::get_current_remote_ip(),
            origin                            => 'cpanel',
            attach_files                      => \@attachments,
            notification_targets_user_account => 1,
            notification_cannot_be_disabled   => 1,
            selected_account_services         => \%account_services,
            selected_device                   => $device,
            block_on_send                     => $ref->{'block_on_send'},
            ( $ref->{'cc'} ? ( extra_addresses_to_notify => $ref->{'cc'} ) : () ),
        ]
    );
    die @Cpanel::iContact::LAST_ERRORS if (@Cpanel::iContact::LAST_ERRORS);
    return 1;
}

sub GENERATE_MOBILECONFIG {
    my ( $self, $ref ) = @_;

    my $caller_username = $self->get_caller_username();
    require Cpanel::AccessControl;
    if ( Cpanel::AccessControl::user_has_access_to_account( $caller_username, $ref->{'account'} ) ) {
        require Cpanel::Email::Setup::MobileConfig;
        return Cpanel::Email::Setup::MobileConfig::generate(
            'account'                   => $ref->{'account'},
            'use_ssl'                   => $ref->{'use_ssl'},
            'selected_account_services' => $ref->{'selected_account_services'} || ''
        );
    }
    else {
        die "The user “$caller_username” does not have access to the account “$ref->{'account'}”.";
    }
}

#----------------------------------------------------------------------

1;
