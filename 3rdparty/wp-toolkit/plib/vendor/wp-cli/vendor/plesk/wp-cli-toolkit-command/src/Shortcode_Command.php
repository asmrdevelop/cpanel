<?php

/**
 * Manage shortcodes
 *
 * @package wp-cli
 */
class Shortcode_Command extends WP_CLI_Command {
    /**
     * Retrieve registered shortcodes names
     *
     * ## EXAMPLES
     *
     *      wp shortcode list
     *
     * @when after_wp_load
     *
     * @subcommand list
     */
    public function list_($args, $assoc_args )
    {
        /**
         * Global associative array: tag => function
         */
        global $shortcode_tags;

		$tags = is_array($shortcode_tags) ? array_keys($shortcode_tags) : array();
		$resultTags = [];
		foreach ($tags as $tag) {
			$resultTags[$tag] = $tag;
		}

		$formatter = new \WP_CLI\Formatter( $assoc_args, \array_keys($resultTags));
		$formatter->display_item( $resultTags );
	}
}

WP_CLI::add_command( 'shortcode', 'Shortcode_Command' );
