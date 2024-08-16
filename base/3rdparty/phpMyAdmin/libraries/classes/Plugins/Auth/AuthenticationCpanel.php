<?php
/* vim: set expandtab sw=4 ts=4 sts=4: */
/**
 * Set of functions used to run cookie based authentication.
 * Thanks to Piotr Roszatycki <d3xter at users.sourceforge.net> and
 * Dan Wilson who built this patch for the Debian package.
 *
 * @package phpMyAdmin-Auth-Cookie
 * @version $Id$
 */

// This version is modified by cPanel, Inc and is distributed under the same terms as phpMyAdmin itself (GPLv2).
// Intended for use with 2 and 3.3 pma version

namespace PhpMyAdmin\Plugins\Auth;

use PhpMyAdmin\Core;
use PhpMyAdmin\LanguageManager;
use PhpMyAdmin\URL;
use PhpMyAdmin\Util;
use PhpMyAdmin\Session;
use PhpMyAdmin\Plugins\Auth\AuthenticationCookie;

// NOTE TO MAINTAINER: See patch 0004 for why the 'Session' lib is needed!

if (file_exists('/var/cpanel/dev_sandbox')) {
    error_reporting(E_ERROR);
}

/**
 * Handles the cPanel authentication method
 *
 */

// headers, blowfish...
class AuthenticationCpanel extends AuthenticationCookie {

    /**
     * Displays authentication form
     *
     * this function MUST exit/quit the application
     *
     * @uses    $GLOBALS['server']
     * @uses    $GLOBALS['PHP_AUTH_USER']
     * @uses    $GLOBALS['pma_auth_server']
     * @uses    $GLOBALS['text_dir']
     * @uses    $GLOBALS['pmaThemeImage']
     * @uses    $GLOBALS['charset']
     * @uses    $GLOBALS['target']
     * @uses    $GLOBALS['db']
     * @uses    $GLOBALS['table']
     * @uses    $GLOBALS['pmaThemeImage']
     * @uses    $cfg['Servers']
     * @uses    $cfg['LoginCookieRecall']
     * @uses    $cfg['Lang']
     * @uses    $cfg['Server']
     * @uses    $cfg['ReplaceHelpImg']
     * @uses    $cfg['blowfish_secret']
     * @uses    $cfg['AllowArbitraryServer']
     * @uses    $_COOKIE
     * @uses    $_REQUEST['old_usr']
     * @uses    Core::sendHeaderLocation()
     * @global  string    the last connection error
     *
     * @access  public
     */
    public function showLoginForm() :bool {
        global $conn_error;

        /* Perform logout to custom URL */
        if (!empty($_REQUEST['old_usr']) && !empty($GLOBALS['cfg']['Server']['LogoutURL'])) {
            Core::sendHeaderLocation($GLOBALS['cfg']['Server']['LogoutURL']);
            exit;
        }
        if (strstr($_SESSION['auth_type'], 'env') || strstr($_SESSION['auth_type'], 'mycnf')) {
            return true;
        }

        return parent::showLoginForm();
    }


    /**
     * Gets advanced authentication settings
     *
     * this function DOES NOT check authentication - it just checks/provides
     * authentication credentials required to connect to the MySQL server
     * usually with PMA_DBI_connect()
     *
     * it returns false if something is missing - which usually leads to
     * PMA_auth() which displays login form
     *
     * it returns true if all seems ok which usually leads to storeCredentials()
     *
     * it directly switches to PMA_auth_fails() if user inactivity timout is reached
     *
     * @todo    AllowArbitraryServer on does not imply that the user wants an
     *          arbitrary server, or? so we should also check if this is filled and
     *          not only if allowed
     * @uses    $GLOBALS['PHP_AUTH_USER']
     * @uses    $GLOBALS['PHP_AUTH_PW']
     * @uses    $GLOBALS['no_activity']
     * @uses    $GLOBALS['server']
     * @uses    $GLOBALS['from_cookie']
     * @uses    $GLOBALS['pma_auth_server']
     * @uses    $cfg['AllowArbitraryServer']
     * @uses    $cfg['LoginCookieValidity']
     * @uses    $cfg['Servers']
     * @uses    $_REQUEST['old_usr'] from logout link
     * @uses    $_REQUEST['pma_username'] from login form
     * @uses    $_REQUEST['pma_password'] from login form
     * @uses    $_REQUEST['pma_servername'] from login form
     * @uses    $_COOKIE
     * @uses    $_SESSION['last_access_time']
     * @uses    PMA_removeCookie()
     * @uses    time()
     *
     * @return  boolean   whether we get authentication settings or not
     *
     * @access  public
     */
    public function readCredentials() :bool {
        // Initialization
        /**
         * @global $GLOBALS['pma_auth_server'] the user provided server to connect to
         */
        $GLOBALS['pma_auth_server'] = '';

        // REMOTE_PASSWORD auth
        $TMP_PASS = $_ENV['REMOTE_PASSWORD'];
        $TMP_USER = $_ENV['REMOTE_USER'] == "root" ? "root" : $_ENV['REMOTE_DBOWNER'];
        if ($this->cp_mysql_auth_check($TMP_USER, $TMP_PASS)) {
            $_SESSION['auth_type']    = 'env';
            $GLOBALS['PHP_AUTH_USER'] = $TMP_USER;
            $GLOBALS['PHP_AUTH_PW']   = $TMP_PASS;
            $sess_cookie_details = session_get_cookie_params();
            if( !empty($sess_cookie_details) ) $GLOBALS['from_cookie'] = true;

            return true;
        }

        // .my.cnf auth
        $user_info       = posix_getpwnam(CORE::getenv('REMOTE_USER'));
        $my_cnf_location = $user_info['dir'] . "/.my.cnf";
        if (is_readable($my_cnf_location)) {
            list($TMP_USER, $TMP_PASS) = $this->cp_get_my_cnf_vars($my_cnf_location);
            if (!empty($TMP_USER) && !empty($TMP_PASS)) {
                if ($this->cp_mysql_auth_check($TMP_USER, $TMP_PASS)) {
                    $_SESSION['auth_type']    = 'mycnf';
                    $GLOBALS['PHP_AUTH_USER'] = $TMP_USER;
                    $GLOBALS['PHP_AUTH_PW']   = $TMP_PASS;
                    $sess_cookie_details = session_get_cookie_params();
                    if( !empty($sess_cookie_details) ) $GLOBALS['from_cookie'] = true;

                    return true;
                }
            }
        }

        // form auth.
        $GLOBALS['PHP_AUTH_USER'] = $GLOBALS['PHP_AUTH_PW'] = '';
        $GLOBALS['from_cookie']   = false;

        //end cpanel auth changes, fallback to what's normally defined
        return parent::readCredentials();
    }


    /**
     * Set the user and password after last checkings if required
     *
     * @uses    $GLOBALS['PHP_AUTH_USER']
     * @uses    $GLOBALS['PHP_AUTH_PW']
     * @uses    $GLOBALS['server']
     * @uses    $GLOBALS['from_cookie']
     * @uses    $GLOBALS['pma_auth_server']
     * @uses    $cfg['Server']
     * @uses    $cfg['AllowArbitraryServer']
     * @uses    $cfg['LoginCookieStore']
     * @uses    $cfg['PmaAbsoluteUri']
     * @uses    $_SESSION['last_access_time']
     * @uses    Config::setCookie()
     * @uses    Config::removeCookie()
     * @uses    Core::sendHeaderLocation()
     * @uses    time()
     * @uses    define()
     * @return  boolean   always true
     *
     * @access  public
     */

    public function storeCredentials() :bool {

        global $PHP_AUTH_USER, $PHP_AUTH_PW;
        $this->user     = $PHP_AUTH_USER;
        $this->password = $PHP_AUTH_PW;

        return parent::storeCredentials();
    }

    /**
     * ========================================
     * ========   private methods     =========
     * ========================================
     **/

    private static function cp_mysql_auth_check($username, $password) {
        global $cfg;
        if (!mysqli_connect( $cfg['Server']['host'], $username, $password, NULL, $cfg['Server']['port'] ) ) {
            return false;
        } else {
            return true;
        }
    }

    private static function cp_get_my_cnf_vars($my_cnf_file) {
        if (!is_readable($my_cnf_file)) {
            error_log('cp_get_my_cnf_vars() called with invalid .my.cnf');
            return;
        }
        list($username, $password) = NULL;
        $my_cnf_contents = file($my_cnf_file);

        foreach ($my_cnf_contents as $line) {
            if (strpos($line, 'user') !== FALSE || strpos($line, 'pass') !== FALSE) {
                list($key, $value) = explode('=', $line, 2);
                $value = trim($value);
                $key   = trim($key);

                $dq = (strpos($value, '"') === 0 && strpos(substr($value, -1, 1), '"') === 0) ? TRUE : FALSE;
                $sq = (strpos($value, "'") === 0 && strpos(substr($value, -1, 1), "'") === 0) ? TRUE : FALSE;

                if ($dq || $sq) {
                    $mycnf_array[$key] = substr($value, 1, -1);
                } else {
                    $mycnf_array[$key] = $value;
                }
            }
        }
        $username = (array_key_exists('username', $mycnf_array)) ? $mycnf_array['username'] : $mycnf_array['user'];
        $password = (array_key_exists('password', $mycnf_array)) ? $mycnf_array['password'] : $mycnf_array['pass'];

        return array(
            $username,
            $password
        );
    }

} // end of AuthenticationCpanel class

?>
