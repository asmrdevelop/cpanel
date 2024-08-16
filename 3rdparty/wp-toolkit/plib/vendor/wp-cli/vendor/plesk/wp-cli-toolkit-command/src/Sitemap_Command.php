<?php

/**
 * Manage sitemap
 *
 * @package wp-cli
 */
class Sitemap_Command extends WP_CLI_Command {
    /**
     * Check status of pingbacks
     *
     * ## EXAMPLES
     *     wp pingbacks is_disabled
     */
    public function generate($args, $assoc_args)
    {
        $posts = get_posts(array(
            'numberposts' => -1,
            'orderby' => 'modified',
            'post_type' => array('post', 'page'),
            'order' => 'DESC'
        ));

        $filename = isset($args[0] ) ? trim($args[0]) : 'sitemap.xml';
        $path = ABSPATH . $filename;

        $content = '<?xml version="1.0" encoding="UTF-8"?>';
        $content .= '<urlset xmlns="http://www.sitemaps.org/schemas/sitemap/0.9">';
        $content .= '<url><loc>' . site_url() . '</loc><lastmod>' . gmdate('Y-m-d') . '</lastmod></url>';
        foreach ($posts as $post) {
            $url = get_permalink($post->ID);
            $modificationDateTime = explode(' ', $post->post_modified);
            $content .= "<url><loc>{$url}</loc><lastmod>{$modificationDateTime[0]}</lastmod></url>";
        }
        $content .= '</urlset>';

        $result = file_put_contents($path, $content);

        if (false === $result) {
            WP_CLI::error("Failed to put sitemap into '{$path}'.");
            return;
        }
        WP_CLI::print_value($path);
    }
}

WP_CLI::add_command('sitemap', 'Sitemap_Command');
