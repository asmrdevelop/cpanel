<?php

use \WP_CLI\Utils;

/**
 * Extends for Plugin_Command \ Theme_Command
 *
 * @package plesk/wp-cli
 */
class Wpt_Asset_Command extends WP_CLI_Command {
	protected $obj_fields = array(
		'slug',
		'download_link',
	);

	public function __construct()
	{
		parent::__construct();
		require_once ABSPATH . 'wp-admin/includes/plugin.php';
		require_once ABSPATH . 'wp-admin/includes/plugin-install.php';
	}

	public function information( $args, $assoc_args )
	{
		$findBy = \array_intersect_key($assoc_args, \array_flip($this->obj_fields));

		if ( isset($assoc_args['asset-type']) && $assoc_args['asset-type'] === 'plugin' ) {
			$api = plugins_api( 'plugin_information', $findBy );
		} else {
			$api = themes_api( 'theme_information', $findBy );
		}

		if ( is_wp_error( $api ) ) {
			WP_CLI::error( $api->get_error_message() );
		}

		$formatter = $this->get_formatter( $assoc_args );
		$formatter->display_item( $api );
    }

	protected function get_formatter( &$assoc_args ) {
		return new \WP_CLI\Formatter( $assoc_args, $this->obj_fields );
	}

    /**
     * Install must use plugin into mu-plugins folder
     *
     * ## OPTIONS
     *
     * [<zip-archive>]
     * : Zip archive.
     *
     * ## EXAMPLES
     *
     *  wp wpt-asset install-mu-plugin /var/www/vhosts/10-69-45-6.qa.plesk.tech/.wp-toolkit/1/wp-toolkit-integration-plugin.zip
     *
     * @subcommand install-mu-plugin
     */
    public function installMuPlugin($args, $assoc_args)
    {
        WP_Filesystem();

        if (isset($args[0])) {
            $zipArchive = $args[0];
        }

        if (empty($zipArchive)) {
            WP_CLI::error("Need to specify mu-plugin zip file path.");
        }

        $result = unzip_file($zipArchive, WPMU_PLUGIN_DIR);
        if (is_wp_error($result)) {
            WP_CLI::error( WP_CLI::error_to_string( $result ));
        }
    }
}

WP_CLI::add_command( 'wpt-asset', 'Wpt_Asset_Command' );
