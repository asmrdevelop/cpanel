<?php

if ( ! class_exists( 'WP_CLI' ) ) {
	return;
}

$autoload = dirname( __FILE__ ) . '/vendor/autoload.php';
if ( file_exists( $autoload ) ) {
	require_once $autoload;
}

WP_CLI::add_command( 'admin-username', 'Admin_Username_Command' );
WP_CLI::add_command( 'config-settings', 'Config_Settings_Command' );
WP_CLI::add_command( 'db-prefix', 'Db_Prefix_Command' );
WP_CLI::add_command( 'instance', 'Instance_Command' );
WP_CLI::add_command( 'maintenance-mode', 'Maintenance_Mode_Command' );
WP_CLI::add_command( 'release', 'Release_Command' );
WP_CLI::add_command( 'security-keys', 'Security_Keys_Command' );
WP_CLI::add_command( 'pingbacks', 'Pingbacks_Command' );
WP_CLI::add_command( 'sitemap', 'Sitemap_Command' );
WP_CLI::add_command( 'wpt-cron event', 'Wpt_Cron_Command' );
WP_CLI::add_command( 'wpt-asset', 'Wpt_Asset_Command' );
WP_CLI::add_command( 'shortcode', 'Shortcode_Command' );

$startObLevel = 0;
WP_CLI::add_hook('before_wp_load', function () use (&$startObLevel) {
	ob_start();
	$startObLevel = ob_get_level();
});
WP_CLI::add_hook('after_wp_load', function () use (&$startObLevel) {
	while (ob_get_level() > $startObLevel) {
		ob_end_clean();
	}
});
