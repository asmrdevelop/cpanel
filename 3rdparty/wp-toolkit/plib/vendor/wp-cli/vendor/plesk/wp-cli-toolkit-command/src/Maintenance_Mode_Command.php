<?php

/**
 * Manage maintenance mode.
 *
 * @package wp-cli
 */
class Maintenance_Mode_Command extends WP_CLI_Command {

    /**
     * Generate maintenance mode page
     *
     * ## OPTIONS
     *
     * [--dst=<dst>]
     * : Absolute path to maintenance mode page to be created.
     *
     * [--template=<template>]
     * : Absolute path to template to be used to page generation.
     *
     * [--vars=<vars>]
     * : Variables to be inserted into template (json encoded array)
     *
     * ## EXAMPLES
     *     $ wp maintenance-mode create-page --dst=/var/www/vhosts/domain.com/wp-content/maintenance.php --template=/var/www/vhosts/domain.com/wp-content/maintenance/template.php --vars={"startTime":1495473951,"socialNetworks":{"facebook":"https:\/\/www.facebook.com\/Plesk"},"texts":{"title":"!!","header":"Sorry it wouldn't be long. Just install some updates.","text":""},"timer":{"enabled":"1","days":"1","hours":"0","minutes":"0"}}
     *
     * @subcommand create-page
     */
    public function create_page( $args, $assoc_args )
    {
        $template = isset( $assoc_args['template'] ) ? $assoc_args['template'] : null;
        if ( is_null( $template ) ) {
            WP_CLI::error( 'Template is not specified' );
        }

        $filePath = isset( $assoc_args['dst'] ) ? $assoc_args['dst'] : null;
        if ( is_null( $filePath ) ) {
            WP_CLI::error( 'Filename is not specified' );
        }

        if ( file_exists( $filePath ) ) {
            unlink( $filePath );
        }

        $vars = isset( $assoc_args['vars'] ) ? json_decode( $assoc_args['vars'], true ) : array();
        $iconUrl = function_exists('get_site_icon_url') ? get_site_icon_url( 32 ) : '';
        $siteUrl = function_exists('get_option') ? get_option( 'siteurl' ) : '';
        if (isset($vars['assetsUrl']) && '' != $siteUrl) {
            $vars['assetsUrl'] = rtrim($siteUrl, '/') . '/' . $vars['assetsUrl'];
        }
        $vars['favicon'] = $iconUrl ?: '/favicon.ico';

        // calculate difference between server time and browser time
        $vars['timeShift'] = '<?php echo time(); ?> - Math.floor(Date.now() / 1000)';

        $backtime = 600;
        if ( !empty( $vars['timer']['enabled'] ) ) {
            $timer = $vars['timer'];
            $backtime = $timer['days'] * 24 * 60 * 60 + $timer['hours'] * 60 * 60 + $timer['minutes'] * 60;
        }

        $headers = <<<'EOT'
<?php

//  ATTENTION!
//
//  DO NOT MODIFY THIS FILE BECAUSE IT WAS GENERATED AUTOMATICALLY,
//  SO ALL YOUR CHANGES WILL BE LOST THE NEXT TIME THE FILE IS GENERATED.
//  IF YOU REQUIRE TO APPLY CUSTOM MODIFICATIONS, PERFORM THEM IN THE FOLLOWING FILE:
//  __TEMPLATE__


$protocol = $_SERVER['SERVER_PROTOCOL'];
if ('HTTP/1.1' != $protocol && 'HTTP/1.0' != $protocol) {
    $protocol = 'HTTP/1.0';
}

header("{$protocol} 503 Service Unavailable", true, 503);
header('Content-Type: text/html; charset=utf-8');
header('Retry-After: __BACKTIME__');
?>
EOT;

        extract( $vars );
        ob_start();
        include $template;

        file_put_contents(
            $filePath,
            str_replace( '__TEMPLATE__', $template, str_replace( '__BACKTIME__', $backtime, $headers ) )
            . PHP_EOL . PHP_EOL . ob_get_clean()
        );

        foreach (array_keys($vars) as $name => $value) {
            unset($$name);
        }
    }
}

WP_CLI::add_command( 'maintenance-mode', 'Maintenance_Mode_Command' );
