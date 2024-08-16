<?php

use \WP_CLI\Utils;

/**
 * Manage config settings command
 *
 * @package wp-cli
 */
class Config_Settings_Command extends WP_CLI_Command {

    /**
     * Get config params values
     *
     * ## EXAMPLES
     *     wp config-settings get --params=DB_NAME,DB_HOST,DB_USER --format=json
     */
    public function get($_, $assoc_args)
    {
        $paramsNames = isset($assoc_args['params']) ? $assoc_args['params'] : '';
        $params = explode(',', $paramsNames);
        $values = array();
        foreach ($params as $param) {
            if (defined($param)) {
                $values[$param] = constant($param);
            }
        }
        $formatter = new \WP_CLI\Formatter( $assoc_args, \array_keys( $values ) );
        $formatter->display_item( $values );
    }
}

WP_CLI::add_command( 'config-settings', 'Config_Settings_Command' );
