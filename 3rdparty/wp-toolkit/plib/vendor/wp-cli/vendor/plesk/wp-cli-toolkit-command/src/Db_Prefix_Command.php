<?php

use \WP_CLI\Utils;

class CannotRenameTableException extends Exception
{
}

/**
 * Manage database prefix.
 *
 * @package wp-cli
 */
class DB_Prefix_Command extends WP_CLI_Command {

    const CODE_FAILED_TURN_ON_MAINTENANCE_MODE = 10101;
    const CODE_FAILED_TURN_OFF_MAINTENANCE_MODE = 10102;
    const CODE_FAILED_DEACTIVATE_PLUGIN = 10103;
    const CODE_FAILED_ACTIVATE_PLUGIN = 10104;
    const CODE_WRONG_PREFIX = 10105;
    const CODE_FAILED_CHANGE_WP_CONFIG = 10106;
    const CODE_FAILED_CHANGE_DB = 10107;

    const WP_TOOLKIT_MANAGEMENT_PLUGIN = 'wp-toolkit-management-plugin';

    /**
     * Get database prefix.
     *
     * ## EXAMPLES
     *
     *     wp db-prefix get
     */
    public function get() {
        global $wpdb;

        WP_CLI::print_value( $wpdb->base_prefix );
    }

    /**
     * Set new database prefix in database and wp-config.
     *
     * ## OPTIONS
     *
     * [<prefix>]
     * : New database prefix. If not passed, the 'wp_' is used.
     *
     * [--skip-success=<skip-success>]
     * : Skip success messages:
     *
     *    **true**: skip success messages.
     *
     * ## EXAMPLES
     *
     *     wp db-prefix set
     *     wp db-prefix set newpref_
     *     wp db-prefix set newpref_ --skip-success=true
     */
    public function set ( $args, $assoc_args) {
        global $wpdb;
        $new_prefix = isset( $args[0] ) ? $args[0] : $this->_generatePrefix();
        $current_prefix = $wpdb->base_prefix;
        if (\WP_CLI\Utils\is_windows()) {
            $current_prefix = strtolower($current_prefix);
        }
        $skipSuccess = isset($assoc_args['skip-success']) ? $assoc_args['skip-success'] : 'false';
        if ( 0 == strcmp( $current_prefix, $new_prefix ) ) {
            if ('true' !== $skipSuccess) {
                WP_CLI::success( "'{$new_prefix}' is current database prefix value." );
	     }
	     return;
        }

        $result = $wpdb->set_prefix( $new_prefix, false );
        if ( is_wp_error( $result ) ) {
            WP_CLI::error( WP_CLI::error_to_string( $result ), self::CODE_WRONG_PREFIX );
        }

        $this->_maintenance_mode( true );
        $plugins = $this->_deactivate_plugins();
        $this->_edit_config( $new_prefix );

        $e = null;
        try {
            $this->_update_db( $new_prefix, $current_prefix );
        } catch (CannotRenameTableException $e) {
            // If table names cannot be renamed for any reason,
            // need to save previous prefix into config file
            $this->_edit_config( $current_prefix );
        } catch (Exception $e) {
            // If table names successfully renamed, but another error has occurred,
            // need to rename tables back and reset wp-config changes
            $this->changeTablePrefix($current_prefix, $new_prefix);
            $this->_edit_config( $current_prefix );
        }

        $this->_activate_plugins( $plugins );
        $this->_flush_rewrite_rules();
        $this->_maintenance_mode( false );

        if (!is_null($e)) {
            WP_CLI::error( $e->getMessage(), $e->getCode() );
        }

	    if ('true' !== $skipSuccess) {
            WP_CLI::success( "Database prefix was successfully changed to '{$new_prefix}'." );
        }
        WP_CLI::print_value( $new_prefix );
    }

    private function _maintenance_mode( $enable = true ) {
        require_once( ABSPATH . 'wp-admin/includes/upgrade.php' );
        $err_code = $enable ? self::CODE_FAILED_TURN_ON_MAINTENANCE_MODE : self::CODE_FAILED_TURN_OFF_MAINTENANCE_MODE;

        $upgrader = Utils\get_upgrader( 'WP_Upgrader' );
        if ( !$upgrader->fs_connect( WP_CONTENT_DIR ) ) {
            WP_CLI::error( "Could not connect file system.", $err_code );
        }
        $result = $upgrader->maintenance_mode( $enable );
        if ( is_wp_error( $result ) ) {
            WP_CLI::error( WP_CLI::error_to_string( $result ), $err_code );
        }
    }

    private function _deactivate_plugins () {
        require_once ABSPATH.'wp-admin/includes/plugin.php';
        $active_plugins = array();
        foreach ( get_plugins() as $file => $details ) {
            if (strpos($file, self::WP_TOOLKIT_MANAGEMENT_PLUGIN) !== false) {
                // Don't deactivate remote management plugin because:
                // - on deactivation security key & token will be removed and on activation generated again -> connection to instance will be broken
                // - we cannot interact with instance when plugin is deactivated
                continue;
            }
            if (is_plugin_active( $file )) {
                deactivate_plugins( $file );
                if ( is_plugin_active( $file ) ) {
                    WP_CLI::error( "Could not deactivate the '{$details['Name']}' plugin.", self::CODE_FAILED_DEACTIVATE_PLUGIN );
                }
                $active_plugins[] = $file;
            }
        }
        return $active_plugins;
    }

    private function _activate_plugins ( $plugins ) {
        require_once ABSPATH.'wp-admin/includes/plugin.php';
        foreach ( $plugins as $file ) {
            activate_plugins($file);
            if ( !is_plugin_active( $file ) ) {
                $plugin_folder = get_plugins(  '/' . plugin_basename( dirname( $file ) ) );
                $plugin_info = $plugin_folder[basename( $file )];
                WP_CLI::error( "Could not activate the '{$plugin_info['Name']}' plugin.", self::CODE_FAILED_ACTIVATE_PLUGIN );
            }
        }
    }

    private function _edit_config( $new_prefix ) {
        $wp_config_path = Utils\locate_wp_config();

        if ( !is_readable( $wp_config_path ) || false === ( $config_file = file_get_contents( $wp_config_path ) ) ) {
            WP_CLI::error( "Could not open config file.", self::CODE_FAILED_CHANGE_WP_CONFIG );
        }

        $config_file = preg_replace( '/\$table_prefix(.*)$/m', '$table_prefix = \''. $new_prefix .'\';', $config_file );

        if ( !is_writable( $wp_config_path ) || false === file_put_contents( $wp_config_path, $config_file ) ) {
            WP_CLI::error( "Could not modify config file.", self::CODE_FAILED_CHANGE_WP_CONFIG );
        }
    }

    /**
     * @param string $newPrefix
     * @param string $currentPrefix
     * @throws CannotRenameTableException
     */
    private function changeTablePrefix($newPrefix, $currentPrefix)
    {
        global $wpdb;

        $tables = $wpdb->get_col( $wpdb->prepare( "SHOW TABLES LIKE %s", like_escape( $currentPrefix ) . '%' ) );
        $tablesToRename = array();
        foreach ( $tables as $table_name ) {
            if ( 0 === strpos( $table_name, $currentPrefix ) ) {
                $new_table_name = preg_replace('/'. $currentPrefix .'/', $newPrefix, $table_name, 1);
                $tablesToRename[] = "`{$table_name}` TO `{$new_table_name}`";
            }
        }

        $tablesToRenameString = implode(', ', $tablesToRename);
        if ( count($tablesToRename) !== 0 && false === $wpdb->query( "RENAME TABLE {$tablesToRenameString};" ) ) {
            throw new CannotRenameTableException('Could not change table prefixes.', self::CODE_FAILED_CHANGE_DB);
        }

        $result = $wpdb->set_prefix( $newPrefix );
        if ( is_wp_error( $result ) ) {
            throw new Exception(WP_CLI::error_to_string( $result ), self::CODE_FAILED_CHANGE_DB);
        }
    }

    /**
     * @param string $newPrefix
     * @param string $currentPrefix
     * @throws CannotRenameTableException
     */
    private function _update_db($newPrefix, $currentPrefix ) {
        global $wpdb;

        $this->changeTablePrefix($newPrefix, $currentPrefix);

        if ( false === $wpdb->update(
                $wpdb->options,
                array( 'option_name' => $newPrefix . 'user_roles'),
                array( 'option_name' =>  $currentPrefix . 'user_roles' )
            )
        ) {
            throw new Exception("Could not update table '{$wpdb->options}'.", self::CODE_FAILED_CHANGE_DB);
        }

        $meta_keys = $wpdb->get_results( $wpdb->prepare( "SELECT user_id, meta_key FROM {$wpdb->usermeta} WHERE meta_key LIKE %s", like_escape( $currentPrefix ) . '%' ) );
        foreach ( $meta_keys as $meta_key ) {
            if ( false === $wpdb->update(
                    $wpdb->usermeta,
                    array( 'meta_key' => str_replace( $currentPrefix, $newPrefix, $meta_key->meta_key ) ),
                    array( 'meta_key' =>  $meta_key->meta_key, 'user_id' => $meta_key->user_id )
                )
            ) {
                throw new Exception("Could not update table '{$wpdb->usermeta}'.", self::CODE_FAILED_CHANGE_DB);
            }
        }
    }

    private function _flush_rewrite_rules() {
        WP_CLI::run_command( array( 'rewrite', 'flush' ), array( 'hard' => true ) );
    }

    /**
    * Generates a prefix of random length.
    *
    * @return string
    */
    private function _generatePrefix()
    {
        $args = array(
            (array)range('a', 'z'),
            (array)range('A', 'Z'),
            (array)range(0, 9),
        );

        srand((float)microtime()*1000000);

        $length = rand(5, 10);

        $prefix = array();
        // add required symbols
        foreach ($args as $arg) {
            if (count($prefix) == $length) {
                shuffle($prefix);
                return implode("", $prefix).'_';
            }
            $prefix[] = $arg[rand(0, count($arg) - 1)];
        }
        // add remaining symbols
        while (count($prefix) < $length) {
            $arg = $args[rand(0, count($args) - 1)];
            $prefix[] = $arg[rand(0, count($arg) - 1)];
        }
        shuffle($prefix);
        return implode("", $prefix).'_';
    }
}

WP_CLI::add_command( 'db-prefix', 'DB_Prefix_Command' );
