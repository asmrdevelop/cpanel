<?php

/**
 * Manage WordPress config's security keys
 *
 * @package wp-cli
 */
class Security_Keys_Command extends WP_CLI_Command {

    private $_keys = array(
        'AUTH_KEY', 'SECURE_AUTH_KEY', 'LOGGED_IN_KEY', 'NONCE_KEY',
        'AUTH_SALT', 'SECURE_AUTH_SALT', 'LOGGED_IN_SALT', 'NONCE_SALT',
    );

    /**
     * Check that list of keys exists and they are correct in wp-config.php
     *
     * ## EXAMPLES
     *
     *     wp security-keys are_keys_correct
     */
    public function are_keys_correct()
    {

        $missingKeys = $this->_getMissingKeys();
        $wrongKeys = $this->_getWrongKeys();
        WP_CLI::print_value(empty($missingKeys) && empty($wrongKeys));
    }

    /*
     * Add a list of missing keys and fix wrong keys in wp-config.php
     *
     * [--skip-success=<skip-success>]
     * : Skip success messages:
     *
     *    **true**: skip success messages.
     * ## EXAMPLES
     *
     *     wp security-keys fix_keys
     *     wp security-keys fix_keys --skip-success=true
     */
    public function fix_keys($_, $assoc_args)
    {
        if (false === ($configFileContent = file_get_contents(ABSPATH . 'wp-config.php'))) {
            WP_CLI::error("Could not open config file.");
        }

        $missingKeys = $this->_getMissingKeys();
        $keysToReplace = array_diff($this->_keys, $missingKeys);

        foreach($keysToReplace as $key) {
            $pattern = "/define\s*\(\s*(['\"]){$key}\g{-1}\s*,\s*(['\"]).*?\g{-1}\s*\)/";
            $replacement = "define('$key', '{$this->_getSalt()}')";
            $result = preg_replace($pattern, $replacement, $configFileContent);
            if (is_null($result)) {
                WP_CLI::error('Could not replace a value of key "' . $key . '" in config file.');
            }
            $configFileContent = $result;
        }

        if (!empty($missingKeys)) {
            $keysToAppend = array();
            foreach($missingKeys as $key) {
                $keysToAppend[] = "define('{$key}', '{$this->_getSalt()}');";
            }
            $pattern = '/\/\*\*[^\/]*Authentication Unique Keys and Salts.+?(?=\*\/)\*\//is';
            $secondPattern = '/\/\*\sThat\'s all, stop editing!\sHappy blogging.+?\*\//is';
            $matches = array();
            if (1 === preg_match($pattern, $configFileContent, $matches)) {
                $marker = $matches[0];
                $replacement = implode("\n", array_merge(array($marker), $keysToAppend));
                $configFileContent = str_replace($marker, $replacement, $configFileContent);
            } elseif (1 === preg_match($secondPattern, $configFileContent, $matches)) {
                $marker = $matches[0];
                $replacement = implode("\n", array_merge($keysToAppend, array($marker)));
                $configFileContent = str_replace($marker, $replacement, $configFileContent);
            }
        }

        if ( false === file_put_contents( ABSPATH . 'wp-config.php', $configFileContent ) ) {
            WP_CLI::error('Could not modify config file.');
        }
        $skipSuccess = isset($assoc_args['skip-success']) ? $assoc_args['skip-success'] : 'false';
        if ('true' !== $skipSuccess) {
            WP_CLI::success('Security keys were updated successfully.');
        }
    }

    /**
     * @return array
     */
    private function _getMissingKeys()
    {
        $missingKeys = array();
        foreach($this->_keys as $key) {
            if (defined($key)) {
                continue;
            }
            $missingKeys[] = $key;
        }
        return $missingKeys;
    }

    private function _getWrongKeys()
    {
        $wrongKeys = array();
        foreach($this->_keys as $key) {
            if (!defined($key)) {
                continue;
            }
            $value = constant($key);

            if (!preg_match('/(\d)+/', $value)) {
                $wrongKeys[] = $key;
            }
        }
        return $wrongKeys;
    }

    /**
     * @return string
     */
    private function _getSalt()
    {
        $args = array(
            (array)range('a', 'z'),
            (array)range('A', 'Z'),
            (array)range(0, 9),
            array('(', ')', '#', '*', '%', '!', '@', '&', '~', '-', '_', '[', ']', '/', ':', ';', '+', '|'),
        );

        srand((float)microtime()*1000000);

        $length = 64;
        $prefix = array();
        // add required symbols
        foreach ($args as $arg) {
            if (count($prefix) == $length) {
                shuffle($prefix);
                return implode("", $prefix);
            }
            $prefix[] = $arg[rand(0, count($arg) - 1)];
        }
        // add remaining symbols
        while (count($prefix) < $length) {
            $arg = $args[rand(0, count($args) - 1)];
            $prefix[] = $arg[rand(0, count($arg) - 1)];
        }
        shuffle($prefix);
        return implode("", $prefix);
    }
}

WP_CLI::add_command( 'security-keys', 'Security_Keys_Command' );
