<?php

use \WP_CLI\Utils;

/**
 * Extends for Cron_Event_Command
 *
 * @package wp-cli
 */
class Wpt_Cron_Command extends WP_CLI_Command {
    /**
     * Reschedule a cron event to new time.
     *
     * ## OPTIONS
     *
     * <hook>
     * : The hook name.
     *
     * [<next-run>]
     * : A Unix timestamp or an English textual datetime description compatible with `strtotime()`. Defaults to now.
     */
    public function reschedule( $args, $assoc_args ) {

        $hook = $args[0];
        $next_run = \WP_CLI\Utils\get_flag_value( $args, 1, 'now' );

        $events = self::get_cron_events($hook);

        if ( count($events) !== 0 ) {
            WP_CLI::run_command( array( 'cron', 'event', 'delete', $hook ), array() );
        }

        foreach ( $events as $event ) {
            $eventArgs = array($hook, $next_run);
            $event['schedule'] && $eventArgs[] = $event['schedule'];

            WP_CLI::run_command( array_merge( array( 'cron', 'event', 'schedule' ), $eventArgs ), $event['args'] );
        }
    }

    /**
     * Fetch an array of scheduled cron events.
     *
     * @param string $needleHook
     * @return array An array of event objects.
     */
    protected static function get_cron_events($needleHook) {
        $crons  = _get_cron_array();
        $events = array();

        if (!is_array($crons)) {
            return array();
        }

        foreach ( $crons as $hooks ) {
            foreach ( $hooks as $hook => $hook_events ) {
                if ($hook !== $needleHook) {
                    continue;
                }

                foreach ( $hook_events as $data ) {
                    $args = empty($data['args']) ? array() : $data['args'];
                    $events[serialize($args)] = array(
                        'args'     => $args,
                        'schedule' => isset($data['schedule']) ? $data['schedule'] : false,
                    );
                }
            }
        }

        return $events;
    }
}

WP_CLI::add_command( 'wpt-cron event', 'Wpt_Cron_Command' );
