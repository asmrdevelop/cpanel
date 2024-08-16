package Cpanel::Admin::Modules::Cpanel::WpToolkitNotification;

use strict;

use parent ('Cpanel::Admin::Base');

use Cpanel::iContact::Class::WPT::AdminSuspiciousInstance ();
use Cpanel::iContact::Class::WPT::ResellerSuspiciousInstance ();
use Cpanel::iContact::Class::WPT::ClientSuspiciousInstance ();
use Cpanel::iContact::Class::WPT::AdminAutoUpdates ();
use Cpanel::iContact::Class::WPT::ResellerAutoUpdates ();
use Cpanel::iContact::Class::WPT::ClientAutoUpdates ();
use Cpanel::iContact::Class::WPT::BlacklistedPluginDeactivated ();
use Cpanel::iContact::Class::WPT::VulnerabilityFound ();

use constant _actions => (
    'SEND_ADMIN_SUSPICIOUS_INSTANCE_NOTIFICATION',
    'SEND_RESELLER_SUSPICIOUS_INSTANCE_NOTIFICATION',
    'SEND_CLIENT_SUSPICIOUS_INSTANCE_NOTIFICATION',
    'SEND_ADMIN_AUTO_UPDATES_NOTIFICATION',
    'SEND_RESELLER_AUTO_UPDATES_NOTIFICATION',
    'SEND_CLIENT_AUTO_UPDATES_NOTIFICATION',
    'SEND_BLACKLISTED_PLUGIN_DEACTIVATED_NOTIFICATION',
    'SEND_ADMIN_BLACKLISTED_PLUGIN_DEACTIVATED_NOTIFICATION',
    'SEND_VULNERABILITY_FOUND_NOTIFICATION',
    'SEND_ADMIN_VULNERABILITY_FOUND_NOTIFICATION',
);

sub SEND_ADMIN_SUSPICIOUS_INSTANCE_NOTIFICATION {
    my ($self, @args) = @_;

    $self->cpuser_has_feature_or_die("wp-toolkit");

    Cpanel::iContact::Class::WPT::AdminSuspiciousInstance->new(
        # This identifies the application that sends the notification
        # This, when set, is also used for Contact Manager notification settings
        'origin'           => 'wp_toolkit',
        # Any additional variables that the specific template needs will be set here.
        'suspicious_instance_text' => @args[0],
        'suspicious_instance_details_info' => @args[1],
    );

    return 1;
}

sub SEND_RESELLER_SUSPICIOUS_INSTANCE_NOTIFICATION {
    my ($self, @args) = @_;

    $self->cpuser_has_feature_or_die("wp-toolkit");

    my $username = $self->get_caller_username();

    Cpanel::iContact::Class::WPT::ResellerSuspiciousInstance->new(
        # If the notification is going to a user, it's the username.
        # Otherwise, exclude this and it goes to root.
        'to'         => $username,
        # This identifies the application that sends the notification
        # This, when set, is also used for Contact Manager notification settings
        'origin'           => 'wp_toolkit',
        # Any additional variables that the specific template needs will be set here.
        'suspicious_instance_text' => @args[0],
        'suspicious_instance_details_info' => @args[1],
    );

    return 1;
}

sub SEND_CLIENT_SUSPICIOUS_INSTANCE_NOTIFICATION {
    my ($self, @args) = @_;

    $self->cpuser_has_feature_or_die("wp-toolkit");

    my $username = $self->get_caller_username();

    Cpanel::iContact::Class::WPT::ClientSuspiciousInstance->new(
        # If the notification is going to a user, it's the username.
        # Otherwise, exclude this and it goes to root.
        'to'         => $username,
        # This identifies the application that sends the notification
        # This, when set, is also used for Contact Manager notification settings
        'origin'           => 'wp_toolkit',
        # Any additional variables that the specific template needs will be set here.
        'suspicious_instance_text' => @args[0],
        'suspicious_instance_details_info' => @args[1],
    );

    return 1;
}

sub SEND_ADMIN_AUTO_UPDATES_NOTIFICATION {
    my ($self, @args) = @_;

    $self->cpuser_has_feature_or_die("wp-toolkit");

    Cpanel::iContact::Class::WPT::AdminAutoUpdates->new(
        # This identifies the application that sends the notification
        # This, when set, is also used for Contact Manager notification settings
        'origin'           => 'wp_toolkit',
        # Any additional variables that the specific template needs will be set here.
        'failure_updates_text' => @args[0],
        'failure_updates_list' => @args[1],
        'available_updates_text' => @args[2],
        'available_updates_list' => @args[3],
        'installed_updates_text' => @args[4],
        'installed_updates_list' => @args[5],
        'requirements_updates_text' => @args[6],
        'requirements_updates_list' => @args[7]
    );

    return 1;
}

sub SEND_RESELLER_AUTO_UPDATES_NOTIFICATION {
    my ($self, @args) = @_;

    $self->cpuser_has_feature_or_die("wp-toolkit");

    my $username = $self->get_caller_username();

    Cpanel::iContact::Class::WPT::ResellerAutoUpdates->new(
        # If the notification is going to a user, it's the username.
        # Otherwise, exclude this and it goes to root.
        'to'         => $username,
        # This identifies the application that sends the notification
        # This, when set, is also used for Contact Manager notification settings
        'origin'           => 'wp_toolkit',
        # Any additional variables that the specific template needs will be set here.
        'failure_updates_text' => @args[0],
        'failure_updates_list' => @args[1],
        'available_updates_text' => @args[2],
        'available_updates_list' => @args[3],
        'installed_updates_text' => @args[4],
        'installed_updates_list' => @args[5],
        'requirements_updates_text' => @args[6],
        'requirements_updates_list' => @args[7]
    );

    return 1;
}

sub SEND_CLIENT_AUTO_UPDATES_NOTIFICATION {
    my ($self, @args) = @_;

    $self->cpuser_has_feature_or_die("wp-toolkit");

    my $username = $self->get_caller_username();

    Cpanel::iContact::Class::WPT::ClientAutoUpdates->new(
        # If the notification is going to a user, it's the username.
        # Otherwise, exclude this and it goes to root.
        'to'         => $username,
        # This identifies the application that sends the notification
        # This, when set, is also used for Contact Manager notification settings
        'origin'           => 'wp_toolkit',
        # Any additional variables that the specific template needs will be set here.
        'failure_updates_text' => @args[0],
        'failure_updates_list' => @args[1],
        'available_updates_text' => @args[2],
        'available_updates_list' => @args[3],
        'installed_updates_text' => @args[4],
        'installed_updates_list' => @args[5],
        'requirements_updates_text' => @args[6],
        'requirements_updates_list' => @args[7]
    );

    return 1;
}

sub SEND_BLACKLISTED_PLUGIN_DEACTIVATED_NOTIFICATION {
    my ($self, @args) = @_;

    $self->cpuser_has_feature_or_die("wp-toolkit");

    my $username = $self->get_caller_username();

    Cpanel::iContact::Class::WPT::BlacklistedPluginDeactivated->new(
        # If the notification is going to a user, it's the username.
        # Otherwise, exclude this and it goes to root.
        'to'         => $username,
        # This identifies the application that sends the notification
        # This, when set, is also used for Contact Manager notification settings
        'origin'           => 'wp_toolkit',
        # Any additional variables that the specific template needs will be set here.
        'message' => @args[0]
    );

    return 1;
}

sub SEND_ADMIN_BLACKLISTED_PLUGIN_DEACTIVATED_NOTIFICATION {
    my ($self, @args) = @_;

    $self->cpuser_has_feature_or_die("wp-toolkit");

    Cpanel::iContact::Class::WPT::BlacklistedPluginDeactivated->new(
        # This identifies the application that sends the notification
        # This, when set, is also used for Contact Manager notification settings
        'origin'           => 'wp_toolkit',
        # Any additional variables that the specific template needs will be set here.
        'message' => @args[0]
    );

    return 1;
}

sub SEND_VULNERABILITY_FOUND_NOTIFICATION {
    my ($self, @args) = @_;

    $self->cpuser_has_feature_or_die("wp-toolkit");

    my $username = $self->get_caller_username();

    Cpanel::iContact::Class::WPT::VulnerabilityFound->new(
        # If the notification is going to a user, it's the username.
        # Otherwise, exclude this and it goes to root.
        'to'         => $username,
        # This identifies the application that sends the notification
        # This, when set, is also used for Contact Manager notification settings
        'origin'           => 'wp_toolkit',
        # Any additional variables that the specific template needs will be set here.
        'message' => @args[0]
    );

    return 1;
}

sub SEND_ADMIN_VULNERABILITY_FOUND_NOTIFICATION {
    my ($self, @args) = @_;

    $self->cpuser_has_feature_or_die("wp-toolkit");

    Cpanel::iContact::Class::WPT::VulnerabilityFound->new(
        # This identifies the application that sends the notification
        # This, when set, is also used for Contact Manager notification settings
        'origin'           => 'wp_toolkit',
        # Any additional variables that the specific template needs will be set here.
        'message' => @args[0]
    );

    return 1;
}

return 1;
