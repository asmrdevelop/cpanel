<?php

use \WP_CLI\Utils;

/**
 * Get release information
 *
 * @package wp-cli
 */
class Release_Command extends WP_CLI_Command {

    /**
     * Get current release version.
     *
     * ## OPTIONS
     *
     * [--locale=<locale>]
     * : Select which language you want to download.
     *
     * ## EXAMPLES
     *
     *     $ wp release get-current --locale=nl_NL
     *     4.7
     *
     * @when before_wp_load
     *
     * @subcommand get-current
     */
    public function get_current( $args, $assoc_args ) {
        $locale = \WP_CLI\Utils\get_flag_value( $assoc_args, 'locale', 'en_US' );

        $out = unserialize( self::_read( 'https://api.wordpress.org/core/version-check/1.6/?locale=' . $locale ) );
        $offer = $out['offers'][0];

        if ( $offer['locale'] != $locale ) {
            WP_CLI::error( "The requested locale ($locale) was not found." );
        }

        WP_CLI::print_value( $offer['current'] );
    }

    /**
     * Get available translations for selected release version.
     *
     * ## OPTIONS
     *
     * --version=<version>
     * : Select which version you want to download.
     *
     * [--format=<format>]
     * : Accepted values: table, csv, json. Default: table
     *
     * ## EXAMPLES
     *
     *     $ wp release get-translations --version=4.7
     *
     * @when before_wp_load
     *
     * @subcommand get-translations
     */
    public function get_translations( $args, $assoc_args ) {
        $translations = json_decode( self::_read(
            'https://api.wordpress.org/translations/core/1.0/?version=' . $assoc_args['version'] ), true );

        $formatter = new \WP_CLI\Formatter( $assoc_args, array( 'language', 'english_name', 'native_name',  'updated' ) );
        $formatter->display_items( $translations['translations'] );
    }

    /**
     * Get available releases.
     *
     * ## OPTIONS
     *
     * [--locale=<locale>]
     * : Select which language you want to download.
     *
     * [--format=<format>]
     * : Accepted values: table, csv, json. Default: table
     *
     * ## EXAMPLES
     *
     *     $ wp release list --locale=nl_NL
     *
     * @when before_wp_load
     *
     * @subcommand list
     */
    public function list_( $args, $assoc_args ) {
        $locale = \WP_CLI\Utils\get_flag_value( $assoc_args, 'locale', 'en_US' );
        $out = json_decode( self::_read( 'https://api.wordpress.org/core/version-check/1.7/?locale=' . $locale ), true );

        $offers = array_filter($out['offers'], function( $offer ) use( $locale ) { return $offer['locale'] == $locale; } );

        $formatter = new \WP_CLI\Formatter( $assoc_args, array( 'version', 'download', 'locale' ) );
        $formatter->display_items( $offers );
    }

    private static function _read( $url ) {
        $headers = array('Accept' => 'application/json');
        $response = Utils\http_request( 'GET', $url, null, $headers, array( 'timeout' => 30 ) );
        if ( 200 === $response->status_code ) {
            return $response->body;
        } else {
            WP_CLI::error( "Couldn't fetch response from {$url} (HTTP code {$response->status_code})." );
        }
    }
}

WP_CLI::add_command( 'release', 'Release_Command' );
