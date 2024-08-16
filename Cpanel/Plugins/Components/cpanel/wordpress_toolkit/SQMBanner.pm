package Cpanel::Plugins::Components::cpanel::wordpress_toolkit::SQMBanner;

use Moo;
use cPstrict;

extends 'Cpanel::Plugins::Components::SQMBannerBase';

has '+feature_flag' => (
    is      => 'ro',
    default => 'cpanel-wptk.banner-cpanel.koality.plugin-banner.removed',
);

has "+markup" => (
    is      => 'ro',
    default => '<cp-koality-banner></cp-koality-banner>',
);

has '+js_url' => (
    is      => 'ro',
    default => 'plugin_banners/koality/sqm-banner/cp-koality-banner.js',
);

has '+slot' => (
    is      => 'ro',
    default => 'content-end',
);

1;
