package Cpanel::iContact::Class::ContactInfo::Change;

# cpanel - Cpanel/iContact/Class/ContactInfo/Change.pm
#                                                  Copyright 2022 cPanel, L.L.C.
#                                                           All rights reserved.
# copyright@cpanel.net                                         http://cpanel.net
# This code is subject to the cPanel license. Unauthorized copying is prohibited

use strict;

use parent qw(
  Cpanel::iContact::Class::FromUserAction
);

use Cpanel::ArrayFunc::Uniq  ();
use Cpanel::LoadModule       ();
use Cpanel::StringFunc::Case ();

my @required_args = (
    'user',

    #hashref of: {
    #   primary => [ $old => $new ],
    #   secondary => [ $old => $new ],
    #}
    'updated_email_addresses',

    #arrayref
    'extra_addresses_to_notify',

    #arrayref
    'disabled_notifications',
);

sub _required_args {
    my ($class) = @_;

    return (
        $class->SUPER::_required_args(),
        @required_args
    );
}

sub _icontact_args {
    my ($self) = @_;

    my $email_updates = $self->{'_opts'}{'updated_email_addresses'};

    my @to_addresses = map { @$_ } values %$email_updates;
    push @to_addresses, @{ $self->{'_opts'}{'extra_addresses_to_notify'} };
    @to_addresses = grep { length } @to_addresses;                             # updated_email_addresses may have an empty email and we don't want to send email to ''
    $_            = Cpanel::StringFunc::Case::ToLower($_) for @to_addresses;

    return (
        $self->SUPER::_icontact_args(),
        email => [ Cpanel::ArrayFunc::Uniq::uniq(@to_addresses) ],
    );
}

sub _template_args {
    my ($self) = @_;

    my @messages_about_disabled_settings = map { $self->_disabled_notification_text($_) } @{ $self->{'_opts'}{'disabled_notifications'} };

    return (
        $self->SUPER::_template_args(),

        messages_about_disabled_settings => \@messages_about_disabled_settings,

        map { $_ => $self->{'_opts'}{$_} } @required_args,
    );
}

my $_locale;

sub _locale {

    #The base class will probably have already loaded this by now,
    #but just in case.
    Cpanel::LoadModule::load_perl_module('Cpanel::Locale');

    return $_locale ||= Cpanel::Locale->get_handle();
}

sub _disabled_notification_text {
    my ( $self, $notification_key ) = @_;

    if ( $notification_key eq 'notify_password_change' ) {
        return _locale()->maketext('You will no longer receive notifications when your password changes.');
    }

    if ( $notification_key eq 'notify_password_change_notification_disabled' ) {
        return _locale()->maketext('You will no longer receive notifications when your password change notification preference changes.');
    }

    if ( $notification_key eq 'notify_account_login' ) {
        return _locale()->maketext('You will no longer receive notifications when you log in to your account.');
    }

    if ( $notification_key eq 'notify_account_login_notification_disabled' ) {
        return _locale()->maketext('You will no longer receive notifications when your account log in notification preference changes.');
    }

    if ( $notification_key eq 'notify_contact_address_change' ) {
        return _locale()->maketext('You will no longer receive notifications when your contact address changes.');
    }

    if ( $notification_key eq 'notify_contact_address_change_notification_disabled' ) {
        return _locale()->maketext('You will no longer receive notifications when your contact address change notification preference changes.');
    }

    if ( $notification_key eq 'notify_account_authn_link' ) {
        return _locale()->maketext('You will no longer receive notifications when an external account links to your account.');
    }

    if ( $notification_key eq 'notify_account_authn_link_notification_disabled' ) {
        return _locale()->maketext('You will no longer receive notifications when your account authentication link notification preference changes.');
    }

    if ( $notification_key eq 'notify_twofactorauth_change' ) {
        return _locale()->maketext('You will no longer receive notifications when your two-factor authentication configuration changes.');
    }

    if ( $notification_key eq 'notify_twofactorauth_change_notification_disabled' ) {
        return _locale()->maketext('You will no longer receive notifications when your two-factor authentication notification preference changes.');
    }

    #Should never happen
    die "Unrecognized notification key: $notification_key";
}

1;
