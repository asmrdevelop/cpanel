<?php

use \WP_CLI\Utils;

/**
 * Manage administrator username.
 *
 * @package wp-cli
 */
class Admin_Username_Command extends WP_CLI_Command {

    const VULNERABLE_ADMIN_USERNAME = 'admin';

    const ENVIRONMENT_VARIABLE_NAME_NEW_PASSWORD = 'NEW_WORDPRESS_ADMINISTRATOR_PASSWORD';
	const ENVIRONMENT_VARIABLE_NAME_NEW_USERNAME = 'NEW_WORDPRESS_ADMINISTRATOR_USERNAME';
	const ENVIRONMENT_VARIABLE_NAME_PASSWORD = 'WORDPRESS_ADMINISTRATOR_PASSWORD';
    const ENVIRONMENT_VARIABLE_NAME_USERNAME = 'WORDPRESS_ADMINISTRATOR_USERNAME';

    const CODE_ADMIN_NOT_FOUND = 20101;
    const CODE_ADMIN_NOT_CREATED = 20102;
    const CODE_USER_META_NOT_UPDATED = 20103;
    const CODE_ADMIN_NOT_DELETED = 20104;
    const CODE_ADMIN_NOT_UPDATED = 20105;
    const CODE_ADMIN_ALREADY_EXIST = 20106;

	/**
	 * Check, if administrator with given username exist.
	 *
	 * ## OPTIONS
	 *
	 * [<username>]
	 * : administrator username.
	 *
	 * ## EXAMPLES
	 *
	 *     wp admin-username is_exist ipetrov
	 *
	 * @subcommand is-exist
	 */
	public function is_exist( $args ) {
		global $wpdb;

		$username = getenv(self::ENVIRONMENT_VARIABLE_NAME_USERNAME);
		if (isset($args[0])) {
			$username = $args[0];
		}

		if ($username === false) {
			WP_CLI::error("Need to specify administrator username.", self::CODE_ADMIN_NOT_FOUND);
		}

        WP_CLI::print_value( $this->_get_admin( $username ) ? true : false );
    }

    /**
     * Check if all administrators have secure usernames (other from admin).
     *
     * ## EXAMPLES
     *
     *     wp admin-username is-secure
     *
     * @subcommand is-secure
     */
    public function is_secure() {
        WP_CLI::print_value( !$this->_get_admin(self::VULNERABLE_ADMIN_USERNAME) );
    }

    /**
     * Change administrator username from 'admin' to random string and get administrator info.
     *
     * ## OPTIONS
     *
     * [--format=<format>]
     * : The format to use when printing the user; acceptable values:
     *
     *     **table**: Outputs all fields of the user as a table.
     *
     *     **json**: Outputs all fields in JSON format.
     *
     * [--skip-error=<skip-error>]
     * : Skip error messages:
     *
     *    **true**: skip error messages.
     *
     * ## EXAMPLES
     *
     *     wp admin-username secure
     *     wp admin-username secure --format=json
     *     wp admin-username secure --format=json --skip-error=true
     */
    public function secure( $_, $assoc_args ) {
        $vulnerable_admin = $this->_get_admin(self::VULNERABLE_ADMIN_USERNAME);
        $formatter = new \WP_CLI\Formatter( $assoc_args, ['user_login', 'user_pass'] );
        if ( !$vulnerable_admin ) {
            $skipError = isset($assoc_args['skip-error']) ? $assoc_args['skip-error'] : false;
            if ('true' === $skipError) {
                $formatter->display_item(array());
                return;
            } else {
                WP_CLI::error( "Administrator with 'admin' username was not found.", self::CODE_ADMIN_NOT_FOUND );
            }
        }

        $admin_credentials = $this->_create_new_admin( $vulnerable_admin );
        $this->_delete_old_admin( $vulnerable_admin, get_user_by( 'login', $admin_credentials['user_login'] ) );

        $formatter->display_item( $admin_credentials );
    }

	/**
	 * Set new administrator username and password. New password should be passed via environment variable "NEW_WORDPRESS_ADMINISTRATOR_PASSWORD".
	 *
	 * ## OPTIONS
	 *
	 * [<old-username>]
	 * : Old administrator username.
	 *
	 * [--username=<username>]
	 * : New administrator username.
	 *
	 * ## EXAMPLES
	 *
	 *     wp admin-username change ipetrov --username=mvasilevna
	 *
	 *     wp admin-username change ipetrov --username=ipetrov
	 */
    public function change( $args, $assoc_args ) {
        global $wpdb;

        $old_username = getenv(self::ENVIRONMENT_VARIABLE_NAME_USERNAME);
		if (isset($args[0])) {
			$old_username = $args[0];
		}
        if ( false === $old_username ) {
            WP_CLI::error( "Need to specify old administrator username.", self::CODE_ADMIN_NOT_FOUND );
        }

        if ( !$old_admin = $this->_get_admin( $old_username ) ) {
            WP_CLI::error( "Administrator with '" . $old_username . "' username was not found.", self::CODE_ADMIN_NOT_FOUND );
        }

		$new_username = getenv(self::ENVIRONMENT_VARIABLE_NAME_NEW_USERNAME);
		if (isset($assoc_args['username'])) {
			$new_username = $assoc_args['username'];
		}
        $new_password = getenv(self::ENVIRONMENT_VARIABLE_NAME_NEW_PASSWORD);

        if ( false === $new_username || false === $new_password ) {
            WP_CLI::error( "Need to specify new administrator username and password.", self::CODE_ADMIN_NOT_CREATED );
        }

        if ($old_username != $new_username) {
            $admin_credentials = $this->_create_new_admin( $old_admin, $new_username, $new_password );
            $this->_delete_old_admin( $old_admin, get_user_by( 'login', $admin_credentials['user_login'] ) );
        } else {
            $this->_set_password($old_admin, $new_password);
        }

        WP_CLI::success( "Administrator username was successfully changed to '{$new_username}' with password '{$new_password}'." );
    }

    /**
     * Checks the admin user's password.
	 * Password to check should be passed in WORDPRESS_ADMINISTRATOR_PASSWORD environment variable, username in WORDPRESS_ADMINISTRATOR_USERNAME
     *
	 * ## OPTIONS
	 *
	 * [<user>]
	 * : User ID or user login.
	 *
	 * [<password>]
	 * : Users's password in plaintext.
	 *
	 * ## EXAMPLES
	 *
	 *     wp admin-username check-password john q1w2e3
     *
     * @param $args
     * @param $assoc_args
     * @throws \WP_CLI\ExitException
     * @subcommand check-password
     */
    public function check_password($args, $assoc_args)
    {
		$username = getenv(self::ENVIRONMENT_VARIABLE_NAME_USERNAME);
		if (isset($args[0])) {
			$username = $args[0];
		}
		$password = getenv(self::ENVIRONMENT_VARIABLE_NAME_PASSWORD);
		if (isset($args[1])) {
			$password = $args[1];
		}

		if ($username === false || $password === false) {
			WP_CLI::error('You must specify administrator username and password to check.', self::CODE_ADMIN_NOT_FOUND);
		}

        if ( !$admin = $this->_get_admin( $username ) ) {
            WP_CLI::error( "Administrator with '" . $username . "' username was not found.", self::CODE_ADMIN_NOT_FOUND );
        }
        WP_CLI::print_value( wp_check_password( $password, $admin->user_pass, $admin->ID ) );
    }

    /**
     * Get administrator with given username
     *
     * @return WP_User|bool     *
     */
    private function _get_admin($login)
    {
        $user = get_user_by( 'login', $login );
        if ( !$user || !in_array( 'administrator', $user->roles ) ) {
            return false;
        }

        return $user;
    }

    /**
     * Create new admin using info from existing admin.
     *
     * @param WP_User $admin
     * @param string $username new administrator username
     * @param string $password new administrator password
     *
     * @return array
     */
    private function _create_new_admin( $admin, $username = null, $password = null ) {

        if (is_null($username)) {
            $username = wp_generate_password( 10, false );
	        while ( username_exists( $username ) ) {
	            $username = wp_generate_password( 10, false );
	        }
        } else {
            if ( username_exists( $username ) ) {
                WP_CLI::error( "Administrator with '" . $username . "' username already exist.", self::CODE_ADMIN_ALREADY_EXIST );
            }
        }

        $password = is_null($password) ? wp_generate_password() : $password;

        $result = wp_insert_user( array(
            'user_login' => $username,
            'user_url' => $admin->user_url,
            'user_pass' => $password,
            'user_registered' => $admin->user_registered,
            'display_name' => $admin->display_name,
            'role' => 'administrator',
        ) );
        if ( is_wp_error( $result ) ) {
            WP_CLI::error( WP_CLI::error_to_string( $result ), self::CODE_ADMIN_NOT_CREATED );
        }

        $user_id = $result;

        foreach ( get_user_meta( $admin->ID ) as $meta_key => $meta_values  ) {
            foreach ($meta_values as $meta_value) {
                $result = update_user_meta( $user_id, $meta_key, maybe_unserialize( $meta_value ) );
                if ( is_wp_error( $result ) ) {
                    WP_CLI::error( WP_CLI::error_to_string( $result ), self::CODE_USER_META_NOT_UPDATED );
                }
            }
        }

        return array ( 'user_login' => $username, 'user_pass' => $password );
    }

    /**
     * Change password of existing user.
     *
     * @param WP_User $user
     * @param string $password new user password
     *
     * @return array
     */
    private function _set_password( $user, $password ) {
        $result = $this->_update_wp_user(array(
            'ID' => $user->ID,
            'user_pass' => $password,
        ));
        if ( is_wp_error( $result ) ) {
            WP_CLI::error( WP_CLI::error_to_string( $result ), self::CODE_USER_META_NOT_UPDATED );
        }
    }

    /**
     * Remove old admin with reassigning his blogs and links to new admin.
     *
     * @param WP_User $old_admin
     * @param WP_User $new_admin
     */
    private function _delete_old_admin ( $old_admin, $new_admin) {
        $email = $old_admin->user_email;
        $nicename = $old_admin->user_nicename;

        $result = wp_delete_user( $old_admin->ID, $new_admin->ID );
        if ( is_wp_error( $result ) ) {
            WP_CLI::error( WP_CLI::error_to_string( $result ), self::CODE_ADMIN_NOT_DELETED );
        }

        $result = $this->_update_wp_user(array(
            'ID' => $new_admin->ID,
            'user_email' => $email,
            'user_nicename' => $nicename,
        ));
        if ( is_wp_error( $result ) ) {
            WP_CLI::error( WP_CLI::error_to_string( $result ), self::CODE_ADMIN_NOT_UPDATED );
        }
    }

    /**
     * @param array $params
     * @return int|WP_Error
     */
    private function _update_wp_user($params)
    {
        $urlParts = Utils\parse_url(get_option('siteurl'));
        $needToUnset = false;
        if (isset($urlParts['host']) && !isset($_SERVER['SERVER_NAME'])) {
            // Override SERVER_NAME to avoid phpmailerException because of invalid email address "from"
            $_SERVER['SERVER_NAME'] = $urlParts['host'];
            $needToUnset = true;
        }
        $result = wp_update_user( $params );
        if ($needToUnset) {
            unset($_SERVER['SERVER_NAME']);
        }
        return $result;
    }
}

WP_CLI::add_command( 'admin-username', 'Admin_Username_Command' );
