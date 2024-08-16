package Cpanel::API::WpToolkitNotification;

use strict;

our $VERSION = '1.0';

our %API = (
    _needs_feature => "wp-toolkit"
);

use Cpanel ();
use Cpanel::AdminBin::Call ();

sub send_admin_suspicious_instance_notification {
	my ( $args, $result ) = @_;

	Cpanel::AdminBin::Call::call(
		'Cpanel',
		'WpToolkitNotification',
		'SEND_ADMIN_SUSPICIOUS_INSTANCE_NOTIFICATION',
		$args->get('suspicious_instance_text'),
		$args->get('suspicious_instance_details_info')
	);

	return 1;
}

sub send_reseller_suspicious_instance_notification {
	my ( $args, $result ) = @_;

	Cpanel::AdminBin::Call::call(
		'Cpanel',
		'WpToolkitNotification',
		'SEND_RESELLER_SUSPICIOUS_INSTANCE_NOTIFICATION',
		$args->get('suspicious_instance_text'),
		$args->get('suspicious_instance_details_info')
	);

	return 1;
}

sub send_client_suspicious_instance_notification {
	my ( $args, $result ) = @_;

	Cpanel::AdminBin::Call::call(
		'Cpanel',
		'WpToolkitNotification',
		'SEND_CLIENT_SUSPICIOUS_INSTANCE_NOTIFICATION',
		$args->get('suspicious_instance_text'),
		$args->get('suspicious_instance_details_info')
	);

	return 1;
}

sub send_admin_auto_updates_notification {
	my ( $args, $result ) = @_;

	Cpanel::AdminBin::Call::call(
		'Cpanel',
		'WpToolkitNotification',
		'SEND_ADMIN_AUTO_UPDATES_NOTIFICATION',
		$args->get('failure_updates_text'),
		$args->get('failure_updates_list'),
		$args->get('available_updates_text'),
		$args->get('available_updates_list'),
		$args->get('installed_updates_text'),
		$args->get('installed_updates_list'),
		$args->get('requirements_updates_text'),
		$args->get('requirements_updates_list')
	);

	return 1;
}

sub send_reseller_auto_updates_notification {
    my ( $args, $result ) = @_;

	Cpanel::AdminBin::Call::call(
		'Cpanel',
		'WpToolkitNotification',
		'SEND_RESELLER_AUTO_UPDATES_NOTIFICATION',
		$args->get('failure_updates_text'),
		$args->get('failure_updates_list'),
		$args->get('available_updates_text'),
		$args->get('available_updates_list'),
		$args->get('installed_updates_text'),
		$args->get('installed_updates_list'),
		$args->get('requirements_updates_text'),
		$args->get('requirements_updates_list')
	);

    return 1;
}

sub send_client_auto_updates_notification {
	my ( $args, $result ) = @_;

	Cpanel::AdminBin::Call::call(
		'Cpanel',
		'WpToolkitNotification',
		'SEND_CLIENT_AUTO_UPDATES_NOTIFICATION',
		$args->get('failure_updates_text'),
		$args->get('failure_updates_list'),
		$args->get('available_updates_text'),
		$args->get('available_updates_list'),
		$args->get('installed_updates_text'),
		$args->get('installed_updates_list'),
		$args->get('requirements_updates_text'),
		$args->get('requirements_updates_list')
	);

	return 1;
}

sub send_blacklisted_plugin_deactivated_notification {
	my ( $args, $result ) = @_;

	Cpanel::AdminBin::Call::call(
		'Cpanel',
		'WpToolkitNotification',
		'SEND_BLACKLISTED_PLUGIN_DEACTIVATED_NOTIFICATION',
		$args->get('message')
	);

	return 1;
}

sub send_admin_blacklisted_plugin_deactivated_notification {
	my ( $args, $result ) = @_;

	Cpanel::AdminBin::Call::call(
		'Cpanel',
		'WpToolkitNotification',
		'SEND_ADMIN_BLACKLISTED_PLUGIN_DEACTIVATED_NOTIFICATION',
		$args->get('message')
	);

	return 1;
}

sub send_vulnerability_found_notification {
	my ( $args, $result ) = @_;

	Cpanel::AdminBin::Call::call(
		'Cpanel',
		'WpToolkitNotification',
		'SEND_VULNERABILITY_FOUND_NOTIFICATION',
		$args->get('message')
	);

	return 1;
}

sub send_admin_vulnerability_found_notification {
	my ( $args, $result ) = @_;

	Cpanel::AdminBin::Call::call(
		'Cpanel',
		'WpToolkitNotification',
		'SEND_ADMIN_VULNERABILITY_FOUND_NOTIFICATION',
		$args->get('message')
	);

	return 1;
}

1;
