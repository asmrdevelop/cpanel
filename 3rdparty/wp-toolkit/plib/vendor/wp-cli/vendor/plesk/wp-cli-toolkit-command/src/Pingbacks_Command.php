<?php

use \WP_CLI\Utils;

/**
 * Manage config settings command
 *
 * @package wp-cli
 */
class Pingbacks_Command extends WP_CLI_Command {

    const STATUS_CLOSED = 'closed';
    const STATUS_OPEN = 'open';

    const OPTION_FLAG = 'default_pingback_flag';
    const OPTION_STATUS = 'default_ping_status';

    /**
     * enable pingbacks
     *
     * ## EXAMPLES
     *     wp pingbacks enable
     */
    public function enable($_, $assoc_args)
    {
        $this->_toggle(true);
    }

    /**
     * Disable pingbacks
     *
     * ## EXAMPLES
     *     wp pingbacks disable
     */
    public function disable($_, $assoc_args)
    {
        $this->_toggle(false);
    }

    /**
     * Check status of pingbacks
     *
     * ## EXAMPLES
     *     wp pingbacks is_disabled
     */
    public function is_disabled($_, $assoc_args)
    {
        global $wpdb;
        WP_CLI::print_value(
            !get_option( 'default_pingback_flag' )
            && static::STATUS_CLOSED == get_option( 'default_ping_status' )
            && !$wpdb->get_var($wpdb->prepare(
                "SELECT count(*) FROM $wpdb->posts WHERE ping_status!=%s", static::STATUS_CLOSED
            ))
        );
    }

    /**
     * @param $enable
     * @throws \WP_CLI\ExitException
     */
    private function _toggle($enable)
    {
        global $wpdb;
        $options = $this->_getOptions($enable);
        foreach ($options as $key => $value) {
            update_option( $key, $value );
        }
        $wpdb->query( $wpdb->prepare( "UPDATE $wpdb->posts SET ping_status = %s", $options[static::OPTION_STATUS]) );
    }

    /**
     * @param boolean $valuesToEnable
     */
    private function _getOptions($valuesToEnable)
    {
        return array(
            static::OPTION_FLAG => $valuesToEnable ? 1 : "",
            static::OPTION_STATUS => $valuesToEnable ? static::STATUS_OPEN : static::STATUS_CLOSED
        );
    }
}

WP_CLI::add_command( 'pingbacks', 'Pingbacks_Command' );
