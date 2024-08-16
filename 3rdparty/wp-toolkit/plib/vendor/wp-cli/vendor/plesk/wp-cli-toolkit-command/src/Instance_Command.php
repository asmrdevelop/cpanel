<?php

/**
 * Make init
 *
 * @package wp-cli
 */
class Instance_Command extends WP_CLI_Command {
    /**
     * Secure instance by default set of operations
     * [--format=<format>]
     * : The format to use when printing the user; acceptable values:
     * [--checkers=<checkers>]
     * : List of checkers.
     * ## EXAMPLES
     *
     *      wp init secure --checkers=securityKeys,dbPrefix,adminUsername,versionInfo  --format=json
     *
     * @subcommand secure
     * @todo Looks like obsolete command
     */
    public function secure( $args, $assoc_args ) {

        $formatter = new \WP_CLI\Formatter( $assoc_args, ['dbPrefix', 'securityKeys', 'versionInfo', 'adminUsername'] );
        $checkersNames = isset($assoc_args['checkers']) ? $assoc_args['checkers'] : null;
        if (is_null($checkersNames)) {
            $formatter->display_item(array());
            return;
        }
        $checkers = explode(",", $checkersNames);

        foreach($checkers as $checker) {
            switch ($checker) {
                case 'dbPrefix':
                    ob_start();
                    WP_CLI::run_command( array( 'db-prefix', 'set' ), array('skip-success' => 'true'));
                    $resultString = ob_get_clean();
                    $result[$checker] = array(trim($resultString));
                    break;
                case 'securityKeys':
                    ob_start();
                    WP_CLI::run_command( array( 'security-keys', 'fix_keys' ), array('skip-success' => 'true'));
                    ob_get_clean();
                    $result[$checker] = array();
                    break;
                case 'versionInfo':
                    ob_start();
                    WP_CLI::run_command( array( 'version-info', 'secure' ), array('skip-success' => 'true'));
                    ob_get_clean();
                    $result[$checker] = array();
                    break;
                case 'adminUsername':
                    ob_start();
                    WP_CLI::run_command( array( 'admin-username', 'secure' ), array('format' => 'json', 'skip-error' => 'true') );
                    $resultString = ob_get_clean();
                    $result[$checker] = json_decode($resultString);
                    break;
                default:
                    break;
            }
        }

        $formatter->display_item( $result );
    }

    /**
     * Get main WordPress info: blog name, site url, version, update version, plugins, themes.
     *
     * ## OPTIONS
     *
     * [--plugin-fields=<plugin-fields>]
     * : Limit the plugins output to specific object fields. Defaults to name,status,update,version,title,description,update version.
     *
     * [--theme-fields=<theme-fields>]
     * : Limit the themes output to specific object fields. Defaults to name,status,update,version,title,description,update version.
     *
     * [--format=<format>]
     * : The format to use when printing the user; acceptable values:
     *
     *      **table**: Outputs all fields of the user as a table.
     *
     *      **json**: Outputs all fields in JSON format.
     *
     * [--check-updates=<check-updates>]
     * : Check updates for instance:
     *
     *    **true**: check updates for instance.
     *    **false**: do not check updates for instance.
     *
     * ## EXAMPLES
     *
     *      wp instance info
     *      wp instance info --format=json
     *      wp instance info --plugin-fields=name,status,version --theme-fields=name,title,description --format=json
     *      wp instance info --plugin-fields=name,status,version --theme-fields=name,title,description --format=json --check-updates=true
     */
    public  function info( $_, $assoc_args ) {
        global $wp_version;
        $info['name'] = get_option( 'blogname' );
        $info['url'] = get_option( 'siteurl' );
        $language = get_option( 'WPLANG' );
        $info['language'] = '' != $language ? $language : 'en_US';
        $info['admin_email'] = get_option( 'admin_email' );
        $info['blog_public'] = get_option( 'blog_public' );
        $info['version'] = $wp_version;
        $checkUpdates = isset( $assoc_args['check-updates'] ) ? $assoc_args['check-updates'] : 'true';
        $info['update_version'] = ('true' === $checkUpdates) ? $this->_get_update_version() : null;

        $plugin_fields = isset( $assoc_args['plugin-fields'] ) ? $assoc_args['plugin-fields'] : 'name,status,version,title,description,update_version';
        ob_start();
        WP_CLI::run_command( array( 'plugin', 'list' ), array( 'fields' => $plugin_fields, 'check-updates' => $checkUpdates, 'format' => 'json' ) );
        $info['plugins'] = ob_get_clean();

        $theme_fields = isset( $assoc_args['theme-fields'] ) ? $assoc_args['theme-fields'] : 'name,status,version,title,description,update_version';
        ob_start();
        WP_CLI::run_command( array( 'theme', 'list' ), array( 'fields' => $theme_fields, 'check-updates' => $checkUpdates, 'format' => 'json' ) );
        $info['themes'] = ob_get_clean();

        $formatter = new \WP_CLI\Formatter( $assoc_args, \array_keys( $info ) );
        $formatter->display_item( $info );
    }

	/**
	 * Returns WP login URL
	 *
	 * ## EXAMPLES
	 *
	 *     $ wp instance login-url
	 *
	 * @subcommand login-url
	 */
    public function login_url($_, $assoc_args)
	{
		WP_CLI::print_value( wp_login_url(), $assoc_args );
	}

    private function _get_update_version() {
        global $wp_version;
        wp_version_check();
        $from_api = get_site_transient( 'update_core' );
        if ( isset( $from_api->updates ) && is_array( $from_api->updates ) ) {
            list( $update ) = $from_api->updates;
            if ( isset( $update->response ) && 'latest' != $update->response && 'development' != $update->response
                && version_compare($update->current, $wp_version, '!=')) {
                return $update->current;
            }
        }

        return null;
    }
}

WP_CLI::add_command( 'instance', 'Instance_Command' );
